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

-module(emqx_lwm2m_cmd_handler).

-author("Feng Lee <feng@emqtt.io>").

-include("emqx_lwm2m.hrl").
-include_lib("lwm2m_coap/include/coap.hrl").

-export([mqtt_payload_to_coap_request/3, coap_response_to_mqtt_payload/4]).

-define(LOG(Level, Format, Args), lager:Level("LWM2M-CNVT: " ++ Format, Args)).

mqtt_payload_to_coap_request(AlternatePath, InputCmd = #{<<"msgType">> := <<"read">>, <<"data">> := Data}, _Lwm2mProtoType) ->
    FullPathList = add_alternate_path_prefix(AlternatePath, path_list(maps:get(<<"path">>, Data))),
    {lwm2m_coap_message:request(con, get, <<>>, [{uri_path, FullPathList}]), InputCmd};
mqtt_payload_to_coap_request(AlternatePath, InputCmd = #{<<"msgType">> := <<"write">>, <<"data">> := Data}, Lwm2mProtoType) ->
    CoapRequest =
        case maps:get(<<"basePath">>, Data, <<"/">>) of
            <<"/">> ->
                single_write_request(AlternatePath, Data, Lwm2mProtoType);
            BasePath ->
                batch_write_request(AlternatePath, BasePath, maps:get(<<"content">>, Data))
        end,
    {CoapRequest, InputCmd};

mqtt_payload_to_coap_request(AlternatePath, InputCmd = #{<<"msgType">> := <<"execute">>, <<"data">> := Data}, _Lwm2mProtoType) ->
    FullPathList = add_alternate_path_prefix(AlternatePath, path_list(maps:get(<<"path">>, Data))),
    Args = 
        case maps:get(<<"args">>, Data, <<>>) of
            <<"undefined">> -> <<>>;
            undefined -> <<>>;
            Arg1 -> Arg1
        end,
    {lwm2m_coap_message:request(con, post, Args, [{uri_path, FullPathList}, {content_format, <<"text/plain">>}]), InputCmd};
mqtt_payload_to_coap_request(AlternatePath, InputCmd = #{<<"msgType">> := <<"discover">>, <<"data">> := Data}, _Lwm2mProtoType) ->
    FullPathList = add_alternate_path_prefix(AlternatePath, path_list(maps:get(<<"path">>, Data))),
    {lwm2m_coap_message:request(con, get, <<>>, [{uri_path, FullPathList}, {'accept', ?LWM2M_FORMAT_LINK}]), InputCmd};
mqtt_payload_to_coap_request(AlternatePath, InputCmd = #{<<"msgType">> := <<"write-attr">>, <<"data">> := Data}, _Lwm2mProtoType) ->
    FullPathList = add_alternate_path_prefix(AlternatePath, path_list(maps:get(<<"path">>, Data))),
    Query = attr_query_list(Data),
    {lwm2m_coap_message:request(con, put, <<>>, [{uri_path, FullPathList}, {uri_query, Query}]), InputCmd};
mqtt_payload_to_coap_request(AlternatePath, InputCmd = #{<<"msgType">> := <<"observe">>, <<"data">> := Data}, _Lwm2mProtoType) ->
    PathList = path_list(maps:get(<<"path">>, Data)),
    InputCmd2 =
        case hd(PathList) of
            <<"19">> -> InputCmd#{observe_type => idiot};
            _ -> InputCmd#{observe_type => standard}
        end,
    FullPathList = add_alternate_path_prefix(AlternatePath, PathList),
    {lwm2m_coap_message:request(con, get, <<>>, [{uri_path, FullPathList}, {observe, 0}]), InputCmd2};
mqtt_payload_to_coap_request(AlternatePath, InputCmd = #{<<"msgType">> := <<"cancel-observe">>, <<"data">> := Data}, _Lwm2mProtoType) ->
    PathList = path_list(maps:get(<<"path">>, Data)),
    InputCmd2 =
        case hd(PathList) of
            <<"19">> -> InputCmd#{observe_type => idiot};
            _ -> InputCmd#{observe_type => standard}
        end,
    FullPathList = add_alternate_path_prefix(AlternatePath, PathList),
    {lwm2m_coap_message:request(con, get, <<>>, [{uri_path, FullPathList}, {observe, 1}]), InputCmd2}.

coap_response_to_mqtt_payload(Method, CoapPayload, Options, Ref=#{<<"msgType">> := <<"read">>}) ->
    coap_read_response_to_mqtt_payload(Method, CoapPayload, data_format(Options), Ref);
coap_response_to_mqtt_payload(Method, _CoapPayload, _Options, Ref=#{<<"msgType">> := <<"write">>}) ->
    coap_write_response_to_mqtt_payload(Method, Ref);
coap_response_to_mqtt_payload(Method, _CoapPayload, _Options, Ref=#{<<"msgType">> := <<"execute">>}) ->
    coap_execute_response_to_mqtt_payload(Method, Ref);
coap_response_to_mqtt_payload(Method, CoapPayload, _Options, Ref=#{<<"msgType">> := <<"discover">>}) ->
    coap_discover_response_to_mqtt_payload(Method, CoapPayload, Ref);
coap_response_to_mqtt_payload(Method, CoapPayload, _Options, Ref=#{<<"msgType">> := <<"write-attr">>}) ->
    coap_writeattr_response_to_mqtt_payload(Method, CoapPayload, Ref);
coap_response_to_mqtt_payload(Method, CoapPayload, Options, Ref=#{<<"msgType">> := <<"observe">>}) ->
    coap_observe_response_to_mqtt_payload(Method, CoapPayload, data_format(Options), observe_seq(Options, Ref), Ref);
coap_response_to_mqtt_payload(Method, CoapPayload, Options, Ref=#{<<"msgType">> := <<"cancel-observe">>}) ->
    coap_cancel_observe_response_to_mqtt_payload(Method, CoapPayload, data_format(Options), Ref).

coap_read_response_to_mqtt_payload({error, ErrorCode}, _CoapPayload, _Format, Ref) ->
    make_response(ErrorCode, Ref);
coap_read_response_to_mqtt_payload({ok, SuccessCode}, CoapPayload, Format, Ref) ->
    try
        Result = coap_content_to_mqtt_payload(CoapPayload, Format, Ref),
        make_response(SuccessCode, Ref, Format, Result)
    catch
        error:not_implemented -> make_response(not_implemented, Ref);
        _:Ex ->
            ?LOG(error, "~p, bad payload format: ~p, stacktrace: ~p", [Ex, CoapPayload, erlang:get_stacktrace()]),
            make_response(bad_request, Ref)
    end.

coap_content_to_mqtt_payload(CoapPayload, <<"text/plain">>, Ref) ->
    emqx_lwm2m_message:text_to_json(extract_path(Ref), CoapPayload);
coap_content_to_mqtt_payload(CoapPayload, <<"application/octet-stream">>, Ref) ->
    emqx_lwm2m_message:opaque_to_json(extract_path(Ref), CoapPayload);
coap_content_to_mqtt_payload(CoapPayload, <<"application/vnd.oma.lwm2m+tlv">>, Ref) ->
    emqx_lwm2m_message:tlv_to_json(extract_path(Ref), CoapPayload);
coap_content_to_mqtt_payload(CoapPayload, <<"application/vnd.oma.lwm2m+json">>, _Ref) ->
    emqx_lwm2m_message:translate_json(CoapPayload).

coap_write_response_to_mqtt_payload({ok, changed}, Ref) ->
    make_response(changed, Ref);
coap_write_response_to_mqtt_payload({error, Error}, Ref) ->
    make_response(Error, Ref).

coap_execute_response_to_mqtt_payload({ok, changed}, Ref) ->
    make_response(changed, Ref);
coap_execute_response_to_mqtt_payload({error, Error}, Ref) ->
    make_response(Error, Ref).

coap_discover_response_to_mqtt_payload({ok, content}, CoapPayload, Ref) ->
    Links = binary:split(CoapPayload, <<",">>),
    make_response(content, Ref, <<"application/link-format">>, Links);
coap_discover_response_to_mqtt_payload({error, Error}, _CoapPayload, Ref) ->
    make_response(Error, Ref).

coap_writeattr_response_to_mqtt_payload({ok, changed}, _CoapPayload, Ref) ->
    make_response(changed, Ref);
coap_writeattr_response_to_mqtt_payload({error, Error}, _CoapPayload, Ref) ->
    make_response(Error, Ref).

coap_observe_response_to_mqtt_payload({error, Error}, _CoapPayload, _Format, _ObserveSeqNum, Ref) ->
    make_response(Error, Ref);
coap_observe_response_to_mqtt_payload({ok, content}, CoapPayload, Format, 0, Ref) ->
    coap_read_response_to_mqtt_payload({ok, content}, CoapPayload, Format, Ref);
coap_observe_response_to_mqtt_payload({ok, content}, CoapPayload, Format, ObserveSeqNum, Ref) ->
    RefWithObserve = maps:put(<<"seqNum">>, ObserveSeqNum, Ref),
    RefNotify = maps:put(<<"msgType">>, <<"notify">>, RefWithObserve),
    coap_read_response_to_mqtt_payload({ok, content}, CoapPayload, Format, RefNotify).

coap_cancel_observe_response_to_mqtt_payload({ok, content}, CoapPayload, Format, Ref) ->
    coap_read_response_to_mqtt_payload({ok, content}, CoapPayload, Format, Ref);
coap_cancel_observe_response_to_mqtt_payload({error, Error}, _CoapPayload, _Format, Ref) ->
    make_response(Error, Ref).

make_response(Code, Ref=#{}) ->
    BaseRsp = make_base_response(Ref),
    make_data_response(BaseRsp, Code).
make_response(Code, Ref=#{}, _Format, Result) ->
    BaseRsp = make_base_response(Ref),
    make_data_response(BaseRsp, Code, _Format, Result).

%% The base response format is what included in the request:
%%
%%   #{
%%       <<"seqNum">> => SeqNum,
%%       <<"imsi">> => maps:get(<<"imsi">>, Ref, null),
%%       <<"imei">> => maps:get(<<"imei">>, Ref, null),
%%       <<"requestID">> => maps:get(<<"requestID">>, Ref, null),
%%       <<"cacheID">> => maps:get(<<"cacheID">>, Ref, null),
%%       <<"msgType">> => maps:get(<<"msgType">>, Ref, null)
%%   }

make_base_response(Ref=#{}) ->
    remove_tmp_fields(Ref).

make_data_response(BaseRsp, Code) ->
    BaseRsp#{
        <<"data">> => #{
            <<"code">> => code(Code),
            <<"codeMsg">> => Code
        }
    }.
make_data_response(BaseRsp, Code, _Format, Result) ->
    BaseRsp#{
        <<"data">> =>  #{
            <<"code">> => code(Code),
            <<"codeMsg">> => Code,
            <<"content">> => Result
        }
    }.

remove_tmp_fields(Ref) ->
    maps:remove(observe_type, Ref).

path_list(Path) ->
    case binary:split(binary_util:trim(Path, $/), [<<$/>>], [global]) of
        [ObjId, ObjInsId, ResId, ResInstId] -> [ObjId, ObjInsId, ResId, ResInstId];
        [ObjId, ObjInsId, ResId] -> [ObjId, ObjInsId, ResId];
        [ObjId, ObjInsId] -> [ObjId, ObjInsId];
        [ObjId] -> [ObjId]
    end.

attr_query_list(Data) ->
    attr_query_list(Data, valid_attr_keys(), []).
attr_query_list(QueryJson = #{}, ValidAttrKeys, QueryList) ->
    maps:fold(
        fun
            (_K, null, Acc) -> Acc;
            (K, V, Acc) ->
                case lists:member(K, ValidAttrKeys) of
                    true ->
                        KV = <<K/binary, "=", V/binary>>,
                        Acc ++ [KV];
                    false ->
                        Acc
                end
        end, QueryList, QueryJson).

valid_attr_keys() ->
    [<<"pmin">>, <<"pmax">>, <<"gt">>, <<"lt">>, <<"st">>].

data_format(Options) ->
    proplists:get_value(content_format, Options, <<"text/plain">>).
observe_seq(Options, #{observe_type := idiot}) ->
    proplists:get_value(observe, Options, rand:uniform(1000000) + 1 );
observe_seq(Options, #{observe_type := standard}) ->
    proplists:get_value(observe, Options, 0).

add_alternate_path_prefix(<<"/">>, PathList) ->
    PathList;
add_alternate_path_prefix(AlternatePath, PathList) ->
    [binary_util:trim(AlternatePath, $/) | PathList].

extract_path(Ref = #{}) ->
    case Ref of
        #{<<"data">> := Data} ->
            maps:get(<<"path">>, Data);
        #{<<"path">> := Path} ->
            Path
    end.

batch_write_request(AlternatePath, BasePath, Content) ->
    PathList = path_list(BasePath),
    Method = case length(PathList) of
                2 -> post;
                3 -> put
             end,
    FullPathList = add_alternate_path_prefix(AlternatePath, PathList),
    TlvData = emqx_lwm2m_message:json_to_tlv(PathList, Content),
    Payload = emqx_lwm2m_tlv:encode(TlvData),
    lwm2m_coap_message:request(con, Method, Payload, [{uri_path, FullPathList}, {content_format, <<"application/vnd.oma.lwm2m+tlv">>}]).

single_write_request(AlternatePath, Data, Lwm2mProtoType) ->
    PathList = path_list(maps:get(<<"path">>, Data)),
    FullPathList = add_alternate_path_prefix(AlternatePath, PathList),
    case {PathList, Lwm2mProtoType} of
        {[<<"19">>, <<"1">>, <<"0">>], 2} ->
            Value = base64:decode(maps:get(<<"value">>, Data)),
            lwm2m_coap_message:request(con, put, Value, [{uri_path, FullPathList}, {content_format, <<"application/octet-stream">>}]);
        {_, _} ->
            %% TO DO: handle write to resource instance, e.g. /4/0/1/0
            TlvData = emqx_lwm2m_message:json_to_tlv(PathList, [Data]),
            Payload = emqx_lwm2m_tlv:encode(TlvData),
            lwm2m_coap_message:request(con, put, Payload, [{uri_path, FullPathList}, {content_format, <<"application/vnd.oma.lwm2m+tlv">>}])
    end.

code(get) -> <<"0.01">>;
code(post) -> <<"0.02">>;
code(put) -> <<"0.03">>;
code(delete) -> <<"0.04">>;
code(created) -> <<"2.01">>;
code(deleted) -> <<"2.02">>;
code(valid) -> <<"2.03">>;
code(changed) -> <<"2.04">>;
code(content) -> <<"2.05">>;
code(continue) -> <<"2.31">>;
code(bad_request) -> <<"4.00">>;
code(uauthorized) -> <<"4.01">>;
code(bad_option) -> <<"4.02">>;
code(forbidden) -> <<"4.03">>;
code(not_found) -> <<"4.04">>;
code(method_not_allowed) -> <<"4.05">>;
code(not_acceptable) -> <<"4.06">>;
code(request_entity_incomplete) -> <<"4.08">>;
code(precondition_failed) -> <<"4.12">>;
code(request_entity_too_large) -> <<"4.13">>;
code(unsupported_content_format) -> <<"4.15">>;
code(internal_server_error) -> <<"5.00">>;
code(not_implemented) -> <<"5.01">>;
code(bad_gateway) -> <<"5.02">>;
code(service_unavailable) -> <<"5.03">>;
code(gateway_timeout) -> <<"5.04">>;
code(proxying_not_supported) -> <<"5.05">>.
