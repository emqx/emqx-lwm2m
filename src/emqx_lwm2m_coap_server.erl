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
    logger:Level("LWM2M: " ++ Format, Args)).

start() ->
    {ok, _} = application:ensure_all_started(lwm2m_coap),

    ResourceHandlers = [
        {[<<"rd">>], emqx_lwm2m_coap_resource, undefined}
    ],
    lwm2m_coap_server:start_registry(ResourceHandlers),


    Opts = application:get_env(?APP, options, []),

    LbOpt = proplists:get_value(lb, Opts, undefined),
    UdpOpts = proplists:get_value(opts, Opts, []),

    start_udp(LbOpt, UdpOpts),
    start_dtls().

start_udp(LbOpt, Opts) ->
    BindUdps = application:get_env(?APP, bind_udp, [{5683, []}]),
    lists:foreach(fun({Port, InetOpt}) ->
        Name = process_name(lwm2m_udp_socket, Port),
        lwm2m_coap_server:start_udp(Name, Port, [{lb, LbOpt}, {opts, InetOpt ++ Opts}])
    end, BindUdps).

start_dtls() ->
    CertFile = application:get_env(?APP, certfile, ""),
    KeyFile = application:get_env(?APP, keyfile, ""),
    case (filelib:is_regular(CertFile) andalso filelib:is_regular(KeyFile)) of
        true ->
            BindDtls = application:get_env(?APP, bind_dtls, [{5684, []}]),
            lists:foreach(fun({DtlsPort, InetOpt}) ->
                Name = process_name(lwm2m_dtls_socket, DtlsPort),
                lwm2m_coap_server:start_dtls(Name, DtlsPort, InetOpt ++ [{certfile, CertFile}, {keyfile, KeyFile}])
            end, BindDtls);
        false ->
            ?LOG(error, "certfile ~p or keyfile ~p are not valid, turn off coap DTLS", [CertFile, KeyFile])
    end.

process_name(Mod, Port) ->
    list_to_atom(atom_to_list(Mod) ++ "_" ++ integer_to_list(Port)).

stop() ->
    stop_udp(),
    stop_dtls(),
    lwm2m_coap_server:stop(undefined).

stop_udp() ->
    BindUdps = application:get_env(?APP, bind_udp, [{5683, []}]),
    lists:foreach(fun({Port, _}) ->
        Name = process_name(lwm2m_udp_socket, Port),
        lwm2m_coap_server:stop_udp(Name)
    end, BindUdps).

stop_dtls() ->
    BindDtls = application:get_env(?APP, bind_dtls, [{5684, []}]),
    lists:foreach(fun({Port, _}) ->
        Name = process_name(lwm2m_dtls_socket, Port),
        lwm2m_coap_server:stop_dtls(Name)
    end, BindDtls).

% end of file
