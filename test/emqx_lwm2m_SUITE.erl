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

-module(emqx_lwm2m_SUITE).

-compile(export_all).

-define(PORT, 5783).

-define(LOGT(Format, Args), lager:debug("TEST_SUITE: " ++ Format, Args)).

-include("emqx_lwm2m.hrl").
-include_lib("lwm2m_coap/include/coap.hrl").
-include_lib("eunit/include/eunit.hrl").


all() -> [case01_register, case02_update_deregister, case03_register_wrong_version,
    case04_register_and_lifetime_timeout, case05_register_wrong_epn, case06_register_wrong_lifetime,
    case10_read, case11_read_object_tlv, case11_read_object_json, case12_read_resource_opaque, case13_read_no_xml,
    case20_write, case21_write_object, case22_write_error,
    case30_execute, case31_execute_error,
    case40_discover,
    case50_write_attribute,
    case60_observe].



init_per_suite(Config) ->
    lager_common_test_backend:bounce(debug),
    Config.

end_per_suite(Config) ->
    Config.


case01_register(_Config) ->
    application:set_env(?APP, port, ?PORT),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % ----------------------------------------
    % REGISTER command
    % ----------------------------------------
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId = 12,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=345&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3>, </4>, </5>">>},
                            [],
                            MsgId),
    #coap_message{type = ack, method = Method} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,created}, Method),
    timer:sleep(50),
    SubTopic = list_to_binary("lwm2m/"++Epn++"/command"),
    ?assertEqual([SubTopic], test_mqtt_broker:get_subscrbied_topics()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().


case02_update_deregister(_Config) ->
    application:set_env(?APP, port, ?PORT),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % ----------------------------------------
    % REGISTER command
    % ----------------------------------------
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId = 12,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=345&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3>, </4>, </5>">>},
                            [],
                            MsgId),
    timer:sleep(100),
    #coap_message{type = ack, method = Method, payload = Location} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,created}, Method),
    ?assertMatch(<<"/rd/", _Rest/binary>>, Location),
    LocationString = binary_to_list(Location),
    timer:sleep(50),
    SubTopic = list_to_binary("lwm2m/"++Epn++"/command"),
    ?assertEqual([SubTopic], test_mqtt_broker:get_subscrbied_topics()),

    % ----------------------------------------
    % UPDATE command
    % ----------------------------------------
    ?LOGT("start to send UPDATE command", []),
    MsgId2 = 27,
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b~s?lt=789", [?PORT, LocationString]),
                            #coap_content{payload = <<>>},
                            [],
                            MsgId2),
    #coap_message{type = ack, method = Method2} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,changed}, Method2),

    timer:sleep(50),

    % ----------------------------------------
    % DE-REGISTER command
    % ----------------------------------------
    ?LOGT("start to send DE-REGISTER command", []),
    MsgId3 = 52,
    test_send_coap_request( UdpSock,
                            delete,
                            sprintf("coap://127.0.0.1:~b~s", [?PORT, LocationString]),
                            #coap_content{payload = <<>>},
                            [],
                            MsgId3),
    timer:sleep(100),
    #coap_message{type = ack, method = Method3} = test_recv_coap_response(UdpSock),
    ?assertMatch({ok,deleted}, Method3),

    timer:sleep(100),
    ?assertEqual([], test_mqtt_broker:get_subscrbied_topics()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().



case03_register_wrong_version(_Config) ->
    application:set_env(?APP, port, ?PORT),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % ----------------------------------------
    % REGISTER command
    % ----------------------------------------
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId = 12,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=345&lwm2m=8.3", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3>, </4>, </5>">>},
                            [],
                            MsgId),
    #coap_message{type = ack, method = Method} = test_recv_coap_response(UdpSock),
    ?assertEqual({error,not_acceptable}, Method),
    timer:sleep(50),
    ?assertEqual([], test_mqtt_broker:get_subscrbied_topics()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().



case04_register_and_lifetime_timeout(_Config) ->
    application:set_env(?APP, port, ?PORT),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % ----------------------------------------
    % REGISTER command
    % ----------------------------------------
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId = 12,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=1&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3>, </4>, </5>">>},
                            [],
                            MsgId),
    timer:sleep(100),
    #coap_message{type = ack, method = Method, payload = Location} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,created}, Method),
    ?assertMatch(<<"/rd/", _Rest/binary>>, Location),
    timer:sleep(50),
    SubTopic = list_to_binary("lwm2m/"++Epn++"/command"),
    ?assertEqual([SubTopic], test_mqtt_broker:get_subscrbied_topics()),

    % ----------------------------------------
    % lifetime timeout
    % ----------------------------------------
    timer:sleep(4000),
    ?assertEqual([], test_mqtt_broker:get_subscrbied_topics()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().




case05_register_wrong_epn(_Config) ->
    application:set_env(?APP, port, ?PORT),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % ----------------------------------------
    % REGISTER command
    % ----------------------------------------
    MsgId = 12,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?lt=345&lwm2m=1.0", [?PORT]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3>, </4>, </5>">>},
                            [],
                            MsgId),
    #coap_message{type = ack, method = Method} = test_recv_coap_response(UdpSock),
    ?assertEqual({error,not_acceptable}, Method),
    timer:sleep(50),
    ?assertEqual([], test_mqtt_broker:get_subscrbied_topics()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().




case06_register_wrong_lifetime(_Config) ->
    application:set_env(?APP, port, ?PORT),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % ----------------------------------------
    % REGISTER command
    % ----------------------------------------
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId = 12,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3>, </4>, </5>">>},
                            [],
                            MsgId),
    #coap_message{type = ack, method = Method} = test_recv_coap_response(UdpSock),
    ?assertEqual({error,not_acceptable}, Method),
    timer:sleep(50),
    ?assertEqual([], test_mqtt_broker:get_subscrbied_topics()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().




case10_read(_Config) ->
    application:set_env(?APP, port, ?PORT),
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % step 1, device register ...
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId1 = 15,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=345&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3/0>, </4>, </5>">>},
                            [],
                            MsgId1),
    #coap_message{method = Method1, payload=Payload1} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,created}, Method1),
    ?assertMatch(<<"/rd/", _Rest/binary>>, Payload1),
    timer:sleep(50),
    SubTopic = list_to_binary("lwm2m/"++Epn++"/command"),
    ?assertEqual([SubTopic], test_mqtt_broker:get_subscrbied_topics()),


    % step2,  send a READ command to device
    CmdId = 206,
    CommandTopic = <<"lwm2m/", (list_to_binary(Epn))/binary, "/command">>,
    Command =   #{
                    ?MQ_COMMAND_ID         => CmdId,
                    ?MQ_COMMAND            => <<"Read">>,
                    ?MQ_BASENAME           => <<"/3/0/0">>
                },
    CommandJson = jsx:encode(Command),
    ?LOGT("CommandJson=~p", [CommandJson]),
    test_mqtt_broker:dispatch(CommandTopic, CommandJson, CommandTopic),
    timer:sleep(50),
    Request2 = test_recv_coap_request(UdpSock),
    #coap_message{method = Method2, options=Options2, payload=Payload2} = Request2,
    Path2 = get_coap_path(Options2),
    ?assertEqual(get, Method2),
    ?assertEqual(<<"/3/0/0">>, Path2),
    ?assertEqual(<<>>, Payload2),
    timer:sleep(50),

    test_send_coap_response(UdpSock, "127.0.0.1", ?PORT, {ok, content}, #coap_content{format = <<"text/plain">>, payload = <<"EMQ">>}, Request2, false),
    timer:sleep(100),

    PubTopic = list_to_binary("lwm2m/"++Epn++"/response"),
    ReadResult = jsx:encode(#{  ?MQ_COMMAND_ID   => CmdId,
                                ?MQ_COMMAND      => <<"Read">>,
                                ?MQ_RESULT       => #{bn=><<"/3/0/0">>, e=>[#{sv=><<"EMQ">>}]}
                             }),
    ?assertEqual({PubTopic, ReadResult}, test_mqtt_broker:get_published_msg()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().




case11_read_object_tlv(_Config) ->
    application:set_env(?APP, port, ?PORT),
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % step 1, device register ...
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId1 = 15,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=345&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3/0>, </4>, </5>">>},
                            [],
                            MsgId1),
    #coap_message{method = Method1, payload=Payload1} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,created}, Method1),
    ?assertMatch(<<"/rd/", _Rest/binary>>, Payload1),
    timer:sleep(50),
    SubTopic = list_to_binary("lwm2m/"++Epn++"/command"),
    ?assertEqual([SubTopic], test_mqtt_broker:get_subscrbied_topics()),


    % step2,  send a READ command to device
    CmdId = 206,
    CommandTopic = <<"lwm2m/", (list_to_binary(Epn))/binary, "/command">>,
    Command = #{?MQ_COMMAND_ID         => CmdId,
                ?MQ_COMMAND            => <<"Read">>,
                ?MQ_BASENAME           => <<"/3/0">>
            },
    CommandJson = jsx:encode(Command),
    test_mqtt_broker:dispatch(CommandTopic, CommandJson, CommandTopic),
    timer:sleep(50),
    Request2 = test_recv_coap_request(UdpSock),
    #coap_message{method = Method2, options=Options2, payload=Payload2} = Request2,
    Path2 = get_coap_path(Options2),
    ?assertEqual(get, Method2),
    ?assertEqual(<<"/3/0">>, Path2),
    ?assertEqual(<<>>, Payload2),
    timer:sleep(50),

    Tlv = <<16#08, 16#00, 16#3C, 16#C8, 16#00, 16#14, 16#4F, 16#70, 16#65, 16#6E, 16#20, 16#4D, 16#6F, 16#62, 16#69, 16#6C, 16#65, 16#20, 16#41, 16#6C, 16#6C, 16#69, 16#61, 16#6E, 16#63, 16#65, 16#C8, 16#01, 16#16, 16#4C, 16#69, 16#67, 16#68, 16#74, 16#77, 16#65, 16#69, 16#67, 16#68, 16#74, 16#20, 16#4D, 16#32, 16#4D, 16#20, 16#43, 16#6C, 16#69, 16#65, 16#6E, 16#74, 16#C8, 16#02, 16#09, 16#33, 16#34, 16#35, 16#30, 16#30, 16#30, 16#31, 16#32, 16#33>>,
    test_send_coap_response(UdpSock, "127.0.0.1", ?PORT, {ok, content}, #coap_content{format = <<"application/vnd.oma.lwm2m+tlv">>, payload = Tlv}, Request2, false),
    timer:sleep(100),

    PubTopic = list_to_binary("lwm2m/"++Epn++"/response"),
    ReadResult = jsx:encode(#{  ?MQ_COMMAND_ID          => CmdId,
                                ?MQ_COMMAND             => <<"Read">>,
                                ?MQ_RESULT              => #{   bn=><<"/3/0">>,
                                                                e=>[
                                                                    #{n=><<"0">>,sv=><<"Open Mobile Alliance">>},
                                                                    #{n=><<"1">>,sv=><<"Lightweight M2M Client">>},
                                                                    #{n=><<"2">>,sv=><<"345000123">>}]
                                                            }
                            }),
    ?assertEqual({PubTopic, ReadResult}, test_mqtt_broker:get_published_msg()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().



case11_read_object_json(_Config) ->
    application:set_env(?APP, port, ?PORT),
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % step 1, device register ...
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId1 = 15,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=345&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3/0>, </4>, </5>">>},
                            [],
                            MsgId1),
    #coap_message{method = Method1, payload=Payload1} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,created}, Method1),
    ?assertMatch(<<"/rd/", _Rest/binary>>, Payload1),
    timer:sleep(50),
    SubTopic = list_to_binary("lwm2m/"++Epn++"/command"),
    ?assertEqual([SubTopic], test_mqtt_broker:get_subscrbied_topics()),


    % step2,  send a READ command to device
    CmdId = 206,
    CommandTopic = <<"lwm2m/", (list_to_binary(Epn))/binary, "/command">>,
    Command = #{?MQ_COMMAND_ID         => CmdId,
        ?MQ_COMMAND            => <<"Read">>,
        ?MQ_BASENAME           => <<"/3/0">>
    },
    CommandJson = jsx:encode(Command),
    test_mqtt_broker:dispatch(CommandTopic, CommandJson, CommandTopic),
    timer:sleep(50),
    Request2 = test_recv_coap_request(UdpSock),
    #coap_message{method = Method2, options=Options2, payload=Payload2} = Request2,
    Path2 = get_coap_path(Options2),
    ?assertEqual(get, Method2),
    ?assertEqual(<<"/3/0">>, Path2),
    ?assertEqual(<<>>, Payload2),
    timer:sleep(50),

    Json = <<"{\"bn\":\"/3/0\",\"e\":[{\"n\":\"0\",\"sv\":\"Open Mobile Alliance\"},{\"n\":\"1\",\"sv\":\"Lightweight M2M Client\"},{\"n\":\"2\",\"sv\":\"345000123\"}]}">>,
    test_send_coap_response(UdpSock, "127.0.0.1", ?PORT, {ok, content}, #coap_content{format = <<"application/vnd.oma.lwm2m+json">>, payload = Json}, Request2, false),
    timer:sleep(100),

    PubTopic = list_to_binary("lwm2m/"++Epn++"/response"),
    ReadResult = jsx:encode(#{  ?MQ_COMMAND_ID          => CmdId,
                                ?MQ_COMMAND             => <<"Read">>,
                                ?MQ_RESULT              => #{   bn=><<"/3/0">>,
                                                                e=>[
                                                                    #{n=><<"0">>,sv=><<"Open Mobile Alliance">>},
                                                                    #{n=><<"1">>,sv=><<"Lightweight M2M Client">>},
                                                                    #{n=><<"2">>,sv=><<"345000123">>}]
                                                            }
                            }),
    ?assertEqual({PubTopic, ReadResult}, test_mqtt_broker:get_published_msg()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().


case12_read_resource_opaque(_Config) ->
    application:set_env(?APP, port, ?PORT),
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % step 1, device register ...
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId1 = 15,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=345&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3/0>, </4>, </5>">>},
                            [],
                            MsgId1),
    #coap_message{method = Method1, payload=Payload1} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,created}, Method1),
    ?assertMatch(<<"/rd/", _Rest/binary>>, Payload1),
    timer:sleep(50),
    SubTopic = list_to_binary("lwm2m/"++Epn++"/command"),
    ?assertEqual([SubTopic], test_mqtt_broker:get_subscrbied_topics()),


    % step2,  send a READ command to device
    CmdId = 206,
    CommandTopic = <<"lwm2m/", (list_to_binary(Epn))/binary, "/command">>,
    Command = #{?MQ_COMMAND_ID         => CmdId,
                ?MQ_COMMAND            => <<"Read">>,
                ?MQ_BASENAME           => <<"/3/0/8">>
            },
    CommandJson = jsx:encode(Command),
    test_mqtt_broker:dispatch(CommandTopic, CommandJson, CommandTopic),
    timer:sleep(50),
    Request2 = test_recv_coap_request(UdpSock),
    #coap_message{method = Method2, options=Options2, payload=Payload2} = Request2,
    Path2 = get_coap_path(Options2),
    ?assertEqual(get, Method2),
    ?assertEqual(<<"/3/0/8">>, Path2),
    ?assertEqual(<<>>, Payload2),
    timer:sleep(50),

    Opaque = <<20, 21, 22, 23>>,
    test_send_coap_response(UdpSock, "127.0.0.1", ?PORT, {ok, content}, #coap_content{format = <<"application/octet-stream">>, payload = Opaque}, Request2, false),
    timer:sleep(100),

    PubTopic = list_to_binary("lwm2m/"++Epn++"/response"),
    ReadResult = jsx:encode(#{  ?MQ_COMMAND_ID          => CmdId,
                                ?MQ_COMMAND             => <<"Read">>,
                                ?MQ_RESULT              => #{   bn=><<"/3/0/8">>,
                                                                e=>[#{sv=>base64:encode(Opaque)}]
                                                            }
                            }),
    ?assertEqual({PubTopic, ReadResult}, test_mqtt_broker:get_published_msg()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().



case13_read_no_xml(_Config) ->
    application:set_env(?APP, port, ?PORT),
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % step 1, device register ...
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId1 = 15,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=345&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3/0>, </4>, </5>">>},
                            [],
                            MsgId1),
    #coap_message{method = Method1, payload=Payload1} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,created}, Method1),
    ?assertMatch(<<"/rd/", _Rest/binary>>, Payload1),
    timer:sleep(50),
    SubTopic = list_to_binary("lwm2m/"++Epn++"/command"),
    ?assertEqual([SubTopic], test_mqtt_broker:get_subscrbied_topics()),


    % step2,  send a READ command to device
    CmdId = 206,
    CommandTopic = <<"lwm2m/", (list_to_binary(Epn))/binary, "/command">>,
    Command =   #{
                    ?MQ_COMMAND_ID         => CmdId,
                    ?MQ_COMMAND            => <<"Read">>,
                    ?MQ_BASENAME           => <<"/9723/0/0">>
                },
    CommandJson = jsx:encode(Command),
    ?LOGT("CommandJson=~p", [CommandJson]),
    test_mqtt_broker:dispatch(CommandTopic, CommandJson, CommandTopic),
    timer:sleep(50),
    Request2 = test_recv_coap_request(UdpSock),
    #coap_message{method = Method2, options=Options2, payload=Payload2} = Request2,
    Path2 = get_coap_path(Options2),
    ?assertEqual(get, Method2),
    ?assertEqual(<<"/9723/0/0">>, Path2),
    ?assertEqual(<<>>, Payload2),
    timer:sleep(50),

    test_send_coap_response(UdpSock, "127.0.0.1", ?PORT, {ok, content}, #coap_content{format = <<"text/plain">>, payload = <<"EMQ">>}, Request2, false),
    timer:sleep(100),

    PubTopic = list_to_binary("lwm2m/"++Epn++"/response"),
    ReadResult = jsx:encode(#{  ?MQ_COMMAND_ID   => CmdId,
                                ?MQ_COMMAND      => <<"Read">>,
                                ?MQ_ERROR        => <<"No XML Definition">>
                            }),
    ?assertEqual({PubTopic, ReadResult}, test_mqtt_broker:get_published_msg()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().


case20_write(_Config) ->
    application:set_env(?APP, port, ?PORT),
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % step 1, device register ...
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId1 = 15,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=345&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3/0>, </4>, </5>">>},
                            [],
                            MsgId1),
    #coap_message{method = Method1, payload=Payload1} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,created}, Method1),
    ?assertMatch(<<"/rd/", _Rest/binary>>, Payload1),
    timer:sleep(50),
    SubTopic = list_to_binary("lwm2m/"++Epn++"/command"),
    ?assertEqual([SubTopic], test_mqtt_broker:get_subscrbied_topics()),


    % step2,  send a WRITE command to device
    CommandTopic = <<"lwm2m/", (list_to_binary(Epn))/binary, "/command">>,
    CmdId = 307,
    Command = #{?MQ_COMMAND_ID         => CmdId,
                ?MQ_COMMAND            => <<"Write">>,
                ?MQ_VALUE              => #{bn=><<"/3/0/13">>,e=>[#{v=>12345}]}},  % Current Time Resource
    CommandJson = jsx:encode(Command),
    test_mqtt_broker:dispatch(CommandTopic, CommandJson, CommandTopic),
    timer:sleep(50),
    Request2 = test_recv_coap_request(UdpSock),
    #coap_message{method = Method2, options=Options2, payload=Payload2} = Request2,
    Path2 = get_coap_path(Options2),
    ?assertEqual(put, Method2),
    ?assertEqual(<<"/3/0/13">>, Path2),
    Tlv_Value = <<3:2, 0:1, 0:2, 2:3, 13, 12345:16>>,
    ?assertEqual(Tlv_Value, Payload2),
    timer:sleep(50),

    test_send_coap_response(UdpSock, "127.0.0.1", ?PORT, {ok, changed}, #coap_content{}, Request2, false),
    timer:sleep(100),

    PubTopic = list_to_binary("lwm2m/"++Epn++"/response"),
    ReadResult = jsx:encode(#{  ?MQ_COMMAND_ID         => CmdId,
                                ?MQ_COMMAND            => <<"Write">>,
                                ?MQ_RESULT             => <<"Changed">>
                            }),
    ?assertEqual({PubTopic, ReadResult}, test_mqtt_broker:get_published_msg()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().



case21_write_object(_Config) ->
    application:set_env(?APP, port, ?PORT),
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % step 1, device register ...
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId1 = 15,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=345&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3/0>, </4>, </5>">>},
                            [],
                            MsgId1),
    #coap_message{method = Method1, payload=Payload1} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,created}, Method1),
    ?assertMatch(<<"/rd/", _Rest/binary>>, Payload1),
    timer:sleep(50),
    SubTopic = list_to_binary("lwm2m/"++Epn++"/command"),
    ?assertEqual([SubTopic], test_mqtt_broker:get_subscrbied_topics()),


    % step2,  send a WRITE command to device
    CommandTopic = <<"lwm2m/", (list_to_binary(Epn))/binary, "/command">>,
    CmdId = 307,
    Command = #{?MQ_COMMAND_ID         => CmdId,
                ?MQ_COMMAND            => <<"Write">>,
                ?MQ_VALUE              => #{bn=><<"/3/0">>,e=>[
                                                                #{n=><<"13">>, v=>12345},     % Current Time Resource
                                                                #{n=><<"14">>, sv=><<"87x">>} % UTC OFFSET
                                                            ]
                }},
    CommandJson = jsx:encode(Command),
    test_mqtt_broker:dispatch(CommandTopic, CommandJson, CommandTopic),
    timer:sleep(50),
    Request2 = test_recv_coap_request(UdpSock),
    #coap_message{method = Method2, options=Options2, payload=Payload2} = Request2,
    Path2 = get_coap_path(Options2),
    ?assertEqual(post, Method2),
    ?assertEqual(<<"/3/0">>, Path2),
    Tlv_Value = <<3:2, 0:1, 0:2, 2:3, 13, 12345:16,
                  3:2, 0:1, 0:2, 3:3, 14, "87x">>,
    ?assertEqual(Tlv_Value, Payload2),
    timer:sleep(50),

    test_send_coap_response(UdpSock, "127.0.0.1", ?PORT, {ok, changed}, #coap_content{}, Request2, false),
    timer:sleep(100),

    PubTopic = list_to_binary("lwm2m/"++Epn++"/response"),
    ReadResult = jsx:encode(#{  ?MQ_COMMAND_ID         => CmdId,
                                ?MQ_COMMAND            => <<"Write">>,
                                ?MQ_RESULT             => <<"Changed">>
                            }),
    ?assertEqual({PubTopic, ReadResult}, test_mqtt_broker:get_published_msg()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().



case22_write_error(_Config) ->
    application:set_env(?APP, port, ?PORT),
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % step 1, device register ...
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId1 = 15,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=345&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3/0>, </4>, </5>">>},
                            [],
                            MsgId1),
    #coap_message{method = Method1, payload=Payload1} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,created}, Method1),
    ?assertMatch(<<"/rd/", _Rest/binary>>, Payload1),
    timer:sleep(50),
    SubTopic = list_to_binary("lwm2m/"++Epn++"/command"),
    ?assertEqual([SubTopic], test_mqtt_broker:get_subscrbied_topics()),


    % step2,  send a WRITE command to device
    CommandTopic = <<"lwm2m/", (list_to_binary(Epn))/binary, "/command">>,
    CmdId = 307,
    Command = #{?MQ_COMMAND_ID         => CmdId,
                ?MQ_COMMAND            => <<"Write">>,
                ?MQ_VALUE              => #{bn=><<"/3/0/1">>,e=>[#{sv=><<"AA">>}]}},  % This resource is readonly
    CommandJson = jsx:encode(Command),
    test_mqtt_broker:dispatch(CommandTopic, CommandJson, CommandTopic),
    timer:sleep(50),
    Request2 = test_recv_coap_request(UdpSock),
    #coap_message{method = Method2, options=Options2, payload=Payload2} = Request2,
    Path2 = get_coap_path(Options2),
    ?assertEqual(put, Method2),
    ?assertEqual(<<"/3/0/1">>, Path2),
    Tlv_Value = <<3:2, 0:1, 0:2, 2:3, 1, "AA">>,
    ?assertEqual(Tlv_Value, Payload2),
    timer:sleep(50),

    test_send_coap_response(UdpSock, "127.0.0.1", ?PORT, {error, bad_request}, #coap_content{}, Request2, false),
    timer:sleep(100),

    PubTopic = list_to_binary("lwm2m/"++Epn++"/response"),
    ReadResult = jsx:encode(#{  ?MQ_COMMAND_ID  => CmdId,
                                ?MQ_COMMAND     => <<"Write">>,
                                ?MQ_ERROR       => <<"Bad Request">>
                            }),
    ?assertEqual({PubTopic, ReadResult}, test_mqtt_broker:get_published_msg()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().




case30_execute(_Config) ->
    application:set_env(?APP, port, ?PORT),
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % step 1, device register ...
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId1 = 15,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=345&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3/0>, </4>, </5>">>},
                            [],
                            MsgId1),
    #coap_message{method = Method1, payload=Payload1} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,created}, Method1),
    ?assertMatch(<<"/rd/", _Rest/binary>>, Payload1),
    timer:sleep(50),
    SubTopic = list_to_binary("lwm2m/"++Epn++"/command"),
    ?assertEqual([SubTopic], test_mqtt_broker:get_subscrbied_topics()),


    % step2,  send a WRITE command to device
    CommandTopic = <<"lwm2m/", (list_to_binary(Epn))/binary, "/command">>,
    CmdId = 307,
    Command = #{?MQ_COMMAND_ID         => CmdId,
                ?MQ_COMMAND            => <<"Execute">>,
                ?MQ_BASENAME           => <<"/3/0/4">>,   % Device, Reboot
                ?MQ_ARGS               => <<"2,7">>
                },
    CommandJson = jsx:encode(Command),
    test_mqtt_broker:dispatch(CommandTopic, CommandJson, CommandTopic),
    timer:sleep(50),
    Request2 = test_recv_coap_request(UdpSock),
    #coap_message{method = Method2, options=Options2, payload=Payload2} = Request2,
    Path2 = get_coap_path(Options2),
    ?assertEqual(post, Method2),
    ?assertEqual(<<"/3/0/4">>, Path2),
    ?assertEqual(<<"2,7">>, Payload2),
    timer:sleep(50),

    test_send_coap_response(UdpSock, "127.0.0.1", ?PORT, {ok, changed}, #coap_content{}, Request2, false),
    timer:sleep(100),

    PubTopic = list_to_binary("lwm2m/"++Epn++"/response"),
    ReadResult = jsx:encode(#{  ?MQ_COMMAND_ID         => CmdId,
                                ?MQ_COMMAND            => <<"Execute">>,
                                ?MQ_RESULT             => <<"Changed">>
                            }),
    ?assertEqual({PubTopic, ReadResult}, test_mqtt_broker:get_published_msg()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().



case31_execute_error(_Config) ->
    application:set_env(?APP, port, ?PORT),
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % step 1, device register ...
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId1 = 15,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=345&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3/0>, </4>, </5>">>},
                            [],
                            MsgId1),
    #coap_message{method = Method1, payload=Payload1} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,created}, Method1),
    ?assertMatch(<<"/rd/", _Rest/binary>>, Payload1),
    timer:sleep(50),
    SubTopic = list_to_binary("lwm2m/"++Epn++"/command"),
    ?assertEqual([SubTopic], test_mqtt_broker:get_subscrbied_topics()),


    % step2,  send a WRITE command to device
    CommandTopic = <<"lwm2m/", (list_to_binary(Epn))/binary, "/command">>,
    CmdId = 307,
    Command = #{?MQ_COMMAND_ID         => CmdId,
                ?MQ_COMMAND            => <<"Execute">>,
                ?MQ_BASENAME           => <<"/3/0/4">>,   % Device, Reboot
                ?MQ_ARGS               => <<"2,7">>
            },
    CommandJson = jsx:encode(Command),
    test_mqtt_broker:dispatch(CommandTopic, CommandJson, CommandTopic),
    timer:sleep(50),
    Request2 = test_recv_coap_request(UdpSock),
    #coap_message{method = Method2, options=Options2, payload=Payload2} = Request2,
    Path2 = get_coap_path(Options2),
    ?assertEqual(post, Method2),
    ?assertEqual(<<"/3/0/4">>, Path2),
    ?assertEqual(<<"2,7">>, Payload2),
    timer:sleep(50),

    test_send_coap_response(UdpSock, "127.0.0.1", ?PORT, {error, uauthorized}, #coap_content{}, Request2, false),
    timer:sleep(100),

    PubTopic = list_to_binary("lwm2m/"++Epn++"/response"),
    ReadResult = jsx:encode(#{  ?MQ_COMMAND_ID         => CmdId,
                                ?MQ_COMMAND            => <<"Execute">>,
                                ?MQ_ERROR              => <<"Unauthorized">>
                            }),
    ?assertEqual({PubTopic, ReadResult}, test_mqtt_broker:get_published_msg()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().



case40_discover(_Config) ->
    application:set_env(?APP, port, ?PORT),
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % step 1, device register ...
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId1 = 15,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=345&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3/0>, </4>, </5>">>},
                            [],
                            MsgId1),
    #coap_message{method = Method1, payload=Payload1} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,created}, Method1),
    ?assertMatch(<<"/rd/", _Rest/binary>>, Payload1),
    timer:sleep(50),
    SubTopic = list_to_binary("lwm2m/"++Epn++"/command"),
    ?assertEqual([SubTopic], test_mqtt_broker:get_subscrbied_topics()),


    % step2,  send a WRITE command to device
    CommandTopic = <<"lwm2m/", (list_to_binary(Epn))/binary, "/command">>,
    CmdId = 307,
    Command = #{?MQ_COMMAND_ID         => CmdId,
                ?MQ_COMMAND            => <<"Discover">>,
                ?MQ_BASENAME           => <<"/3/0/7">>
                },
    CommandJson = jsx:encode(Command),
    test_mqtt_broker:dispatch(CommandTopic, CommandJson, CommandTopic),
    timer:sleep(50),
    Request2 = test_recv_coap_request(UdpSock),
    #coap_message{method = Method2, options=Options2, payload=Payload2} = Request2,
    Path2 = get_coap_path(Options2),
    ?assertEqual(get, Method2),
    ?assertEqual(<<"/3/0/7">>, Path2),
    ?assertEqual(<<>>, Payload2),
    timer:sleep(50),

    PayloadDiscover = <<"</3/0/7>;dim=8;pmin=10;pmax=60;gt=50;lt=42.2">>,
    test_send_coap_response(UdpSock,
                            "127.0.0.1",
                            ?PORT,
                            {ok, content},
                            #coap_content{format = <<"application/link-format">>, payload = PayloadDiscover},
                            Request2,
                            false),
    timer:sleep(100),

    PubTopic = list_to_binary("lwm2m/"++Epn++"/response"),
    ReadResult = jsx:encode(#{  ?MQ_COMMAND_ID         => CmdId,
                                ?MQ_COMMAND            => <<"Discover">>,
                                ?MQ_RESULT             => PayloadDiscover
                            }),
    ?assertEqual({PubTopic, ReadResult}, test_mqtt_broker:get_published_msg()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().




case50_write_attribute(_Config) ->
    application:set_env(?APP, port, ?PORT),
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % step 1, device register ...
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId1 = 15,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=345&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3/0>, </4>, </5>">>},
                            [],
                            MsgId1),
    #coap_message{method = Method1, payload=Payload1} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,created}, Method1),
    ?assertMatch(<<"/rd/", _Rest/binary>>, Payload1),
    timer:sleep(50),
    SubTopic = list_to_binary("lwm2m/"++Epn++"/command"),
    ?assertEqual([SubTopic], test_mqtt_broker:get_subscrbied_topics()),


    % step2,  send a WRITE command to device
    CommandTopic = <<"lwm2m/", (list_to_binary(Epn))/binary, "/command">>,
    CmdId = 307,
    Command = #{?MQ_COMMAND_ID         => CmdId,
                ?MQ_COMMAND            => <<"Write-Attributes">>,
                ?MQ_BASENAME           => <<"/3/0/10">>,
                ?MQ_VALUE              => <<"pmax=5&lt=1024">>
                },
    CommandJson = jsx:encode(Command),
    test_mqtt_broker:dispatch(CommandTopic, CommandJson, CommandTopic),
    timer:sleep(50),
    Request2 = test_recv_coap_request(UdpSock),
    #coap_message{method = Method2, options=Options2, payload=Payload2} = Request2,
    Path2 = get_coap_path(Options2),
    [Query2] = get_coap_query(Options2),
    ?assertEqual(put, Method2),
    ?assertEqual(<<"/3/0/10">>, Path2),
    ?assertEqual(<<"pmax=5&lt=1024">>, Query2),
    ?assertEqual(<<>>, Payload2),
    timer:sleep(50),

    test_send_coap_response(UdpSock,
                            "127.0.0.1",
                            ?PORT,
                            {ok, changed},
                            #coap_content{},
                            Request2,
                            false),
    timer:sleep(100),

    PubTopic = list_to_binary("lwm2m/"++Epn++"/response"),
    ReadResult = jsx:encode(#{  ?MQ_COMMAND_ID         => CmdId,
                                ?MQ_COMMAND            => <<"Write-Attributes">>,
                                ?MQ_RESULT             => <<"Changed">>
                            }),
    ?assertEqual({PubTopic, ReadResult}, test_mqtt_broker:get_published_msg()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().






case60_observe(_Config) ->
    application:set_env(?APP, port, ?PORT),
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    test_mqtt_broker:start_link(),
    {ok, _Started} = application:ensure_all_started(emqx_lwm2m),
    timer:sleep(100),

    % step 1, device register ...
    Epn = "urn:oma:lwm2m:oma:3",
    MsgId1 = 15,
    {ok, UdpSock} = test_open_udp_socket(),
    test_send_coap_request( UdpSock,
                            post,
                            sprintf("coap://127.0.0.1:~b/rd?ep=~s&lt=345&lwm2m=1", [?PORT, Epn]),
                            #coap_content{format = <<"text/plain">>, payload = <<"</1>, </2>, </3/0>, </4>, </5>">>},
                            [],
                            MsgId1),
    #coap_message{method = Method1, payload=Payload1} = test_recv_coap_response(UdpSock),
    ?assertEqual({ok,created}, Method1),
    ?assertMatch(<<"/rd/", _Rest/binary>>, Payload1),
    timer:sleep(50),
    SubTopic = list_to_binary("lwm2m/"++Epn++"/command"),
    ?assertEqual([SubTopic], test_mqtt_broker:get_subscrbied_topics()),


    % step2,  send a OBSERVE command to device
    CommandTopic = <<"lwm2m/", (list_to_binary(Epn))/binary, "/command">>,
    CmdId = 307,
    Command = #{?MQ_COMMAND_ID         => CmdId,
                ?MQ_COMMAND            => <<"Observe">>,
                ?MQ_BASENAME           => <<"/3/0/10">>
                },
    CommandJson = jsx:encode(Command),
    test_mqtt_broker:dispatch(CommandTopic, CommandJson, CommandTopic),
    timer:sleep(50),
    Request2 = test_recv_coap_request(UdpSock),
    #coap_message{method = Method2, options=Options2, payload=Payload2} = Request2,
    Path2 = get_coap_path(Options2),
    Observe = get_coap_observe(Options2),
    ?assertEqual(get, Method2),
    ?assertEqual(<<"/3/0/10">>, Path2),
    ?assertEqual(Observe, 0),
    ?assertEqual(<<>>, Payload2),
    timer:sleep(50),

    test_send_coap_observe_ack( UdpSock,
                                "127.0.0.1",
                                ?PORT,
                                {ok, content},
                                #coap_content{format = <<"text/plain">>, payload = <<"2048">>},
                                Request2),
    timer:sleep(100),

    PubTopic = list_to_binary("lwm2m/"++Epn++"/response"),
    ReadResult = jsx:encode(#{  ?MQ_COMMAND_ID         => CmdId,
                                ?MQ_COMMAND            => <<"Observe">>,
                                ?MQ_RESULT             => #{bn=><<"/3/0/10">>, e=>[#{v=>2048}]}
                            }),
    ?assertEqual({PubTopic, ReadResult}, test_mqtt_broker:get_published_msg()),


    timer:sleep(200),
    ObSeq = 3,
    test_send_coap_notif(   UdpSock,
                            "127.0.0.1",
                            ?PORT,
                            #coap_content{format = <<"text/plain">>, payload = <<"4096">>},
                            ObSeq,
                            Request2),
    timer:sleep(100),

    PubTopic = list_to_binary("lwm2m/"++Epn++"/response"),
    ReadResult2 = jsx:encode(#{ ?MQ_COMMAND_ID         => CmdId,
                                ?MQ_COMMAND            => <<"Observe">>,
                                ?MQ_RESULT             => #{bn=><<"/3/0/10">>, e=>[#{v=>4096}]}
                            }),
    ?assertEqual({PubTopic, ReadResult2}, test_mqtt_broker:get_published_msg()),

    test_close_udp_socket(UdpSock),
    ok = application:stop(emqx_lwm2m),
    ok = application:stop(lwm2m_coap),
    test_mqtt_broker:stop().




%% TODO: add a case that xml is corrupted






test_open_udp_socket() ->
    gen_udp:open(0, [binary, {active, false}]).

test_close_udp_socket(Socket) ->
    gen_udp:close(Socket).

test_send_coap_request(UdpSock, Method, Uri, Content, Options, MsgId) ->
    is_record(Content, coap_content) orelse error("Content must be a #coap_content!"),
    is_list(Options) orelse error("Options must be a list"),
    case resolve_uri(Uri) of
        {coap, {IpAddr, Port}, Path, Query} ->
            Request0 = lwm2m_coap_message:request(con, Method, Content, [{uri_path, Path}, {uri_query, Query} | Options]),
            Request = Request0#coap_message{id = MsgId},
            ?LOGT("send_coap_request Request=~p", [Request]),
            RequestBinary = lwm2m_coap_message_parser:encode(Request),
            ?LOGT("test udp socket send to ~p:~p, data=~p", [IpAddr, Port, RequestBinary]),
            ok = gen_udp:send(UdpSock, IpAddr, Port, RequestBinary);
        {SchemeDiff, ChIdDiff, _, _} ->
            error(lists:flatten(io_lib:format("scheme ~s or ChId ~s does not match with socket", [SchemeDiff, ChIdDiff])))
    end.

test_recv_coap_response(UdpSock) ->
    {ok, {Address, Port, Packet}} = gen_udp:recv(UdpSock, 0, 2000),
    ?LOGT("test udp receive from ~p:~p, data1=~p", [Address, Port, Packet]),
    Response = lwm2m_coap_message_parser:decode(Packet),
    #coap_message{type = ack, method = Method, id=Id, token = Token, payload = Payload} = Response,
    ?LOGT("receive coap response Method=~p, Id=~p, Token=~p, Payload=~p", [Method, Id, Token, Payload]),
    Response.


test_recv_coap_request(UdpSock) ->
    {ok, {Address, Port, Packet}} = gen_udp:recv(UdpSock, 0, 2000),
    ?LOGT("test udp receive from ~p:~p, data2=~p", [Address, Port, Packet]),
    Request = lwm2m_coap_message_parser:decode(Packet),
    #coap_message{type = con, method = Method, id=Id, token = Token, payload = Payload, options = Options} = Request,
    ?LOGT("receive coap request Method=~p, Id=~p, Token=~p, Options=~p, Payload=~p", [Method, Id, Token, Options, Payload]),
    Request.


test_send_coap_response(UdpSock, Host, Port, Code, Content, Request, Ack) ->
    is_record(Content, coap_content) orelse error("Content must be a #coap_content!"),
    is_list(Host) orelse error("Host is not a string"),

    {ok, IpAddr} = inet:getaddr(Host, inet),
    Response = lwm2m_coap_message:response(Code, Content, Request),
    Response2 = case Ack of
                    true -> Response#coap_message{type = ack};
                    false -> Response
                end,
    ?LOGT("test_send_coap_response Response=~p", [Response2]),
    ResponseBinary = lwm2m_coap_message_parser:encode(Response2),
    ?LOGT("test udp socket send to ~p:~p, data=~p", [IpAddr, Port, ResponseBinary]),
    ok = gen_udp:send(UdpSock, IpAddr, Port, ResponseBinary).



test_send_coap_observe_ack(UdpSock, Host, Port, Code, Content, Request) ->
    is_record(Content, coap_content) orelse error("Content must be a #coap_content!"),
    is_list(Host) orelse error("Host is not a string"),

    {ok, IpAddr} = inet:getaddr(Host, inet),
    Response = lwm2m_coap_message:response(Code, Content, Request),
    Response1 = lwm2m_coap_message:set(observe, 5, Response),
    Response2 = Response1#coap_message{type = ack},

    ?LOGT("test_send_coap_response Response=~p", [Response2]),
    ResponseBinary = lwm2m_coap_message_parser:encode(Response2),
    ?LOGT("test udp socket send to ~p:~p, data=~p", [IpAddr, Port, ResponseBinary]),
    ok = gen_udp:send(UdpSock, IpAddr, Port, ResponseBinary).


test_send_coap_notif(UdpSock, Host, Port, Content, ObSeq, Request) ->
    is_record(Content, coap_content) orelse error("Content must be a #coap_content!"),
    is_list(Host) orelse error("Host is not a string"),

    {ok, IpAddr} = inet:getaddr(Host, inet),
    Notif = lwm2m_coap_message:response({ok, content}, Content, Request),
    NewNotif = lwm2m_coap_message:set(observe, ObSeq, Notif),
    ?LOGT("test_send_coap_notif Response=~p", [NewNotif]),
    NotifBinary = lwm2m_coap_message_parser:encode(NewNotif),
    ?LOGT("test udp socket send to ~p:~p, data=~p", [IpAddr, Port, NotifBinary]),
    ok = gen_udp:send(UdpSock, IpAddr, Port, NotifBinary).


resolve_uri(Uri) ->
    {ok, {Scheme, _UserInfo, Host, PortNo, Path, Query}} =
        http_uri:parse(Uri, [{scheme_defaults, [{coap, ?DEFAULT_COAP_PORT}, {coaps, ?DEFAULT_COAPS_PORT}]}]),
    {ok, PeerIP} = inet:getaddr(Host, inet),
    {Scheme, {PeerIP, PortNo}, split_path(Path), split_query(Query)}.

split_path([]) -> [];
split_path([$/]) -> [];
split_path([$/ | Path]) -> split_segments(Path, $/, []).

split_query([]) -> [];
split_query([$? | Path]) -> split_segments(Path, $&, []).

split_segments(Path, Char, Acc) ->
    case string:rchr(Path, Char) of
        0 ->
            [make_segment(Path) | Acc];
        N when N > 0 ->
            split_segments(string:substr(Path, 1, N-1), Char,
                [make_segment(string:substr(Path, N+1)) | Acc])
    end.

make_segment(Seg) ->
    list_to_binary(http_uri:decode(Seg)).


get_coap_path(Options) ->
    get_path(Options, <<>>).

get_coap_query(Options) ->
    get_query(Options, []).

get_coap_observe(Options) ->
    get_observe(Options).


get_path([], Acc) ->
    %?LOGT("get_path Acc=~p", [Acc]),
    Acc;
get_path([{uri_path, Path1}|T], Acc) ->
    %?LOGT("Path=~p, Acc=~p", [Path1, Acc]),
    get_path(T, join_path(Path1, Acc));
get_path([{_, _}|T], Acc) ->
    get_path(T, Acc).

get_query([], Acc) ->
    lists:reverse(Acc);
get_query([{uri_query, [Q1]}|T], Acc) ->
    get_query(T, [Q1|Acc]);
get_query([{_, _}|T], Acc) ->
    get_query(T, Acc).

get_observe([]) ->
    undefined;
get_observe([{observe, V}|_T]) ->
    V;
get_observe([{_, _}|T]) ->
    get_observe(T).

join_path([], Acc) ->
    Acc;
join_path([H|T], Acc) ->
    join_path(T, <<Acc/binary, $/, H/binary>>).



sprintf(Format, Args) ->
    lists:flatten(io_lib:format(Format, Args)).


