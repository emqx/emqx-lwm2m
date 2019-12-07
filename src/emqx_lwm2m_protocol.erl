%%--------------------------------------------------------------------
%% Copyright (c) 2019 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_lwm2m_protocol).

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

-record(lwm2m_state, {  peerhost
                      , endpoint_name
                      , version
                      , lifetime
                      , coap_pid
                      , register_info
                      , mqtt_topic
                      , life_timer
                      , started_at
                      , mountpoint
                      }).

-define(DEFAULT_KEEP_ALIVE_DURATION,  60*2).

-define(LOG(Level, Format, Args), logger:Level("LWM2M-PROTO: " ++ Format, Args)).

%%--------------------------------------------------------------------
%% APIs
%%--------------------------------------------------------------------
init(CoapPid, EndpointName, {PeerHost, _Port}, RegInfo = #{<<"lt">> := LifeTime, <<"lwm2m">> := Ver}) ->
    Mountpoint = list_to_binary(application:get_env(?APP, mountpoint, "")),
    Lwm2mState = #lwm2m_state{peerhost = PeerHost,
                              endpoint_name = EndpointName,
                              version = Ver,
                              lifetime = LifeTime,
                              coap_pid = CoapPid,
                              register_info = RegInfo,
                              mountpoint = Mountpoint},
    Credentials = credentials(Lwm2mState),
    case emqx_access_control:authenticate(Credentials) of
        {ok, AuthResult} ->
            Credentials1 = maps:merge(Credentials, AuthResult),
            emqx_hooks:run('client.connected',
                          [Credentials1, ?RC_SUCCESS,
                          #{clean_start => true,
                            expiry_interval => 0,
                            proto_name => lwm2m,
                            peerhost => PeerHost,
                            connected_at => os:timestamp(),
                            keepalive => LifeTime,
                            proto_ver => <<"lwm2m">>}]),
            erlang:send(CoapPid, post_init),
            erlang:send_after(2000, CoapPid, auto_observe),
            {ok, Lwm2mState#lwm2m_state{started_at = time_now(),
                                        life_timer = emqx_lwm2m_timer:start_timer(LifeTime, {life_timer, expired}),
                                        mountpoint = maps:get(mountpoint, Credentials1)
                                        }};
        {error, Error} ->
            emqx_hooks:run('client.connected', [Credentials, ?RC_NOT_AUTHORIZED, #{}]),
            {error, Error}
    end.


post_init(Lwm2mState = #lwm2m_state{endpoint_name = EndpointName,
                                    register_info = RegInfo,
                                    coap_pid = CoapPid}) ->
    %% - subscribe to the downlink_topic and wait for commands
    Topic = downlink_topic(<<"register">>, Lwm2mState),
    subscribe(CoapPid, Topic, _Qos = 0, EndpointName),
    %% - report the registration info
    send_to_broker(<<"register">>, #{<<"data">> => RegInfo}, Lwm2mState),
    Lwm2mState#lwm2m_state{mqtt_topic = Topic}.

update_reg_info(NewRegInfo, Lwm2mState=#lwm2m_state{life_timer = LifeTimer, register_info = RegInfo,
                                                    coap_pid = CoapPid}) ->
    UpdatedRegInfo = maps:merge(RegInfo, NewRegInfo),

    %% - report the registration info update, but only when objectList is updated.
    case NewRegInfo of
        #{<<"objectList">> := _} ->
            send_to_broker(<<"update">>, #{<<"data">> => UpdatedRegInfo}, Lwm2mState);
        _ -> ok
    end,

    %% - flush cached donwlink commands
    flush_cached_downlink_messages(CoapPid),

    %% - update the life timer
    UpdatedLifeTimer = emqx_lwm2m_timer:refresh_timer(
                            maps:get(<<"lt">>, UpdatedRegInfo), LifeTimer),

    ?LOG(debug, "Update RegInfo to: ~p", [UpdatedRegInfo]),
    Lwm2mState#lwm2m_state{life_timer = UpdatedLifeTimer,
                           register_info = UpdatedRegInfo}.

replace_reg_info(NewRegInfo, Lwm2mState=#lwm2m_state{life_timer = LifeTimer,
                                                     coap_pid = CoapPid}) ->
    send_to_broker(<<"register">>, #{<<"data">> => NewRegInfo}, Lwm2mState),

    %% - flush cached donwlink commands
    flush_cached_downlink_messages(CoapPid),

    %% - update the life timer
    UpdatedLifeTimer = emqx_lwm2m_timer:refresh_timer(
                            maps:get(<<"lt">>, NewRegInfo), LifeTimer),

    send_auto_observe(CoapPid, NewRegInfo),

    ?LOG(debug, "Replace RegInfo to: ~p", [NewRegInfo]),
    Lwm2mState#lwm2m_state{life_timer = UpdatedLifeTimer,
                           register_info = NewRegInfo}.

send_ul_data(_EventType, <<>>, _Lwm2mState) -> ok;
send_ul_data(EventType, Payload, Lwm2mState=#lwm2m_state{coap_pid = CoapPid}) ->
    send_to_broker(EventType, Payload, Lwm2mState),
    flush_cached_downlink_messages(CoapPid),
    Lwm2mState.

auto_observe(Lwm2mState = #lwm2m_state{register_info = RegInfo,
                                       coap_pid = CoapPid}) ->
    send_auto_observe(CoapPid, RegInfo),
    Lwm2mState.

deliver(#message{topic = Topic, payload = Payload}, Lwm2mState = #lwm2m_state{coap_pid = CoapPid, register_info = RegInfo, started_at = StartedAt}) ->
    IsCacheMode = is_cache_mode(RegInfo, StartedAt),
    ?LOG(debug, "Get MQTT message from broker, IsCacheModeNow?: ~p, Topic: ~p, Payload: ~p", [IsCacheMode, Topic, Payload]),
    AlternatePath = maps:get(<<"alternatePath">>, RegInfo, <<"/">>),
    deliver_to_coap(AlternatePath, Payload, CoapPid, IsCacheMode),
    Lwm2mState.

get_info(Lwm2mState = #lwm2m_state{endpoint_name = EndpointName, peerhost = PeerHost,
                                   started_at = StartedAt}) ->
    ProtoInfo  = [{peerhost, PeerHost}, {endpoint_name, EndpointName}, {started_at, StartedAt}],
    {Stats, _} = get_stats(Lwm2mState),
    {lists:append([ProtoInfo, Stats]), Lwm2mState}.

get_stats(Lwm2mState) ->
    Stats = emqx_misc:proc_stats(),
    {Stats, Lwm2mState}.

terminate(Reason, Lwm2mState = #lwm2m_state{coap_pid = CoapPid, life_timer = LifeTimer,
                                            mqtt_topic = SubTopic}) ->
    ?LOG(debug, "process terminated: ~p", [Reason]),
    is_reference(LifeTimer) andalso emqx_lwm2m_timer:cancel_timer(LifeTimer),
    clean_subscribe(CoapPid, Reason, SubTopic, Lwm2mState);
terminate(Reason, Lwm2mState) ->
    ?LOG(error, "process terminated: ~p, lwm2m_state: ~p", [Reason, Lwm2mState]).

clean_subscribe(_CoapPid, _Error, undefined, _Lwm2mState) -> ok;
clean_subscribe(_CoapPid, _Error, _SubTopic, undefined) -> ok;
clean_subscribe(CoapPid, {shutdown, Error}, SubTopic, Lwm2mState) ->
    do_clean_subscribe(CoapPid, Error, SubTopic, Lwm2mState);
clean_subscribe(CoapPid, Error, SubTopic, Lwm2mState) ->
    do_clean_subscribe(CoapPid, Error, SubTopic, Lwm2mState).

do_clean_subscribe(CoapPid, Error, SubTopic, Lwm2mState) ->
    ?LOG(debug, "unsubscribe ~p while exiting", [SubTopic]),
    unsubscribe(CoapPid, SubTopic, Lwm2mState#lwm2m_state.endpoint_name),
    emqx_hooks:run('client.disconnected', [credentials(Lwm2mState), Error]).

subscribe(_CoapPid, Topic, Qos, EndpointName) ->
    Opts = #{rh => 0, rap => 0, nl => 0, qos => Qos, first => true},
    emqx_broker:subscribe(Topic, EndpointName, Opts),
    emqx_hooks:run('session.subscribed', [#{clientid => EndpointName}, Topic, Opts]).

unsubscribe(_CoapPid, Topic, EndpointName) ->
    Opts = #{rh => 0, rap => 0, nl => 0, qos => 0},
    emqx_broker:unsubscribe(Topic),
    emqx_hooks:run('session.unsubscribed', [#{clientid => EndpointName}, Topic, Opts]).

publish(Topic, Payload, Qos, EndpointName) ->
    emqx_broker:publish(emqx_message:set_flag(retain, false, emqx_message:make(EndpointName, Qos, Topic, Payload))).

time_now() -> erlang:system_time(second).

%%--------------------------------------------------------------------
%% Deliver downlink message to coap
%%--------------------------------------------------------------------

deliver_to_coap(AlternatePath, JsonData, CoapPid, CacheMode) when is_binary(JsonData)->
    try
        TermData = jsx:decode(JsonData, [return_maps]),
        deliver_to_coap(AlternatePath, TermData, CoapPid, CacheMode)
    catch
        C:R:Stack ->
            ?LOG(error, "deliver_to_coap - Invalid JSON: ~p, Exception: ~p, stacktrace: ~p",
                [JsonData, {C, R}, Stack])
    end;

deliver_to_coap(AlternatePath, TermData, CoapPid, CacheMode) when is_map(TermData) ->
    ?LOG(info, "SEND To CoAP, AlternatePath=~p, Data=~p", [AlternatePath, TermData]),
    {CoapRequest, Ref} = emqx_lwm2m_cmd_handler:mqtt2coap(AlternatePath, TermData),

    case CacheMode of
        false ->
            do_deliver_to_coap(CoapPid, CoapRequest, Ref);
        true ->
            cache_downlink_message(CoapRequest, Ref)
    end.

%%--------------------------------------------------------------------
%% Send uplink message to broker
%%--------------------------------------------------------------------

send_to_broker(EventType, Payload = #{}, Lwm2mState) ->
    do_send_to_broker(EventType, Payload, Lwm2mState).

do_send_to_broker(EventType, Payload, Lwm2mState) ->
    NewPayload = maps:put(<<"msgType">>, EventType, Payload),
    Topic = uplink_topic(EventType, Lwm2mState),
    publish(Topic, jsx:encode(NewPayload), _Qos = 0, Lwm2mState#lwm2m_state.endpoint_name).

%%--------------------------------------------------------------------
%% Auto Observe
%%--------------------------------------------------------------------

send_auto_observe(CoapPid, RegInfo) ->
    %% - auto observe the objects
    case application:get_env(?APP, auto_observe, false) of
        true ->
            AlternatePath = maps:get(<<"alternatePath">>, RegInfo, <<"/">>),
            auto_observe(AlternatePath, maps:get(<<"objectList">>, RegInfo, []), CoapPid);
        _ -> ?LOG(info, "Auto Observe Disabled", [])
    end.

auto_observe(AlternatePath, ObjectList, CoapPid) ->
    ?LOG(info, "Auto Observe on: ~p", [ObjectList]),
    erlang:spawn(fun() ->
            observe_object_list(AlternatePath, ObjectList, CoapPid)
        end).

observe_object_list(AlternatePath, ObjectList, CoapPid) ->
    lists:foreach(fun(ObjectPath) ->
        observe_object_slowly(AlternatePath, ObjectPath, CoapPid, 100)
    end, ObjectList).

observe_object_slowly(AlternatePath, ObjectPath, CoapPid, Interval) ->
    observe_object(AlternatePath, ObjectPath, CoapPid),
    timer:sleep(Interval).

observe_object(AlternatePath, ObjectPath, CoapPid) ->
    Payload = #{
        <<"msgType">> => <<"observe">>,
        <<"data">> => #{
            <<"path">> => ObjectPath
        }
    },
    ?LOG(info, "Observe ObjectPath: ~p", [ObjectPath]),
    deliver_to_coap(AlternatePath, Payload, CoapPid, false).

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

%%--------------------------------------------------------------------
%% Queue Mode
%%--------------------------------------------------------------------

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

%%--------------------------------------------------------------------
%% Construct downlink and uplink topics
%%--------------------------------------------------------------------

downlink_topic(EventType, Lwm2mState = #lwm2m_state{mountpoint = Mountpoint}) ->
    Topics = application:get_env(?APP, topics, []),
    DnTopic = proplists:get_value(downlink_topic_key(EventType), Topics,
                                  default_downlink_topic(EventType)),
    take_place(mountpoint(iolist_to_binary(DnTopic), Mountpoint), Lwm2mState).

uplink_topic(EventType, Lwm2mState = #lwm2m_state{mountpoint = Mountpoint}) ->
    Topics = application:get_env(?APP, topics, []),
    UpTopic = proplists:get_value(uplink_topic_key(EventType), Topics,
                                  default_uplink_topic(EventType)),
    take_place(mountpoint(iolist_to_binary(UpTopic), Mountpoint), Lwm2mState).

downlink_topic_key(EventType) when is_binary(EventType) ->
    command.

uplink_topic_key(<<"notify">>) -> notify;
uplink_topic_key(<<"register">>) -> register;
uplink_topic_key(<<"update">>) -> update;
uplink_topic_key(EventType) when is_binary(EventType) ->
    response.

default_downlink_topic(Type) when is_binary(Type)->
    <<"dn/#">>.

default_uplink_topic(<<"notify">>) ->
    <<"up/notify">>;
default_uplink_topic(Type) when is_binary(Type) ->
    <<"up/resp">>.

take_place(Text, Lwm2mState) ->
    IPAddr = Lwm2mState#lwm2m_state.peerhost,
    IPAddrBin = iolist_to_binary(inet:ntoa(IPAddr)),
    take_place(take_place(Text, <<"%a">>, IPAddrBin),
                    <<"%e">>, Lwm2mState#lwm2m_state.endpoint_name).

take_place(Text, Placeholder, Value) ->
    binary:replace(Text, Placeholder, Value, [global]).

credentials(#lwm2m_state{peerhost = PeerHost,
                         endpoint_name = EndpointName,
                         mountpoint = Mountpoint}) ->
    #{peerhost => PeerHost,
      clientid => EndpointName,
      username => null,
      password => null,
      mountpoint => Mountpoint,
      zone => external}.


mountpoint(Topic, <<>>) ->
    Topic;
mountpoint(Topic, Mountpoint) ->
    <<Mountpoint/binary, Topic/binary>>.
