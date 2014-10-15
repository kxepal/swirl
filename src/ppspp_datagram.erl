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

%% @doc Library for PPSPP over UDP, aka PPSPP protocol
%% <p>This module implements a library of functions necessary to
%% handle the wire-protocol of PPSPP over UDP, including
%% functions for encoding and decoding datagrams.</p>
%% @end

-module(ppspp_datagram).
-include("swirl.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% api
-export([handle/2,
         handle/1,
         unpack/3,
         pack/1]).

-opaque endpoint() :: {endpoint, list( endpoint_option())}.
-opaque endpoint_option() :: {ip, inet:ip_address()}
| {socket, inet:socket()}
| {port, inet:port_number()}
| {transport, udp}
| {uri, string()}
| ppspp_channel:channel().
-opaque datagram() :: {datagram, list(endpoint() | ppspp_messages:messages())}.
-export_type([endpoint/0,
              endpoint_option/0,
              datagram/0]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc receives datagram from peer_worker, parses & delivers to matching channel
%% @spec handle_datagram() -> ok
%% @end
-spec handle({udp, inet:socket(), inet:ip_address(), inet:port_number(),
              binary()}, any()) -> ok.

handle({udp, Socket, Peer_IP_Address, Peer_Port, Maybe_Datagram}, State) ->
    Channel = ppspp_channel:get_channel(Maybe_Datagram),
    Endpoint = build_endpoint(udp, Socket, Peer_IP_Address, Peer_Port, Channel),
    {ok, Parsed_Datagram} = unpack(Maybe_Datagram, Endpoint, State),
    % NB usually called from spawned process, so return values are ignored
    handle(Parsed_Datagram).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc translates raw udp packet into a tidy structure for later use
%% @spec
%% @end

-spec peer_to_string(inet:ip_address(), inet:port_number()) -> string().

peer_to_string(Peer, Port) ->
    lists:flatten([[inet_parse:ntoa(Peer)], $:, integer_to_list(Port)]).

-spec build_endpoint(udp, inet:socket(), inet:ip_address(), inet:port_number(),
                     ppspp_channel:channel()) ->  endpoint().
build_endpoint(udp, Socket, IP, Port, Channel) ->
    Channel_Name = ppspp_channel:channel_to_string(Channel),
    Peer_as_String = peer_to_string(IP, Port),
    Endpoint_as_URI = lists:concat([ Peer_as_String, "#", Channel_Name]),
    Endpoint = {endpoint, orddict:from_list([{ip, IP},
                                             {channel, Channel},
                                             {port, Port},
                                             {uri, Endpoint_as_URI},
                                             {transport, udp},
                                             {socket, Socket} ])},
    ?DEBUG("dgram: received udp from ~s~n", [Endpoint_as_URI]),
    Endpoint.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Extract PPSPP channel ID from header of datagram
%% <p>  Each PPSPP datagram contains as the first 4 byes the inbount channel ID.
%% </p>
%% @end

-spec handle(datagram()) -> ok.
handle(Datagram) ->
    _Transport = orddict:fetch(transport, Datagram),
    lists:foreach(
      fun(Message) -> ppspp_message:handle(Message) end,
      orddict:fetch(messages,Datagram)),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc unpack a UDP packet into a PPSPP datagram using erlang term format
%% <p>  Deconstruct PPSPP UDP datagram into multiple erlang terms, including
%% <ul>
%% <li>Endpoint containing opaque information about Transport</li>
%% <li>list of Messages</li>
%% <li>Opaque orddict for Options, within a handshake message</li>
%% <ul>
%% A single datagram MAY contain multiple PPSPP messages; these will be handled
%% recursively as needed.
%% </p>
%% @end

%% packet() = [
%% TODO revisit specs
%% {transport, ppspp_transport()},
%% {messages, ppspp_messages()}
%% ].

-spec unpack(binary(), endpoint(), any()) -> datagram().
unpack(Datagram, _Peer, _State ) ->
    {Channel, Maybe_Messages} = ppspp_channel:unpack_with_rest(Datagram),
    ?DEBUG("dgram: received on channel ~p~n",
           [ppspp_channel:channel_to_string(Channel)]),
    {ok, Parsed_Messages} = ppspp_message:unpack(Maybe_Messages),
    Datagram = orddict:from_list(Channel, {messages, Parsed_Messages}),
    {ok, Datagram}.

-spec pack(datagram()) -> binary().
pack(_Datagram) -> <<>>.

