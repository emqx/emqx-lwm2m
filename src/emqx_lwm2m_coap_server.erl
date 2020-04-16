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
    Port = proplists:get_value(port, Opts, 5683),
    DtlsPort = proplists:get_value(dtls_port, Opts, 5684),

    Opts1 = proplists:delete(port, Opts),
    Opts2 = proplists:delete(dtls_port, Opts1),

    lwm2m_coap_server:start_udp(lwm2m_udp_socket, Port, Opts2),

    CertFile = application:get_env(?APP, certfile, ""),
    KeyFile = application:get_env(?APP, keyfile, ""),
    UdpOption = proplists:get_value(opts, Opts2, []),
    case (filelib:is_regular(CertFile) andalso filelib:is_regular(KeyFile)) of
        true ->
            lwm2m_coap_server:start_dtls(lwm2m_dtls_socket, DtlsPort, [{certfile, CertFile}, {keyfile, KeyFile} | UdpOption]);
        false ->
            ?LOG(error, "certfile ~p or keyfile ~p are not valid, turn off coap DTLS", [CertFile, KeyFile])
    end.

stop() ->
    lwm2m_coap_server:stop_udp(lwm2m_udp_socket),
    lwm2m_coap_server:stop_dtls(lwm2m_dtls_socket),
    lwm2m_coap_server:stop(undefined).
% end of file
