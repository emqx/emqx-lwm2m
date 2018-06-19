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

-define(APP, emqx_lwm2m).


-record(coap_mqtt_auth, {clientid, username, password}).

-define(OMA_ALTER_PATH_RT, <<"\"oma.lwm2m\"">>).

-define(MQ_COMMAND_ID,         <<"CmdID">>).
-define(MQ_COMMAND,            <<"requestID">>).
-define(MQ_BASENAME,           <<"BaseName">>).
-define(MQ_ARGS,               <<"Arguments">>).

-define(MQ_VALUE_TYPE,         <<"ValueType">>).
-define(MQ_VALUE,              <<"Value">>).
-define(MQ_ERROR,              <<"Error">>).
-define(MQ_RESULT,             <<"Result">>).

-define(ERR_NO_XML,             <<"No XML Definition">>).
-define(ERR_NOT_ACCEPTABLE,     <<"Not Acceptable">>).
-define(ERR_METHOD_NOT_ALLOWED, <<"Method Not Allowed">>).
-define(ERR_NOT_FOUND,          <<"Not Found">>).
-define(ERR_UNAUTHORIZED,       <<"Unauthorized">>).
-define(ERR_BAD_REQUEST,        <<"Bad Request">>).


-define(LWM2M_FORMAT_PLAIN_TEXT, 0).
-define(LWM2M_FORMAT_LINK,       40).
-define(LWM2M_FORMAT_OPAQUE,     42).
-define(LWM2M_FORMAT_TLV,        11542).
-define(LWMWM_FORMAT_JSON,       11543).

%-record(lwm2m_query, {epn, life_time, sms, lwm2m_ver, binding, object_list = []}).
-record(lwm2m_context, {epn, location}).

%% LwM2M Client Registration Interface
-define(topic_register(Epn), <<"lwm2m/", Epn/binary, "/ul/reg/register">>).
-define(topic_update(Epn), <<"lwm2m/", Epn/binary, "/ul/reg/update">>).
-define(topic_deregister(Epn), <<"lwm2m/", Epn/binary, "/ul/reg/de_register">>).

%% LwM2M Device Management & Service Enablement Interface
-define(topic_read(Epn, ReqID), <<"lwm2m/", Epn/binary, "/dl/mgmt/read/", ReqID/binary>>).
-define(topic_read_response(Epn, ReqID), <<"lwm2m/", Epn/binary, "/ul/mgmt/read/", ReqID/binary>>).

-define(topic_discover(Epn, ReqID), <<"lwm2m/", Epn/binary, "/dl/mgmt/discover/", ReqID/binary>>).
-define(topic_discover_response(Epn, ReqID), <<"lwm2m/", Epn/binary, "/ul/mgmt/discover/", ReqID/binary>>).

-define(topic_write(Epn, ReqID), <<"lwm2m/", Epn/binary, "/dl/mgmt/write/", ReqID/binary>>).
-define(topic_write_response(Epn, ReqID), <<"lwm2m/", Epn/binary, "/ul/mgmt/write/", ReqID/binary>>).

-define(topic_writeattr(Epn, ReqID), <<"lwm2m/", Epn/binary, "/dl/mgmt/write_attr/", ReqID/binary>>).
-define(topic_writeattr_response(Epn, ReqID), <<"lwm2m/", Epn/binary, "/ul/mgmt/write_attr/", ReqID/binary>>).

-define(topic_execute(Epn, ReqID), <<"lwm2m/", Epn/binary, "/dl/mgmt/execute/", ReqID/binary>>).
-define(topic_execute_response(Epn, ReqID), <<"lwm2m/", Epn/binary, "/ul/mgmt/execute/", ReqID/binary>>).

-define(topic_create(Epn, ReqID), <<"lwm2m/", Epn/binary, "/dl/mgmt/create/", ReqID/binary>>).
-define(topic_create_response(Epn, ReqID), <<"lwm2m/", Epn/binary, "/ul/mgmt/create/", ReqID/binary>>).

-define(topic_delete(Epn, ReqID), <<"lwm2m/", Epn/binary, "/dl/mgmt/delete/", ReqID/binary>>).
-define(topic_delete_response(Epn, ReqID), <<"lwm2m/", Epn/binary, "/ul/mgmt/delete/", ReqID/binary>>).

-define(topic_ack(Epn, ReqID), <<"lwm2m/", Epn/binary, "/ul/mgmt/ack/", ReqID/binary>>).

%% Information Reporting Interface
-define(topic_observe(Epn, ReqID), <<"lwm2m/", Epn/binary, "/dl/report/observe/", ReqID/binary>>).
-define(topic_cancelobserve(Epn, ReqID), <<"lwm2m/", Epn/binary, "/dl/report/cancel_observe/", ReqID/binary>>).

-define(topic_notify(Epn, ReqID), <<"lwm2m/", Epn/binary, "/ul/report/notify/", ReqID/binary>>).
