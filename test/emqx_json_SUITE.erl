%% Copyright (c) 2018 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_json_SUITE).

-compile(export_all).

-define(LOGT(Format, Args), emqx_logger:debug("TEST_SUITE: " ++ Format, Args)).

-include("emqx_lwm2m.hrl").
-include_lib("lwm2m_coap/include/coap.hrl").
-include_lib("eunit/include/eunit.hrl").

all() ->
    [case01, case02, case03, case04_two_multiple_resource,
     case05_two_multiple_resource_three_resource_with_value,
     case06_one_object_instance, case07_two_object_instance].

init_per_suite(Config) ->
    Config.

end_per_suite(Config) ->
    Config.

case01(_Config) ->
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    emqx_lwm2m_xml_object_db:start_link(),
    Input = [#{tlv_resource_with_value => 16#00, value => <<"Open Mobile Alliance">>}],
    R = emqx_lwm2m_json:tlv_to_json(<<"/3/0/0">>, Input),
    Exp = #{bn=><<"/3/0/0">>,e=>[#{sv=><<"Open Mobile Alliance">>}]},
    ?assertEqual(Exp, R),
    EncodedTerm = emqx_lwm2m_json:json_to_tlv(Exp),
    ?assertEqual(Input, EncodedTerm),
    emqx_lwm2m_xml_object_db:stop().

case02(_Config) ->
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    emqx_lwm2m_xml_object_db:start_link(),
    Input = [#{tlv_resource_with_value => 16#00, value => <<"Open Mobile Alliance">>},
             #{tlv_resource_with_value => 16#01, value => <<"Lightweight M2M Client">>},
             #{tlv_resource_with_value => 16#02, value => <<"345000123">>}],
    R = emqx_lwm2m_json:tlv_to_json(<<"/3/0">>, Input),
    Exp = #{bn => <<"/3/0">>,
            e  =>[#{n=><<"0">>, sv=><<"Open Mobile Alliance">>},
                  #{n=><<"1">>, sv=><<"Lightweight M2M Client">>},
                  #{n=><<"2">>, sv=><<"345000123">>}]},
    ?assertEqual(Exp, R),
    EncodedTerm = emqx_lwm2m_json:json_to_tlv(Exp),
    ?assertEqual(Input, EncodedTerm),
    emqx_lwm2m_xml_object_db:stop().

case03(_Config) ->
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    emqx_lwm2m_xml_object_db:start_link(),
    Input = [#{tlv_multiple_resource => 16#07,
               value => [#{tlv_resource_instance => 16#00, value => <<16#0ED8:16>>},
                         #{tlv_resource_instance => 16#01, value => <<16#1388:16>>}]}],
    R = emqx_lwm2m_json:tlv_to_json(<<"/3/0/7">>, Input),
    Exp = #{bn => <<"/3/0">>,
            e  => [#{n=><<"7/0">>, v=>3800},
                   #{n=><<"7/1">>, v=>5000}]},
    ?assertEqual(Exp, R),
    EncodedTerm = emqx_lwm2m_json:json_to_tlv(Exp),
    ?assertEqual(Input, EncodedTerm),
    emqx_lwm2m_xml_object_db:stop().

case04_two_multiple_resource(_Config) ->
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    emqx_lwm2m_xml_object_db:start_link(),
    Input = [#{tlv_multiple_resource => 16#07,
               value => [#{tlv_resource_instance => 16#00, value => <<16#0ED8:16>>},
                         #{tlv_resource_instance => 16#01, value => <<16#1388:16>>}]},
             #{tlv_multiple_resource => 16#0a,
               value =>[#{tlv_resource_instance => 16#00, value => <<16#0101:16>>},
                        #{tlv_resource_instance => 16#01, value => <<16#0202:16>>}]}],
    R = emqx_lwm2m_json:tlv_to_json(<<"/3/0">>, Input),
    Exp = #{bn => <<"/3/0">>,
            e  => [#{n=><<"7/0">>, v=>3800},
                   #{n=><<"7/1">>, v=>5000},
                   #{n=><<"10/0">>, v=>257},
                   #{n=><<"10/1">>, v=>514}]},
    ?assertEqual(Exp, R),
    EncodedTerm = emqx_lwm2m_json:json_to_tlv(Exp),
    ?assertEqual(Input, EncodedTerm),
    emqx_lwm2m_xml_object_db:stop().

case05_two_multiple_resource_three_resource_with_value(_Config) ->
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    emqx_lwm2m_xml_object_db:start_link(),
    Input = [#{tlv_resource_with_value => 16#00, value => <<"Open Mobile Alliance">>},
             #{tlv_resource_with_value => 16#01, value => <<"Lightweight M2M Client">>},
             #{tlv_resource_with_value => 16#02, value => <<"345000123">>},
             #{tlv_multiple_resource => 16#07,
               value => [#{tlv_resource_instance => 16#00, value => <<16#0ED8:16>>},
                         #{tlv_resource_instance => 16#01, value => <<16#1388:16>>}]},
             #{tlv_multiple_resource => 16#0a,
               value => [#{tlv_resource_instance => 16#00, value => <<16#0101:16>>},
                         #{tlv_resource_instance => 16#01, value => <<16#0202:16>>}]}],
    R = emqx_lwm2m_json:tlv_to_json(<<"/3/0">>, Input),
    Exp0 = #{bn => <<"/3/0">>,
             e  => [#{n=><<"0">>, sv=><<"Open Mobile Alliance">>},
                    #{n=><<"1">>, sv=><<"Lightweight M2M Client">>},
                    #{n=><<"2">>, sv=><<"345000123">>},
                    #{n=><<"7/0">>, v=>3800},
                    #{n=><<"7/1">>, v=>5000},
                    #{n=><<"10/0">>, v=>257},
                    #{n=><<"10/1">>, v=>514}]},
    ?assertEqual(Exp0, R),
    EncodedTerm = emqx_lwm2m_json:json_to_tlv(Exp0),
    ?assertEqual(Input, EncodedTerm),
    emqx_lwm2m_xml_object_db:stop().

case06_one_object_instance(_Config) ->
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    emqx_lwm2m_xml_object_db:start_link(),
    Input = [#{tlv_resource_with_value => 16#00, value => <<"Open Mobile Alliance">>},
             #{tlv_resource_with_value => 16#01, value => <<"Lightweight M2M Client">>},
             #{tlv_resource_with_value => 16#02, value => <<"345000123">>},
             #{tlv_multiple_resource => 16#07,
               value => [#{tlv_resource_instance => 16#00, value => <<16#0ED8:16>>},
                         #{tlv_resource_instance => 16#01, value => <<16#1388:16>>}]},
             #{tlv_multiple_resource => 16#0a,
               value => [#{tlv_resource_instance => 16#00, value => <<16#0101:16>>},
                         #{tlv_resource_instance => 16#01, value => <<16#0202:16>>}]}],
    R = emqx_lwm2m_json:tlv_to_json(<<"/3/0">>, Input),
    Exp0 = #{bn => <<"/3/0">>,
             e  => [#{n=><<"0">>, sv=><<"Open Mobile Alliance">>},
                    #{n=><<"1">>, sv=><<"Lightweight M2M Client">>},
                    #{n=><<"2">>, sv=><<"345000123">>},
                    #{n=><<"7/0">>, v=>3800},
                    #{n=><<"7/1">>, v=>5000},
                    #{n=><<"10/0">>, v=>257},
                    #{n=><<"10/1">>, v=>514}]},
    ?assertEqual(Exp0, R),
    EncodedTerm = emqx_lwm2m_json:json_to_tlv(Exp0),
    ?assertEqual(Input, EncodedTerm),
    emqx_lwm2m_xml_object_db:stop().

case07_two_object_instance(_Config) ->
    application:set_env(?APP, xml_dir, "../../lwm2m_xml"),
    emqx_lwm2m_xml_object_db:start_link(),
    Input = [#{tlv_object_instance => 0,
               value => [#{tlv_resource_with_value => 16#00, value => <<"Open Mobile Alliance">>},
                         #{tlv_resource_with_value => 16#01, value => <<"Lightweight M2M Client">>},
                         #{tlv_resource_with_value => 16#02, value => <<"345000123">>},
                         #{tlv_multiple_resource => 16#07,
                           value => [#{tlv_resource_instance => 16#00, value => <<16#0ED8:16>>},
                                     #{tlv_resource_instance => 16#01, value => <<16#1388:16>>}]},
                         #{tlv_multiple_resource => 16#0a,
                           value => [#{tlv_resource_instance => 16#00, value => <<16#0101:16>>},
                                     #{tlv_resource_instance => 16#01, value => <<16#0202:16>>}]}]},
             #{tlv_object_instance => 1,
               value => [#{tlv_resource_with_value => 16#00, value => <<"AAA">>},
                         #{tlv_resource_with_value => 16#01, value => <<"BBB">>},
                         #{tlv_resource_with_value => 16#02, value => <<"CCC">>}]}],
    R = emqx_lwm2m_json:tlv_to_json(<<"/3/0">>, Input),
    Exp0 = #{bn => <<"/3">>,
             e => [#{n=><<"0/0">>, sv=><<"Open Mobile Alliance">>},
                   #{n=><<"0/1">>, sv=><<"Lightweight M2M Client">>},
                   #{n=><<"0/2">>, sv=><<"345000123">>},
                   #{n=><<"0/7/0">>, v=>3800},
                   #{n=><<"0/7/1">>, v=>5000},
                   #{n=><<"0/10/0">>, v=>257},
                   #{n=><<"0/10/1">>, v=>514},
                   #{n=><<"1/0">>, sv=><<"AAA">>},
                   #{n=><<"1/1">>, sv=><<"BBB">>},
                   #{n=><<"1/2">>, sv=><<"CCC">>}]},
    ?assertEqual(Exp0, R),
    EncodedTerm = emqx_lwm2m_json:json_to_tlv(Exp0),
    ?assertEqual(Input, EncodedTerm),
    emqx_lwm2m_xml_object_db:stop().

