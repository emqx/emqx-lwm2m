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

-module(emqx_lwm2m_mqtt_adapter).

-include("emqx_lwm2m.hrl").

-include_lib("emqx/include/emqx.hrl").

-include_lib("emqx/include/emqx_mqtt.hrl").

%% API.
-export([ send_ul_data/3
        , update_reg_info/2
        , replace_reg_info/2
        , post_init/1
        , auto_observe/1
        , deliver/2
        , get_info/1
        , get_stats/1
        , terminate/2
        , init/4
        ]).

-record(lwm2m_state, {  proto
                      , peer
                      , life_timer
                      , coap_pid
                      , sub_topic
                      , reg_info
                      , started_at
                      }).

-define(DEFAULT_KEEP_ALIVE_DURATION,  60*2).

-define(LOG(Level, Format, Args),
    lager:Level("LWM2M-MQTT: " ++ Format, Args)).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------
init(CoapPid, ClientId, ChId, RegInfo = #{<<"lt">> := LifeTime, <<"lwm2m">> := Ver}) ->
    case proto_init(ClientId, undefined, undefined, ChId, Ver) of
        {ok, Proto} ->
            ?LOG(debug, "start adapter ClientId=~p, ChId=~p, RegInfo=~p", [ClientId, ChId, RegInfo]),
            erlang:send(CoapPid, post_init),
            erlang:send_after(2000, CoapPid, auto_observe),
            {ok, #lwm2m_state{
                coap_pid = CoapPid,
                proto = Proto,
                peer = ChId,
                reg_info = RegInfo,
                started_at = time_now(),
                life_timer = emqx_lwm2m_timer:start_timer(LifeTime, {life_timer, expired})
            }};
        {error, Reason, _Proto} -> {error, Reason};
        Other -> {error, Other}
    end.

update_reg_info(NewRegInfo, State=#lwm2m_state{life_timer = LifeTimer,
        reg_info = RegInfo, proto = Proto, coap_pid = CoapPid}) ->
    UpdatedRegInfo = maps:merge(RegInfo, NewRegInfo),

    %% - report the registration info update, but only when objectList is updated.
    NewProto = case NewRegInfo of
                   #{<<"objectList">> := _} ->
                       send_data(<<"update">>, #{<<"data">> => UpdatedRegInfo}, Proto);
                   _ -> Proto
               end,

    %% - flush cached donwlink commands
    flush_cached_downlink_messages(CoapPid),

    %% - update the life timer
    UpdatedLifeTimer = emqx_lwm2m_timer:refresh_timer(maps:get(<<"lt">>, UpdatedRegInfo), LifeTimer),

    ?LOG(debug, "Update RegInfo to: ~p", [UpdatedRegInfo]),
    State#lwm2m_state{life_timer = UpdatedLifeTimer,
                      reg_info = UpdatedRegInfo,
                      proto = NewProto}.

replace_reg_info(NewRegInfo, State=#lwm2m_state{life_timer = LifeTimer,
        proto = Proto, reg_info = RegInfo, coap_pid = CoapPid}) ->
    UpdatedLifeTimer = emqx_lwm2m_timer:refresh_timer(
                            maps:get(<<"lt">>, NewRegInfo), LifeTimer),

    NewProto = send_data(<<"register">>, #{<<"data">> => NewRegInfo}, Proto),

    flush_cached_downlink_messages(CoapPid),

    send_auto_observe(CoapPid, RegInfo, Proto),

    State#lwm2m_state{life_timer = UpdatedLifeTimer,
                      reg_info = NewRegInfo,
                      proto = NewProto}.

send_ul_data(_EventType, <<>>, _State) -> ok;
send_ul_data(EventType, Payload, State=#lwm2m_state{proto = Proto, coap_pid = CoapPid}) ->
    NewProto = send_data(EventType, Payload, Proto),
    flush_cached_downlink_messages(CoapPid),
    State#lwm2m_state{proto = NewProto}.

post_init(Lwm2mState = #lwm2m_state{proto = Proto, reg_info = RegInfo,
        coap_pid = CoapPid}) ->
    %% - subscribe to the downlink_topic and wait for commands
    Topic = downlink_topic(<<"register">>, Proto),
    Proto1 = proto_subscribe(CoapPid, Topic, _Qos = 0, Proto),
    %% - report the registration info
    Proto2 = send_data(<<"register">>, #{<<"data">> => RegInfo}, Proto1),
    Lwm2mState#lwm2m_state{proto = Proto2, sub_topic = Topic}.

auto_observe(Lwm2mState = #lwm2m_state{proto = Proto, reg_info = RegInfo,
        coap_pid = CoapPid}) ->
    send_auto_observe(CoapPid, RegInfo, Proto),
    Lwm2mState.

deliver(#message{topic = Topic, payload = Payload}, State = #lwm2m_state{
        proto = Proto, coap_pid = CoapPid, reg_info = RegInfo, started_at = StartedAt}) ->
    IsCacheMode = is_cache_mode(RegInfo, StartedAt),
    ?LOG(debug, "Get MQTT message from broker, IsCacheModeNow?: ~p, Topic: ~p, Payload: ~p", [IsCacheMode, Topic, Payload]),
    AlternatePath = maps:get(<<"alternatePath">>, RegInfo, <<"/">>),
    deliver_to_coap(AlternatePath, Payload, CoapPid, Proto, IsCacheMode),

    State#lwm2m_state{proto = Proto}.

get_info(Lwm2mState = #lwm2m_state{proto = ProtoState, peer = Channel}) ->
    ProtoInfo  = emqx_protocol:info(ProtoState),
    ClientInfo = [{peername, Channel}],
    {Stats, _} = get_stats(Lwm2mState),
    {lists:append([ClientInfo, ProtoInfo, Stats]), Lwm2mState}.

get_stats(Lwm2mState = #lwm2m_state{proto = ProtoState}) ->
    Stats = lists:append([emqx_misc:proc_stats(), emqx_protocol:stats(ProtoState)]),
    {Stats, Lwm2mState}.

terminate(Reason, #lwm2m_state{coap_pid = CoapPid, proto = Proto,
        life_timer = LifeTimer, sub_topic = SubTopic}) ->
    ?LOG(debug, "process terminated: ~p", [Reason]),
    is_reference(LifeTimer) andalso emqx_lwm2m_timer:cancel_timer(LifeTimer),
    clean_subscribe(CoapPid, Reason, SubTopic, Proto);
terminate(Reason, State) ->
    ?LOG(error, "process terminated: ~p, lwm2m_state: ~p", [Reason, State]).

clean_subscribe(_CoapPid, _Error, undefined, _Proto) -> ok;
clean_subscribe(_CoapPid, _Error, _SubTopic, undefined) -> ok;
clean_subscribe(CoapPid, {shutdown, Error}, SubTopic, Proto) ->
    do_clean_subscribe(CoapPid, Error, SubTopic, Proto);
clean_subscribe(CoapPid, Error, SubTopic, Proto) ->
    do_clean_subscribe(CoapPid, Error, SubTopic, Proto).

do_clean_subscribe(CoapPid, Error, SubTopic, Proto) ->
    ?LOG(debug, "unsubscribe ~p while exiting", [SubTopic]),
    NewProto = proto_unsubscribe(CoapPid, SubTopic, Proto),
    emqx_protocol:shutdown(Error, NewProto).

%%--------------------------------------------------------------------
%% Internal Functions
%%--------------------------------------------------------------------

proto_init(ClientId, Username, Password, Channel, Ver) ->
    SendFun = fun(_Packet) -> ok end,
    PktOpts = [{max_clientid_len, 96}, {max_packet_size, 512}, {protocol, lwm2m}],
    Proto = emqx_protocol:init(#{peername => Channel, peercert => nossl, sendfun => SendFun}, PktOpts),
    ConnPkt = #mqtt_packet_connect{proto_name  = <<"LwM2M">>,
                                   proto_ver   = Ver,
                                   client_id   = ClientId,
                                   username    = Username,
                                   password    = Password,
                                   clean_start = true,
                                   keepalive  = 0},
    emqx_protocol:received(?CONNECT_PACKET(ConnPkt), Proto).

proto_subscribe(CoapPid, Topic, Qos, ProtoState) ->
    Opts = #{rh => 0, rap => 0, nl => 0, qos => Qos, first => true},
    emqx:subscribe(Topic, CoapPid, Opts),
    emqx_hooks:run('session.subscribed', [#{client_id => emqx_protocol:client_id(ProtoState)}, Topic, Opts]),
    ProtoState.

proto_unsubscribe(CoapPid, Topic, ProtoState) ->
    Opts = #{rh => 0, rap => 0, nl => 0, qos => 0},
    emqx:unsubscribe(Topic, CoapPid),
    emqx_hooks:run('session.unsubscribed', [#{client_id => emqx_protocol:client_id(ProtoState)}, Topic, Opts]),
    ProtoState.

proto_publish(Topic, Payload, Qos, Proto) ->
    Publish = #mqtt_packet{header   = #mqtt_packet_header{type = ?PUBLISH, qos = Qos},
                           variable = #mqtt_packet_publish{topic_name = Topic, packet_id = 1},
                           payload  = Payload},
    case emqx_protocol:received(Publish, Proto) of
        {ok, Proto1}  -> Proto1;
        Other         -> error(Other)
    end.

deliver_to_coap(AlternatePath, JsonData, CoapPid, Proto, CacheMode) when is_binary(JsonData)->
    try
        TermData = jsx:decode(JsonData, [return_maps]),
        deliver_to_coap(AlternatePath, TermData, CoapPid, Proto, CacheMode)
    catch
        C:R:Stack ->
            ?LOG(error, "deliver_to_coap - Invalid JSON: ~p, Exception: ~p, stacktrace: ~p",
                [JsonData, {C, R}, Stack])
    end;

deliver_to_coap(AlternatePath, TermData, CoapPid, _Proto, CacheMode) when is_map(TermData) ->
    ?LOG(info, "SEND To CoAP, AlternatePath=~p, Data=~p", [AlternatePath, TermData]),
    {CoapRequest, Ref} = emqx_lwm2m_cmd_handler:mqtt2coap(AlternatePath, TermData),

    case CacheMode of
        false ->
            do_deliver_to_coap(CoapPid, CoapRequest, Ref);
        true ->
            cache_downlink_message(CoapRequest, Ref)
    end.

send_data(EventType, Payload = #{}, Proto) ->
    do_send_data(EventType, Payload, Proto).

do_send_data(EventType, Payload, Proto) ->
    NewPayload = maps:put(<<"msgType">>, EventType, Payload),
    Topic = uplink_topic(EventType, Proto),
    proto_publish(Topic, jsx:encode(NewPayload), _Qos = 0, Proto).

send_auto_observe(CoapPid, RegInfo, Proto) ->
    %% - auto observe the objects
    case application:get_env(?APP, auto_observe, false) of
        true ->
            AlternatePath = maps:get(<<"alternatePath">>, RegInfo, <<"/">>),
            auto_observe(AlternatePath, maps:get(<<"objectList">>, RegInfo, []), CoapPid, Proto);
        _ -> ?LOG(info, "Auto Observe Disabled", [])
    end.

auto_observe(AlternatePath, ObjectList, CoapPid, Proto) ->
    ?LOG(info, "Auto Observe on: ~p", [ObjectList]),
    erlang:spawn(fun() ->
            observe_object_list(AlternatePath, ObjectList, CoapPid, Proto)
        end).

observe_object_list(AlternatePath, ObjectList, CoapPid, Proto) ->
    lists:foreach(fun(ObjectPath) ->
        observe_object_slowly(AlternatePath, ObjectPath, CoapPid, Proto, 100)
    end, ObjectList).

observe_object_slowly(AlternatePath, ObjectPath, CoapPid, Proto, Interval) ->
    observe_object(AlternatePath, ObjectPath, CoapPid, Proto),
    timer:sleep(Interval).

observe_object(AlternatePath, ObjectPath, CoapPid, Proto) ->
    Payload = #{
        <<"msgType">> => <<"observe">>,
        <<"data">> => #{
            <<"path">> => ObjectPath
        }
    },
    ?LOG(info, "Observe ObjectPath: ~p", [ObjectPath]),
    deliver_to_coap(AlternatePath, Payload, CoapPid, Proto, false).

cache_downlink_message(CoapRequest, Ref) ->
    ?LOG(debug, "Cache downlink coap request: ~p, Ref: ~p", [CoapRequest, Ref]),
    put(dl_msg_cache, [{CoapRequest, Ref} | get_cached_downlink_messages()]).

flush_cached_downlink_messages(CoapPid) ->
    case erase(dl_msg_cache) of
        CachedMessageList when is_list(CachedMessageList)->
            do_deliver_to_coap_slowly(CoapPid, CachedMessageList, 100);
        undefined -> ok
    end.

get_cached_downlink_messages() ->
    case get(dl_msg_cache) of
        undefined -> [];
        CachedMessageList -> CachedMessageList
    end.

do_deliver_to_coap_slowly(CoapPid, CoapRequestList, Interval) ->
    erlang:spawn(fun() ->
        lists:foreach(fun({CoapRequest, Ref}) ->
                do_deliver_to_coap(CoapPid, CoapRequest, Ref),
                timer:sleep(Interval)
            end, lists:reverse(CoapRequestList))
        end).

do_deliver_to_coap(CoapPid, CoapRequest, Ref) ->
    ?LOG(debug, "Deliver To CoAP(~p), CoapRequest: ~p", [CoapPid, CoapRequest]),
    CoapPid ! {deliver_to_coap, CoapRequest, Ref}.

is_cache_mode(RegInfo, StartedAt) ->
    case is_psm(RegInfo) orelse is_qmode(RegInfo) of
        true ->
            QModeTimeWind = application:get_env(?APP, qmode_time_window, 22),
            Now = time_now(),
            if (Now - StartedAt) >= QModeTimeWind -> true;
                true -> false
            end;
        false -> false
    end.

is_psm(_) -> false.

is_qmode(#{<<"b">> := Binding}) when Binding =:= <<"UQ">>;
                                     Binding =:= <<"SQ">>;
                                     Binding =:= <<"UQS">>
            -> true;
is_qmode(_) -> false.

downlink_topic(EventType, ProtoState) ->
    Topics = application:get_env(?APP, topics, []),
    DnTopic = proplists:get_value(downlink_topic_key(EventType), Topics,
                                    default_downlink_topic(EventType)),
    take_place(iolist_to_binary(DnTopic), ProtoState).

uplink_topic(EventType, ProtoState) ->
    Topics = application:get_env(?APP, topics, []),
    UpTopic = proplists:get_value(uplink_topic_key(EventType), Topics,
                                    default_uplink_topic(EventType)),
    take_place(iolist_to_binary(UpTopic), ProtoState).

downlink_topic_key(EventType) when is_binary(EventType) ->
    command.

uplink_topic_key(<<"notify">>) -> notify;
uplink_topic_key(<<"register">>) -> register;
uplink_topic_key(<<"update">>) -> update;
uplink_topic_key(EventType) when is_binary(EventType) ->
    response.

default_downlink_topic(Type) when is_binary(Type)->
    <<"lwm2m/%e/dn/#">>.

default_uplink_topic(<<"notify">>) ->
    <<"lwm2m/%e/up/notify">>;
default_uplink_topic(Type) when is_binary(Type) ->
    <<"lwm2m/%e/up/resp">>.

take_place(Text, ProtoState) ->
    {IPAddr, _Port} = emqx_protocol:peername(ProtoState),
    IPAddrBin = iolist_to_binary(esockd_net:ntoa(IPAddr)),
    take_place(take_place(Text, <<"%a">>, IPAddrBin),
                    <<"%e">>, emqx_protocol:client_id(ProtoState)).

take_place(Text, Placeholder, Value) ->
    binary:replace(Text, Placeholder, Value, [global]).

time_now() -> erlang:system_time(second).
