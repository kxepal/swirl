%% -*- tab-width: 4;erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ft=erlang ts=4 sw=4 et
%% Licensed under the Apache License, Version 2.0 (the "License"); you may not
%% use this file except in compliance with the License. You may obtain a copy
%% of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
%% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
%% License for the specific language governing permissions and limitations
%% under the License.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc the module contains the funcitons for the leecher and seeder.
%% @end
-module(peer_core).

-include("../include/ppspp_records.hrl").

-export([init_server/2,
         update_state/3,
         get_peer_state/2,
         piggyback/2,
         update_ack_range/2,
         get_bin_list/3,
         fetch_uncles/3,
         fetch/2,
         remove/2]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Initialize the gen_server.
%% @end
init_server(static, {Swarm_ID, State_Table}) ->
    State =
    #peer{
       type         = static,
       state        = normal,
       server_data  = orddict:new(),
       peer_table   = State_Table,
       mtree        = Swarm_ID,
       options      =
       #options{
          ppspp_swarm_id               = Swarm_ID, 
          ppspp_integrity_check_method = ?PPSPP_DEFAULT_INTEGRITY_CHECK_METHOD
         }
      },

    {ok, State};

%% remaining types are live and injector. swarm options will remain same
init_server(Type, {Swarm_ID, State_Table}) ->
    State =
    #peer{
       type         = Type,
       state        = tune_in,
       server_data  = orddict:new(),
       peer_table   = State_Table,
       mtree        = Swarm_ID,
       options      =
       #options{
          ppspp_swarm_id               = Swarm_ID, 
          ppspp_live_discard_window    = ?PPSPP_DEFAULT_LIVE_DISCARD_WINDOW,
          ppspp_integrity_check_method =
          ?PPSPP_DEFAULT_LIVE_INTEGRITY_CHECK_METHOD,
          ppspp_live_signature_algorithm =
          ?PPSPP_DEFAULT_LIVE_SIGNATURE_ALGORITHM
         }
      },
    {ok, State}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc update the State variable on the arrival of packets from different
%% peers
%% @end
update_state(Server_Type, Msg, State) ->
    %% TODO get the state of peer from peer_state table and store it in State
    %% peer_state in ETS table will be of the form :{Peer_Name, Peer_State}
    %% Where Peer_Name : {Peer_adderss, seeder} and
    %% Peer_State : incase the peer is connected to seeder then Peer_State will
    %% be orddict containing "range" of chunks ACKed and 
    %% incase peer is connected to leecher orddict will contain "range"
    %% received by the leecher from that peer and "integrity" messages recevied
    %% from that peer
    %% NOTE : if peer lookup fails then add the peer to the table with the new
    %% dict as follows :
    %% for leecher :
    %%   orddict:from_list([{range, []},
    %%                      {integrity,
    %%                      orddict:from_list([{bin, hash}, {bin, hash} ..])}])
    %% for seeder:
    %%   orddict:from_list([{range, []}])
    %%
    %% State#peer.peer_state will contain ACKed Chunk_IDs
    %% TODO add channel ID to the Peer
    Peer        = orddict:key(endpoint, lists:keyfind(peer, 1, Msg)),
    Peer_State  = get_peer_state(State#peer.peer_table, {Peer, Server_Type}),
    New_State   = State#peer{peer = Peer, peer_state = Peer_State},
    {ok, New_State}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc get_peer_state/2 : get the state of the peer from the peer_table and if
%% not present then initilize empty state and return that.
%% @end
get_peer_state(Table, {Peer, Server_Type}) ->
    case peer_store:lookup(Table, {Peer, Server_Type}) of
        {error, _}  ->
            peer_store:insert_new(Table, {Peer, Server_Type}),
            get_peer_state(Table, {Peer, Server_Type});
        {ok, State} -> State
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc get_peer_state/2 : get the state of the peer from the peer_table and if
%% not present then initilize empty state and return that.
%% @end
piggyback(have, {State, Latest_Munro}) ->
    Server_Data = State#peer.server_data,
    case orddict:find(have, Server_Data) of
        %% add "have" Payload if not present
        error   ->
            New_Data = orddict:append(have, Latest_Munro, Server_Data),
            orddict:append(have_peers, State#peer.peer, New_Data);
        %% if Latest munro is more recent then overite the previous munro
        [Munro] when Latest_Munro > Munro ->
            New_Data = orddict:store(have, Munro, Server_Data),
            orddict:store(have_peers, State#peer.peer, New_Data);
        %% store the peers with the latest munro .
        [Munro] when Latest_Munro =:= Munro ->
            orddict:append(have_peers, State#peer.peer, Server_Data);
        _ ->
            Server_Data
    end;

piggyback(integrity, {State, Bin, Hash}) ->
    Peer_State = State#peer.peer_state,
    orddict:append(integrity, {Bin, Hash}, Peer_State).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc when new bin is received in ACK, we get the previously ACKed bins from
%% State and filter those bins that don't lie in the range of this Bin so as to
%% get list of bins that correspond to the range that has been acked by the
%% peer.
%% @end
update_ack_range(New_Bin, Peer_State) ->
    New_Range = lists:filter(
      fun(Bin) ->
              not mtree_core:lies_in(Bin, mtree_core:bin_to_range(New_Bin))
      end, orddict:fetch(ack_range, Peer_State)),

    [New_Bin | New_Range].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc return list of bins to request for live stream :
%% [Munro_Root1, bins ... , Munro_Root2, bins ..]
%% the bins that follow the Munro_Root lie in the range of the Munro_Root.
%% @end
get_bin_list({End_Munro, End_Munro}, {Start, End}, Acc) ->
    {ok, lists:concat([Acc, [End_Munro | lists:seq(Start, End, 2)]])};
get_bin_list({Start_Munro, End_Munro}, {Start, End}, Acc) ->
    [_, Last] = mtree_core:bin_to_range(Start_Munro),
    New_Acc   = lists:concat([Acc, [Start_Munro | lists:seq(Start, Last, 2)]]),
    {ok, Munro_Root} = mtree:get_next_munro(Start_Munro),
    get_bin_list({Munro_Root, End_Munro}, {Last+2, End}, New_Acc).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc fetch_uncles/3 : gets the required uncles for live & static stream 
%% @end
%% TODO check if the previous Leaf (ie Leaf -2) has been ACKed, if not then get
%% all the uncles corresponding to the current hash.
fetch_uncles(static, State, Leaf) ->
    mtree:get_uncle_hashes(State#peer.mtree, Leaf);
fetch_uncles(live, State, Leaf) ->
    mtree:get_munro_uncles(State#peer.mtree, Leaf). 

%% fetches keys from orddict
fetch(Field, Payload) ->
    orddict:fetch(Field, Payload).

%% remove element from the dict.
remove(Element, Payload) ->
    orddict:erase(Element, Payload).
