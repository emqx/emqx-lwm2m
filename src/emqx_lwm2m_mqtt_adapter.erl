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

-author("Feng Lee <feng@emqtt.io>").

-behaviour(gen_server).

-include("emqx_lwm2m.hrl").

-include_lib("emqx/include/emqx.hrl").

-include_lib("emqx/include/emqx_mqtt.hrl").

-include_lib("emqx/include/emqx_internal.hrl").

%% API.
-export([start_link/4, send_ul_data/3, update_reg_info/2, replace_reg_info/2]).
-export([stop/1]).

%% gen_server.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
    terminate/2, code_change/3]).

-record(state, {proto, peer, life_timer, coap_pid, sub_topic, reg_info}).

-define(DEFAULT_KEEP_ALIVE_DURATION,  60*2).

-define(LOG(Level, Format, Args),
    lager:Level("LWM2M-MQTT: " ++ Format, Args)).

%% Protocol State, copied from emqx_protocol
%% ws_initial_headers: Headers from first HTTP request for WebSocket Client.
-record(proto_state, {peername, sendfun, connected = false, client_id, client_pid,
                      clean_sess, proto_ver, proto_name, username, is_superuser,
                      will_msg, keepalive, keepalive_backoff, max_clientid_len,
                      session, stats_data, mountpoint, ws_initial_headers,
                      peercert_username, is_bridge, connected_at, headers = [], proto}).
%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------


start_link(CoapPid, ClientId, ChId, RegInfo) ->
    gen_server:start_link({via, emqx_lwm2m_registry, ChId}, ?MODULE, {CoapPid, ClientId, ChId, RegInfo}, []).

stop(ChId) ->
    gen_server:stop(emqx_lwm2m_registry:whereis_name(ChId)).

update_reg_info(ChId, RegInfo) ->
    gen_server:cast({via, emqx_lwm2m_registry, ChId}, {update_reg_info, RegInfo}).

replace_reg_info(ChId, RegInfo) ->
    gen_server:cast({via, emqx_lwm2m_registry, ChId}, {replace_reg_info, RegInfo}).

send_ul_data(_ChId, _EventType, <<>>) -> ok;
send_ul_data(ChId, EventType, Payload) ->
    gen_server:cast({via, emqx_lwm2m_registry, ChId}, {send_ul_data, EventType, Payload}).

%%--------------------------------------------------------------------
%% gen_server Callbacks
%%--------------------------------------------------------------------

init({CoapPid, ClientId, ChId, RegInfo = #{<<"lt">> := LifeTime}}) ->
    case proto_init(ClientId, undefined, undefined, ChId, LifeTime, []) of
        {ok, Proto} ->
            ?LOG(debug, "start adapter ClientId=~p, ChId=~p", [ClientId, ChId]),
            self() ! post_init_process,
            {ok, #state{
                coap_pid = CoapPid,
                proto = Proto,
                peer = ChId,
                reg_info = RegInfo,
                life_timer = emqx_lwm2m_timer:start_timer(LifeTime, {life_timer, expired})
            }};
        {stop, Reason} -> {stop, Reason};
        Reason -> {stop, Reason}
    end.

handle_call(info, From, State = #state{proto = ProtoState, peer = Channel}) ->
    ProtoInfo  = emqx_protocol:info(ProtoState),
    ClientInfo = [{peername, Channel}],
    {reply, Stats, _, _} = handle_call(stats, From, State),
    {reply, lists:append([ClientInfo, ProtoInfo, Stats]), State};

handle_call(stats, _From, State = #state{proto = ProtoState}) ->
    {reply, lists:append([emqx_misc:proc_stats(), emqx_protocol:stats(ProtoState)]), State};

handle_call(kick, _From, State) ->
    {stop, {shutdown, kick}, ok, State};

handle_call({set_rate_limit, _Rl}, _From, State) ->
    ?LOG(error, "set_rate_limit is not support", []),
    {reply, ok, State};

handle_call(get_rate_limit, _From, State) ->
    ?LOG(error, "get_rate_limit is not support", []),
    {reply, ok, State};

handle_call(session, _From, State = #state{proto = ProtoState}) ->
    {reply, emqx_protocol:session(ProtoState), State};

handle_call(Request, _From, State) ->
    ?LOG(error, "adapter unexpected call ~p", [Request]),
    {reply, ignored, State, hibernate}.

handle_cast({send_ul_data, EventType, Payload}, State=#state{proto = Proto, coap_pid = CoapPid}) ->
    NewProto = send_data(EventType, Payload, Proto),
    flush_cached_downlink_messages(CoapPid),
    {noreply, State#state{proto = NewProto}};

handle_cast({update_reg_info, NewRegInfo}, State=#state{life_timer = LifeTimer, reg_info = RegInfo, proto = Proto, coap_pid = CoapPid}) ->
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
    {noreply, State#state{life_timer = UpdatedLifeTimer, reg_info = UpdatedRegInfo, proto = NewProto}, hibernate};

handle_cast({replace_reg_info, NewRegInfo}, State=#state{life_timer = LifeTimer, proto = Proto, coap_pid = CoapPid}) ->
    UpdatedLifeTimer = emqx_lwm2m_timer:refresh_timer(maps:get(<<"lt">>, NewRegInfo), LifeTimer),
    NewProto = send_data(<<"register">>, #{<<"data">> => NewRegInfo}, Proto),

    flush_cached_downlink_messages(CoapPid),
    {noreply, State#state{life_timer = UpdatedLifeTimer, reg_info = NewRegInfo, proto = NewProto}, hibernate};

handle_cast(Msg, State) ->
    ?LOG(error, "unexpected cast ~p", [Msg]),
    {noreply, State, hibernate}.

handle_info({deliver, Msg = #mqtt_message{topic = TopicName, payload = Payload}},
             State = #state{proto = Proto, coap_pid = CoapPid, reg_info = RegInfo}) ->
    %% handle PUBLISH from broker
    ?LOG(debug, "Get MQTT message from broker, Topic: ~p, Payload: ~p", [TopicName, Payload]),
    #{<<"alternatePath">> := AlternatePath} = RegInfo,
    deliver_to_coap(AlternatePath, Payload, CoapPid, Proto, is_cache_mode(RegInfo)),

    NewProto = proto_deliver_ack(Msg, Proto),
    {noreply, State#state{proto = NewProto}};

handle_info({suback, _MsgId, [_GrantedQos]}, State) ->
    {noreply, State};

handle_info(post_init_process, State = #state{proto = Proto, reg_info = RegInfo, coap_pid = CoapPid}) ->
    %% - subscribe to the downlink_topic and wait for commands
    {Topic, Qos} = downlink_topic(<<"register">>, Proto),
    Proto1 = proto_subscribe(Topic, Qos, Proto),

    %% - report the registration info
    Proto2 = send_data(<<"register">>, #{<<"data">> => RegInfo}, Proto1),

    %% - auto observe the objects, for demo only
    case proplists:get_value(lwm2m_auto_observe, Proto#proto_state.headers, false) of
        true ->
            #{<<"alternatePath">> := AlternatePath} = RegInfo,
            auto_observe(AlternatePath, maps:get(<<"objectList">>, RegInfo, []), CoapPid, Proto);
        _ -> ok
    end,
    {noreply, State#state{proto = Proto2, sub_topic = Topic}};

handle_info({life_timer, expired}, State) ->
    ?LOG(debug, "LifeTime expired", []),
    {stop, {shutdown, life_timer_timeout}, State};

handle_info(emit_stats, State) ->
    ?LOG(info, "emit_stats is not supported", []),
    {noreply, State, hibernate};

handle_info(timeout, State) ->
    {stop, {shutdown, idle_timeout}, State};

handle_info({shutdown, Error}, State) ->
    {stop, {shutdown, Error}, State};

handle_info({shutdown, conflict, {ClientId, NewPid}}, State) ->
    ?LOG(warning, "clientid '~s' conflict with ~p", [ClientId, NewPid]),
    {stop, {shutdown, conflict}, State};

handle_info(Info, State) ->
    ?LOG(error, "unexpected info ~p", [Info]),
    {noreply, State, hibernate}.

terminate(Reason, #state{proto = Proto, life_timer = LifeTimer, sub_topic = SubTopic}) ->
    ?LOG(debug, "process terminated: ~p", [Reason]),
    is_reference(LifeTimer) andalso emqx_lwm2m_timer:cancel_timer(LifeTimer),
    clean_subscribe(Reason, SubTopic, Proto).

clean_subscribe(_Error, undefined, _Proto) -> ok;
clean_subscribe(_Error, _SubTopic, undefined) -> ok;
clean_subscribe({shutdown, Error}, SubTopic, Proto) ->
    do_clean_subscribe(Error, SubTopic, Proto);
clean_subscribe(Error, SubTopic, Proto) ->
    do_clean_subscribe(Error, SubTopic, Proto).

do_clean_subscribe(Error, SubTopic, Proto) ->
    ?LOG(debug, "unsubscribe ~p while exiting", [SubTopic]),
    NewProto = proto_unsubscribe(SubTopic, Proto),
    emqx_protocol:shutdown(Error, NewProto).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Internal Functions
%%--------------------------------------------------------------------

proto_init(ClientId, Username, Password, Channel, LifeTime, LwM2MOpts) ->
    SendFun = fun(_Packet) -> ok end,
    PktOpts = [{max_clientid_len, 96}, {max_packet_size, 512}, {protocol, lwm2m}],
    Proto = emqx_protocol:init(Channel, SendFun, PktOpts),
    NewProto = Proto#proto_state{headers = LwM2MOpts},
    ConnPkt = #mqtt_packet_connect{client_id  = ClientId,
                                   username   = Username,
                                   password   = Password,
                                   clean_sess = true,
                                   keep_alive = LifeTime},
    case emqx_protocol:received(?CONNECT_PACKET(ConnPkt), NewProto) of
        {ok, Proto1}                              -> {ok, Proto1};
        {stop, {shutdown, auth_failure}, _Proto2} -> {stop, auth_failure};
        Other                                     -> Other
    end.

proto_subscribe(Topic, Qos, Proto) ->
    case emqx_protocol:received(?SUBSCRIBE_PACKET(1, [{Topic, Qos}]), Proto) of
        {ok, Proto1}  -> Proto1;
        Other         -> error(Other)
    end.

proto_unsubscribe(Topic, Proto) ->
    case emqx_protocol:received(?UNSUBSCRIBE_PACKET(1, [Topic]), Proto) of
        {ok, Proto1}  -> Proto1;
        Other         -> error(Other)
    end.

proto_publish(Topic, Payload, Qos, Proto) ->
    Publish = #mqtt_packet{header   = #mqtt_packet_header{type = ?PUBLISH, qos = Qos},
                           variable = #mqtt_packet_publish{topic_name = Topic, packet_id = 1},
                           payload  = Payload},
    case emqx_protocol:received(Publish, Proto) of
        {ok, Proto1}  -> Proto1;
        Other         -> error(Other)
    end.

proto_deliver_ack(#mqtt_message{qos = ?QOS0, pktid = _PacketId}, Proto) ->
    Proto;
proto_deliver_ack(#mqtt_message{qos = ?QOS1, pktid = PacketId}, Proto) ->
    case emqx_protocol:received(?PUBACK_PACKET(?PUBACK, PacketId), Proto) of
        {ok, NewProto} -> NewProto;
        Other          -> error(Other)
    end;
proto_deliver_ack(#mqtt_message{qos = ?QOS2, pktid = PacketId}, Proto) ->
    case emqx_protocol:received(?PUBACK_PACKET(?PUBREC, PacketId), Proto) of
        {ok, NewProto} ->
            case emqx_protocol:received(?PUBACK_PACKET(?PUBCOMP, PacketId), NewProto) of
                {ok, CurrentProto} -> CurrentProto;
                Another            -> error(Another)
            end;
        Other          -> error(Other)
    end.


deliver_to_coap(AlternatePath, JsonData, CoapPid, Proto, CacheMode) when is_binary(JsonData)->
    try
        TermData = jsx:decode(JsonData, [return_maps]),
        deliver_to_coap(AlternatePath, TermData, CoapPid, Proto, CacheMode)
    catch
        ExClass:Error ->
            ?LOG(error, "deliver_to_coap - Invalid JSON: ~p, Exception: ~p, stacktrace: ~p",
                [JsonData, {ExClass, Error}, erlang:get_stacktrace()])
    end;

deliver_to_coap(AlternatePath, TermData, CoapPid, _Proto, CacheMode) when is_map(TermData) ->
    ?LOG(info, "SEND To CoAP, AlternatePath=~p, Data=~p", [AlternatePath, TermData]),
    {CoapRequest, Ref} = emqx_lwm2m_cmd_handler:mqtt_payload_to_coap_request(AlternatePath, TermData),
    case CacheMode of
        false ->
            do_deliver_to_coap(CoapPid, CoapRequest, Ref);
        true ->
            cache_downlink_message(CoapRequest, Ref)
    end.

downlink_topic(EventType, #proto_state{client_id = ClientID, headers = Headers}) ->
    proplists:get_value(downlink_topic_key(EventType), Headers, default_downlink_topic(EventType, ClientID)).

uplink_topic(EventType, #proto_state{client_id = ClientID, headers = Headers}) ->
    proplists:get_value(uplink_topic_key(EventType), Headers, default_uplink_topic(EventType, ClientID)).

downlink_topic_key(Type)  when is_binary(Type) -> lwm2m_dn_dm_topic.

uplink_topic_key(<<"notify">>) -> lwm2m_up_ad_topic;
uplink_topic_key(<<"register">>) -> lwm2m_up_ol_topic;
uplink_topic_key(<<"update">>) -> lwm2m_up_ol_topic;
uplink_topic_key(Type) when is_binary(Type) -> lwm2m_up_dm_topic.

default_downlink_topic(Type, ClientID) when is_binary(Type)->
    {<<"lwm2m/", ClientID/binary, "/dn/#">>, 0}.

default_uplink_topic(<<"notify">>, ClientID) ->
    {<<"lwm2m/", ClientID/binary, "/up/ad">>, 0};
default_uplink_topic(Type, ClientID) when is_binary(Type) ->
    {<<"lwm2m/", ClientID/binary, "/up/dm">>, 0}.

send_data(EventType, Payload = #{}, Proto)
        when %% Send an extra "notify" for "observe" and "cancel-observe" responses
            EventType =:= <<"observe">>;
            EventType =:= <<"cancel-observe">>
        ->
    do_send_data(<<"notify">>, Payload, Proto),
    do_send_data(EventType, Payload, Proto);
send_data(EventType, Payload = #{}, Proto) ->
    do_send_data(EventType, Payload, Proto).

do_send_data(EventType, Payload, Proto) ->
    NewPayload = maps:put(<<"msgType">>, EventType, Payload),
    {Topic, Qos} = uplink_topic(EventType, Proto),
    proto_publish(Topic, jsx:encode(NewPayload), Qos, Proto).

auto_observe(AlternatePath, ObjectList, CoapPid, Proto) ->
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
    ObservePayload = #{
        <<"msgType">> => <<"observe">>,
        <<"data">> => #{
            <<"path">> => ObjectPath
        }
    },
    ?LOG(info, "Observe ObjectPath: ~p", [ObjectPath]),
    deliver_to_coap(AlternatePath, ObservePayload, CoapPid, Proto, false),

    DiscoverPayload = #{
        <<"msgType">> => <<"discover">>,
        <<"data">> => #{
            <<"path">> => ObjectPath
        }
    },
    ?LOG(info, "Discover ObjectPath: ~p", [ObjectPath]),
    deliver_to_coap(AlternatePath, DiscoverPayload, CoapPid, Proto, false).

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
    ?LOG(debug, "Deliver To CoAP(~p), CoapRequest: ~p, Ref: ~p", [CoapPid, CoapRequest, Ref]),
    CoapPid ! {dispatch_command, CoapRequest, Ref}.

is_cache_mode(#{<<"apn">> := APN})
    when
        APN =:= <<"psmA.eDRX0.ctnb">>;
        APN =:= <<"psmC.eDRX0.ctnb">>;
        APN =:= <<"psmF.eDRXC.ctnb">>
    -> true;
is_cache_mode(#{<<"b">> := Binding})
    when
        Binding =:= <<"UQ">>;
        Binding =:= <<"SQ">>;
        Binding =:= <<"UQS">>
    -> true;
is_cache_mode(_) -> false.
