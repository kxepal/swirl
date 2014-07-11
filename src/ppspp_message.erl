%% -*- tab-width: 4;erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ft=erlang ts=4 sw=4 et
%% Licensed under the Apache License, Version 2.0 (the "License"); you may not
%% use this file except in compliance with the License. You may obtain a copy of
%% the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
%% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
%% License for the specific language governing permissions and limitations under
%% the License.

%% @doc Library for PPSPP over UDP, aka Swift protocol
%% <p>This module implements a library of functions necessary to
%% handle the wire-protocol of PPSPP over UDP, including
%% functions for encoding and decoding messages.</p>
%% @end

-module(ppspp_message).
%-include("ppspp.hrl").
-include("ppspp_records.hrl").
-include("swirl.hrl").

-ifdef(TEST).
-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").
-endif.

%% api
-export([unpack/1,
         pack/1,
         validate_message_type/1,
         handle/3]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% api
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc unpack a datagram segment into a PPSPP message using erlang term format
%% <p>  Deconstruct PPSPP UDP datagram into multiple erlang terms, including
%% parsing any additional data within the same segment. Any parsing failure
%% is fatal & will propagate back to the attempted datagram unpacking.
%% <ul>
%% <li>Message type</li>
%% <li>orddict for Options</li>
%% <ul>
%% </p>
%% @end

%% message() = [
%% TODO revisit specs
%% {options, ppspp_options()},
%% {message_type, ppspp_message_type()}
%% ].

%%-spec unpack(binary() -> ppspp_message()).

unpack(Maybe_Messages) when is_binary(Maybe_Messages) ->
    unpack(Maybe_Messages, []).

%% if the binary is empty, all messages were parsed successfully
unpack( <<>>, Parsed_Messages) ->
    {ok, lists:reverse(Parsed_Messages)};
%% otherwise try to unpack another valid message, peeling off and parsing
%% recursively the remainder, accumulating valid (parsed) messages.
%% A failure anywhere in a message ultimately causes the entire datagram
%% to be rejected.
unpack(<<Maybe_Message_Type:?PPSPP_MESSAGE_SIZE, Rest/binary>>, Parsed_Messages) ->
    {ok, Type} = validate_message_type(Maybe_Message_Type),
    [{ok, Parsed_Message}, Maybe_More_Messages] = parse(Type, Rest),
    unpack(Maybe_More_Messages, [Parsed_Message | Parsed_Messages]);
unpack(_Maybe_Messages, _Rest) -> {error, ppspp_invalid_message}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
pack(_) -> ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% private
%%-spec unpack(binary() -> ppspp_message_type()).
validate_message_type(Maybe_Message_Type)
  when is_integer(Maybe_Message_Type),
       Maybe_Message_Type < ?PPSPP_MAXIMUM_MESSAGE_TYPE ->
    %% message types in the current spec version
    Message_Type = case <<Maybe_Message_Type:?PPSPP_MESSAGE_SIZE>> of
                       ?HANDSHAKE -> handshake;
                       ?DATA -> data;
                       ?ACK -> ack;
                       ?HAVE -> have;
                       ?INTEGRITY -> integrity;
                       ?PEX_RESv4 -> pex_resv4;
                       ?PEX_REQ -> pex_req;
                       ?SIGNED_INTEGRITY -> signed_integrity;
                       ?REQUEST -> request;
                       ?CANCEL -> cancel;
                       ?CHOKE -> choke;
                       ?UNCHOKE -> unchoke;
                       ?PEX_RESv6 -> pex_resv6;
                       ?PEX_REScert -> pex_rescert;
                       _  -> ppspp_message_type_not_yet_implemented
                   end,
    ?DEBUG("message: parser got valid message type ~p~n", [Message_Type]),
    {ok, Message_Type};
%% message types that are not acceptable eg peer is using more recent spec
validate_message_type(_Maybe_Message_Type) ->
    ?DEBUG("message: parser got invalid message type ~p~n", [_Maybe_Message_Type]),
    {error, ppspp_message_type_not_recognised}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%-spec ... parse takes a msg_type, _data, and returns
%%    {error, something} or {ok, {key, orddict}} for the unpacked message
%%    [{Type, Parsed_Message}, Maybe_More_Messages]
%% TODO parse should probably be unpack/2 and then drop validate_message_type/1
parse(handshake, <<Channel:?PPSPP_CHANNEL_SIZE, Maybe_Options/binary>>) ->
    [{ok, Options}, Maybe_Messages] = ppspp_options:unpack(Maybe_Options),
    [{ok, {handshake, orddict:store(channel, Channel, Options) }}, Maybe_Messages];

parse(data, _Rest) ->
    [{data, parsed_msg}, _Rest];
parse(ack, _Rest) ->
    [{ack, parsed_msg}, _Rest];
parse(have, _Rest) ->
    [{have, parsed_msg}, _Rest];
parse(integrity, _Rest) ->
    [{integrity, parsed_msg}, _Rest];
parse(pex_resv4, _Rest) ->
    [{pex_resv4, parsed_msg}, _Rest];
parse(pex_req, _Rest) ->
    [{pex_req, parsed_msg}, _Rest];
parse(signed_integrity, _Rest) ->
    [{signed_integrity, parsed_msg}, _Rest];
parse(request, _Rest) ->
    [{request, parsed_msg}, _Rest];
parse(cancel, _Rest) ->
    [{cancel, parsed_msg}, _Rest];
parse(choke, _Rest) ->
    [{choke, parsed_msg}, _Rest];
parse(unchoke, _Rest) ->
    [{unchoke, parsed_msg}, _Rest];
parse(pex_resv6, _Rest) ->
    [{pex_resv6, parsed_msg}, _Rest];
parse(pex_rescert, _Rest) ->
    [{pex_rescert, parsed_msg}, _Rest];
parse(ppspp_message_type_not_yet_implemented, _Rest) ->
    [{ppspp_message_parser_not_implemented, parsed_msg}, _Rest];
%% TODO confirm we shouldn't be able to get here by using -spec()
parse(_, _Rest) ->
    {error, ppspp_message_type_not_parsable}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% HANDLE MESSAGES
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%-spec ... handle takes a tuple of {type, message_body} where body is a
%%    parsed orddict message and returns either
%%    {error, something} or tagged tuple for the unpacked message
%%    {ok, reply} where reply is probably an orddict to be sent to the
%%    alternate peer.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% HANDSHAKE
%% The payload of the HANDSHAKE message is a channel ID (see Section 3.11) and
%% a sequence of protocol options.  Example options are the content integrity
%% protection scheme used and an option to specify the swarm identifier.  The
%% complete set of protocol options are specified in Section 7.
handle({Type, seeder}, {handshake, Payload}, State) ->
    {ok, HANDSHAKE} = prepare(Type, {handshake, Payload}, State),
    {ok, HAVE}      = prepare(Type, {have, orddict:new()}, State),
    {ok, [HANDSHAKE | HAVE]};

handle({_Type, leecher}, {handshake,_Payload},_State) ->
    %% TODO : discuss what will the leecher do with the HANDSHAKE msg.
    {ok, []};

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% ACK : Update peer_state in State.
handle(_Type_Role, {ack, Payload}, State) ->
    %% TODO discuss whether to update the ack_range in ETS here itself or not.
    Bin            = peer_core:fetch(range, Payload),
    Peer_State     = State#peer.peer_state,
    New_Ack_Range  = peer_core:update_ack_range(Bin, Peer_State),
    New_Peer_State = orddict:store(ack_range, New_Ack_Range, Peer_State),
    {ok, State#peer{peer_state = New_Peer_State}};

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% HAVE
handle({static, leecher}, {have, _Payload},_State) ->
    %% TODO : discuss how to request RANGE
    ok;
handle({live, leecher}, {have, Payload}, #peer{state=tune_in} = State) ->
    %% HAVE in live stream should be piggybacked so as to figure out the latest
    %% munro hash.
    %% TODO discuss if address of peers containing the highest munro needs to
    %% be stored.
    %% TODO discuss how to stop piggybacking and make REQUEST for the latest
    %% data
    Latest_Munro    = peer_core:fetch(range, Payload),
    %% update the munro if latest munro is greater than the current one.
    New_Server_Data = peer_core:piggyback(have, {State, Latest_Munro}),
    {ok, State#peer{server_data = New_Server_Data}};

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% INTEGRITY
%% TODO figure out how to handle integrity messages. The leecher will recevive
%% integrity message which can span multiple chunks so we need to piggybank
%% integrity messages untill the right DATA packet arrives DOUBT : how will
%% that for which data packet are the integrity messages ment for !!!
handle({static, leecher}, {integrity, _Payload},_State) ->
    ok;

handle({live, leecher}, {integrity, Payload}, State) ->
    Bin             = peer_core:fetch(range, Payload),
    Hash            = peer_core:fetch(hash, Payload),
    New_Peer_State  = peer_core:piggyback(integrity, {State, Bin, Hash}),
    {ok, State#peer{peer_state = New_Peer_State}};

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% SIGNED_INTEGRITY
handle({live, leecher}, {signed_integrity, Payload}, State) ->
    Munro_Root = peer_core:fetch(range, Payload),
    Peer_State = State#peer.peer_state,

    %%
    Munro_Hash = peer_core:fetch(Munro_Root,orddict:find(integrity,Peer_State)),
    Signature  = peer_core:fetch(signature, Payload),
    Public_Key = (State#peer.options)#options.ppspp_swarm_id,

    %% verify the signature of the munro hash. we use none becoz Munro Hash is
    %% sha hash.
    true       = public_key:verify(Munro_Hash, none, Signature, Public_Key),
    mtree_store:insert(State#peer.mtree, {Munro_Root, Munro_Hash, empty}),

    %% remove the Munro_Root from integrity.
    New_Integrity = peer_core:remove(Munro_Root, orddict:find(integrity,
                                                              Peer_State)),
    New_Peer_State = orddict:store(integrity, New_Integrity, Peer_State),
    {ok, State#peer{peer_state = New_Peer_State}};

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% REQUEST
handle({static, _}, {request, [_Start, _End]},_State) ->
    %% TODO implement static code.
    %handle_REQ_List({static, State}, REQ_List, []);
    ok;

handle({live, _}, {request, Payload}, State) ->
    [Start, End]  = mtree_core:bin_to_range(peer_core:fetch(range, Payload)),
    Start_Munro   = mtree_core:get_munro_root(Start),
    End_Munro     = mtree_core:get_munro_root(End),
    %% prepare list of requested chunk IDs with their corresponding Munro_Root.
    {ok, Request_List} = peer_core:get_bin_list({Start_Munro, End_Munro},
                                                {Start, End}, []),
    %% Request_List : [Munro_Root1, bins ... , Munro_Root2, bins ..]
    %% the bins that follow the Munro_Root lie in the range of the Munro_Root.
    {ok, process_request({live, State}, Request_List, [])};

handle(_Type_Role, Message,_State) ->
    ?DEBUG("message: handler not yet implemented ~p~n", [Message]),
    {ok, ppspp_message_handler_not_yet_implemented}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% LOCAL INTERNAL FUNCTIONs
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc handle_request/3 : REQ_List and return value will be as follows
%% REQ_List (live): [Munro_Root1, Leaf_bin ... , Munro_Root2, Leaf_bins ..]
%% Returns (live) : [INTEGRITY, SIGNED_INTEGRITY, INTEGRITY, DATA, ..] messages
%% REQ_List (static) : [Leaf_bin, ...]
%% Returns (static)  : [INTEGRITY, DATA, INTEGRITY, DATA, ...] messages
%% @end
process_request(_, [], Acc) ->
    lists:reverse(Acc);
process_request({Type, State}, [Leaf | Rest], Acc) when Leaf rem 2 =:= 0 ->
    %% TODO get the uncle hashes
    %% TODO decide DICUSS when to get all_uncles and when to get only uncles
    %% based on previous ACKs.
    Uncle_Hashes = peer_core:fetch_uncles(Type, State, Leaf),
    INTEGRITY    = lists:map(
                     fun({Uncle, Hash}) ->
                        {ok, Integrity} = prepare(live, {integrity, Uncle,
                                                        Hash}, State),
                        Integrity
                     end, Uncle_Hashes),
    {ok, DATA}   = prepare(live, {data, Leaf}, State),
    process_request({live, State}, Rest, lists:flatten([DATA,INTEGRITY | Acc]));
process_request({live, State}, [Munro_Root | Rest], Acc) ->
    {ok, INTEGRITY}        = prepare(live, {integrity, Munro_Root,
                                            orddict:new()}, State),
    {ok, SIGNED_INTEGRITY} = prepare(live, {signed_integrity, Munro_Root,
                                            orddict:new()}, State),
    process_request({live, State}, Rest, [SIGNED_INTEGRITY, INTEGRITY | Acc]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% PREPARE MESSAGES
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% HANDSHAKE message is of the sort :
%% {handshake, [{channel, }, {options, [{}, {}, ...]}]
prepare(Type, {handshake,_Payload}, State) ->
    Sub_Options =
      [ {ppspp_swarm_id, (State#peer.options)#options.ppspp_swarm_id},
        {ppspp_version,  (State#peer.options)#options.ppspp_version},
        {ppspp_minimum_version,
         (State#peer.options)#options.ppspp_minimum_version},
        {ppspp_chunking_method,
         (State#peer.options)#options.ppspp_chunking_method},
        {ppspp_integrity_check_method,
         (State#peer.options)#options.ppspp_integrity_check_method},
        {ppspp_merkle_hash_function,
         (State#peer.options)#options.ppspp_merkle_hash_function}],

    %% Add LIVE streaming options incase the seeder is in live stream swarm.
    Options_List =
    if
        Type =:= live orelse Type =:= injector ->
            [{ppspp_live_signature_algorithm,
              (State#peer.options)#options.ppspp_live_signature_algorithm},
             {ppspp_live_disard_window,
              (State#peer.options)#options.ppspp_live_discard_window} |
             Sub_Options];
        true -> Sub_Options
    end,

    Options = orddict:from_list(Options_List),
    %% TODO : allocate free channel & store it in Payload as source channel id
    %% TODO : discuss how to get the free Channel id
    Channel  = not_implemented,
    {ok, {handshake, orddict:from_list([{channel, Channel},
                                        {options, Options}])}};

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% ACK : {ack, [{range, [{Start,End}]}]
prepare(_Type, {ack, [Start, End]}, _State) ->
    {ok, {ack, orddict:from_list(range, [{Start, End}])}};

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% HAVE : {have, [{range, Bin}]
prepare(static, {have,_Payload}, State) ->
    %% {ok, Start, End} = mtree:get_data_range(State#state.mtree),
    Peaks = mtree:get_peak_hash(State#peer.mtree),
    Have  = [{have, orddict:from_list([{range, Bin}])} || {Bin, _} <- Peaks],
    {ok, Have};
prepare(_Live,  {have,_Payload}, State) ->
    %% HAVE in case of live stream only sends the latest munro
    {ok, Munro_Root, _} = mtree:get_latest_munro(State#peer.mtree),
    {ok, [{have, orddict:from_list([{range, Munro_Root}])}]};

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% REQUEST : {request, [{range, Bin}]}
%% TODO change the range to bins
prepare(_Type, {request, Bin}, _State) ->
    {ok, {request, orddict:from_list([{range, Bin}])}};

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% DATA : {data, [{range, Bin}, {timestamp, int}, {data, binary}]}
prepare(_Type, {data, Chunk_ID}, State) ->
    {ok, _Hash, Data} = mtree_store:lookup(State#peer.mtree, Chunk_ID),
    %% TODO : add ntp module and filter out the timestamp.
    Ntp_Timestamp = time, %% ntp:ask(),
    %% CAUTION : the range is set to a Chunk_ID.
    {ok, {data, orddict:from_list([{range, Chunk_ID},
                                   {timestamp, Ntp_Timestamp},
                                   {data, Data}])}};

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% INTEGRITY : {integrity, [{range, Bin}, {hash, binary}]
prepare(_Type, {integrity, Bin}, State) ->
    {ok, Hash, _Data} = mtree_store:lookup(State#peer.mtree, Bin),
    %% CAUTION : the range is set to a bin
    {ok, {integrity, orddict:from_list([{range, Bin}, {hash, Hash}])}};
prepare(_Type, {integrity, Bin, Hash}, _State) ->
    {ok, {integrity, orddict:from_list([{range, Bin}, {hash, Hash}])}};

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% SIGNED_INTEGRITY : {signed_integrity, [{range, Bin},
%%                                        {timestamp, Time},
%%                                        {signature, binary}]
prepare(live, {signed_integrity, Munro_Root}, State) ->
    {ok, _Hash, _Data} = mtree_store:lookup(State#peer.mtree, Munro_Root),
    %% TODO : add ntp module and filter out the timestamp.
    Ntp_Timestamp = time, %% ntp:ask(),
    Signture      = not_implemented,
    %% CAUTION : the range is set to a Munro_Root.
    {ok, {data, orddict:from_list([{range, Munro_Root},
                                   {timestamp, Ntp_Timestamp},
                                   {signature, Signture}])}}.
