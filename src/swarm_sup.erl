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

-module(swarm_sup).
-include("swirl.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-spec test() -> term().
-endif.

-behaviour(supervisor).

%% api
-export([start_link/0]).

%% callbacks
-export([init/1]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% api
-spec start_link() -> {ok, pid()} | {error, any()}.

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% callbacks
-spec init([]) -> {ok,{{one_for_one, 10,60}, [] }}.
init([]) ->
    Workers = [],
    {ok, {{one_for_one, 10, 60}, Workers}}.

