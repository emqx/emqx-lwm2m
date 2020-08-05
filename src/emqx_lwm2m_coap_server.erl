%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_lwm2m_coap_server).

-include("emqx_lwm2m.hrl").

-export([ start/0
        , stop/0
        ]).

-define(LOG(Level, Format, Args),
    logger:Level("LwM2M: " ++ Format, Args)).

start() ->
    ResourceHandlers = [{[<<"rd">>], emqx_lwm2m_coap_resource, undefined}],
    lwm2m_coap_server:start_registry(ResourceHandlers),
    start_listeners().

stop() ->
    stop_listeners().

%%--------------------------------------------------------------------
%% Internal funcs
%%--------------------------------------------------------------------

start_listeners() ->
    lists:foreach(fun start_listener/1, listeners_confs()).

stop_listeners() ->
    lists:foreach(fun stop_listener/1, listeners_confs()).

start_listener({Proto, ListenOn, Opts}) ->
    case start_listener(Proto, ListenOn, Opts) of
        {ok, _Pid} ->
            io:format("Start lwm2m:~s listener on ~s successfully.~n",
                      [Proto, format(ListenOn)]);
        {error, Reason} ->
            io:format(standard_error, "Failed to start lwm2m:~s listener on ~s - ~0p~n!",
                      [Proto, format(ListenOn), Reason]),
            error(Reason)
    end.

start_listener(udp, ListenOn, Opts) ->
    lwm2m_coap_server:start_udp('lwm2m:udp', ListenOn, Opts);
start_listener(dtls, ListenOn, Opts) ->
    lwm2m_coap_server:start_dtls('lwm2m:dtls', ListenOn, Opts).

stop_listener({Proto, ListenOn, _Opts}) ->
    Ret = stop_listener(Proto, ListenOn),
    case Ret of
        ok -> io:format("Stop lwm2m:~s listener on ~s successfully.~n",
                        [Proto, format(ListenOn)]);
        {error, Reason} ->
            io:format(standard_error, "Failed to stop lwm2m:~s listener on ~s - ~p~n.",
                      [Proto, format(ListenOn), Reason])
    end,
    Ret.

stop_listener(udp, ListenOn) ->
    lwm2m_coap_server:stop_udp('lwm2m:udp', ListenOn);
stop_listener(dtls, ListenOn) ->
    lwm2m_coap_server:stop_dtls('lwm2m:dtls', ListenOn).

listeners_confs() ->
    listeners_confs(udp) ++ listeners_confs(dtls).

listeners_confs(udp) ->
    Udps = application:get_env(?APP, bind_udp, []),
    Opts = application:get_env(?APP, options, []),
    [{udp, Port, [{udp_options, InetOpts ++ Opts}]} || {Port, InetOpts} <- Udps];

listeners_confs(dtls) ->
    Dtls = application:get_env(?APP, bind_dtls, []),
    Opts = application:get_env(?APP, dtls_opts, []),
    [{dtls, Port, [{dtls_options, InetOpts ++ Opts}]} || {Port, InetOpts} <- Dtls].

format(Port) when is_integer(Port) ->
    io_lib:format("0.0.0.0:~w", [Port]);
format({Addr, Port}) when is_list(Addr) ->
    io_lib:format("~s:~w", [Addr, Port]);
format({Addr, Port}) when is_tuple(Addr) ->
    io_lib:format("~s:~w", [inet:ntoa(Addr), Port]).
