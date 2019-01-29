%% Copyright (c) 2013-2019 EMQ Technologies Co., Ltd. All Rights Reserved.
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


-module(emqx_lwm2m_app).

-author("Feng Lee <feng@emqtt.io>").

-behaviour(application).
-export([start/2, stop/1, prep_stop/1]).

-include("emqx_lwm2m.hrl").


start(_Type, _Args) ->
    Port = application:get_env(?APP, port, 5683),
    Pid = emqx_lwm2m_sup:start_link(),
    emqx_lwm2m_coap_server:start(Port),
    emqx_lwm2m_cfg:register(),
    Pid.

prep_stop(State) ->
    emqx_lwm2m_coap_server:stop(),
    emqx_lwm2m_cfg:unregister(),
    State.

stop(_State) ->
    ok.
