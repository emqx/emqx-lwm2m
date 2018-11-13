%%--------------------------------------------------------------------
%% Copyright (c) 2016-2017 EMQ Enterprise, Inc. (http://emqtt.io)
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

-author("Feng Lee <feng@emqtt.io>").

-include("emqx_lwm2m.hrl").

-export([start/0, start/1, stop/0]).

-define(LOG(Level, Format, Args),
    lager:Level("LWM2M: " ++ Format, Args)).


start() ->
    Port = application:get_env(?APP, port, 5683),
    start(Port).

start(Port) ->
    lwm2m_coap_server:start(),
    lwm2m_coap_server:start_udp(lwm2m_udp_socket, Port),

    CertFile = application:get_env(?APP, certfile, ""),
    KeyFile = application:get_env(?APP, keyfile, ""),
    case (filelib:is_regular(CertFile) andalso filelib:is_regular(KeyFile)) of
        true ->
            lwm2m_coap_server:start_dtls(lwm2m_dtls_socket, Port+1, [{certfile, CertFile}, {keyfile, KeyFile}]);
        false ->
            ?LOG(error, "certfile ~p or keyfile ~p are not valid, turn off coap DTLS", [CertFile, KeyFile])
    end,

    lwm2m_coap_server_registry:add_handler([<<"rd">>], emqx_lwm2m_coap_resource, undefined).


stop() ->
    lwm2m_coap_server:stop_udp(lwm2m_udp_socket),
    lwm2m_coap_server:stop_dtls(lwm2m_dtls_socket),
    lwm2m_coap_server:stop(undefined).




% end of file



