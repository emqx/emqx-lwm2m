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

-module(emqx_lwm2m_coap_resource).

-author("Feng Lee <feng@emqtt.io>").

-include_lib("emqx/include/emqx.hrl").

-include_lib("emqx/include/emqx_mqtt.hrl").

-include_lib("emqx/include/emqx_internal.hrl").

-include_lib("lwm2m_coap/include/coap.hrl").

-behaviour(lwm2m_coap_resource).

-export([coap_discover/2, coap_get/4, coap_post/4, coap_put/4, coap_delete/3,
    coap_observe/4, coap_unobserve/1, handle_info/2, coap_ack/2]).

-export([parse_object_list/1]).

-include("emqx_lwm2m.hrl").

-define(PREFIX, <<"rd">>).

-define(LOG(Level, Format, Args),
    lager:Level("LWM2M-RESOURCE: " ++ Format, Args)).

% resource operations
coap_discover(_Prefix, _Args) ->
    [{absolute, "mqtt", []}].

coap_get(ChId, [?PREFIX], Query, Content) ->
    ?LOG(debug, "~p ~p GET Query=~p, Content=~p", [self(),ChId, Query, Content]),
    #coap_content{};
coap_get(ChId, Prefix, Query, Content) ->
    ?LOG(error, "ignore bad put request ChId=~p, Prefix=~p, Query=~p, Content=~p", [ChId, Prefix,  Query, Content]),
    {error, bad_request}.

% LWM2M REGISTER COMMAND
coap_post(ChId, [?PREFIX], Query, Content = #coap_content{uri_path = [?PREFIX]}) ->
    ?LOG(debug, "~p ~p REGISTER command Query=~p, Content=~p", [self(), ChId, Query, Content]),
    case parse_options(Query) of
        {error, {bad_opt, _CustomOption}} ->
            ?LOG(error, "Reject REGISTER from ~p due to wrong option", [ChId]),
            {error, bad_request};
        {ok, LwM2MQuery} ->
            process_register(ChId, LwM2MQuery, Content#coap_content.payload)
    end;

% LWM2M UPDATE COMMAND
coap_post(ChId, [?PREFIX], Query, Content = #coap_content{uri_path = LocationPath}) ->
    ?LOG(debug, "~p ~p UPDATE command location=~p, Query=~p, Content=~p", [self(), ChId, LocationPath, Query, Content]),
    case parse_options(Query) of
        {error, {bad_opt, _CustomOption}} ->
            ?LOG(error, "Reject UPDATE from ~p due to wrong option, Query=~p", [ChId, Query]),
            {error, bad_request};
        {ok, LwM2MQuery} ->
            process_update(ChId, LwM2MQuery, LocationPath, Content#coap_content.payload)
    end;

coap_post(ChId, Prefix, Query, Content) ->
    ?LOG(error, "bad post request ChId=~p, Prefix=~p, Query=~p, Content=~p", [ChId, Prefix, Query, Content]),
    {error, bad_request}.

coap_put(_ChId, Prefix, Query, Content) ->
    ?LOG(error, "put has error, Prefix=~p, Query=~p, Content=~p", [Prefix, Query, Content]),
    {error, bad_request}.

% LWM2M DE-REGISTER COMMAND
coap_delete(ChId, [?PREFIX], #coap_content{uri_path = Location}) ->
    LocationPath = binary_util:join_path(Location),
    ?LOG(debug, "~p ~p DELETE command location=~p", [self(), ChId, LocationPath]),
    case get(lwm2m_context) of
        #lwm2m_context{location = LocationPath} ->
            emqx_lwm2m_mqtt_adapter:stop(ChId),
            quit(ChId), ok;
        undefined ->
            ?LOG(error, "Location: ~p not found", [Location]),
            {error, forbidden};
        TrueLocation ->
            ?LOG(error, "Wrong Location: ~p, registered location record: ~p", [Location, TrueLocation]),
            {error, not_found}
    end;
coap_delete(_ChId, _Prefix, _Content) ->
    {error, forbidden}.


coap_observe(ChId, Prefix, Name, Ack) ->
    ?LOG(error, "unknown observe request ChId=~p, Prefix=~p, Name=~p, Ack=~p", [ChId, Prefix, Name, Ack]),
    {error, method_not_allowed}.

coap_unobserve({state, ChId, Prefix, Name}) ->
    ?LOG(error, "ignore unknown unobserve request ChId=~p, Prefix=~p, Name=~p", [ChId, Prefix, Name]),
    ok.

handle_info({dispatch_command, CoapRequest, Ref}, _ObState) ->
    {send_request, CoapRequest, Ref};

handle_info({coap_response, ChId, _Channel, Ref = #{<<"msgType">> := MsgType}, Msg=#coap_message{type = Type, method = Method,
        payload = CoapResponse, options = Options}}, ObState) ->
    ?LOG(info, "Received CoAP response from device: ~p, ref: ~p", [Msg, Ref]),
    MqttPayload = emqx_lwm2m_cmd_handler:coap_response_to_mqtt_payload(Method, CoapResponse, Options, Ref),

    if
        %% If it is a lwm2m notify, not a piggybacked ack, we shall change the
        %%   msgType to "notify"
        (MsgType =:= <<"observe">> orelse MsgType =:= <<"cancel-observe">>) andalso (Type =/= ack) ->
            PayloadNotify = maps:put(<<"msgType">>, <<"notify">>, MqttPayload),
            emqx_lwm2m_mqtt_adapter:send_ul_data(ChId, <<"notify">>, PayloadNotify);
        true ->
            emqx_lwm2m_mqtt_adapter:send_ul_data(ChId, MsgType, MqttPayload)
    end,
    {noreply, ObState};

handle_info(Message, State) ->
    ?LOG(error, "Unknown Message ~p", [Message]),
    {noreply, State}.

coap_ack(Ref, State) ->
    ?LOG(error, "Empty ACK: ~p", [Ref]),
    {ok, State}.

%%%%%%%%%%%%%%%%%%%%%%
%% Internal Functions
%%%%%%%%%%%%%%%%%%%%%%
process_register(ChId, LwM2MQuery, LwM2MPayload) ->
    Epn = maps:get(<<"ep">>, LwM2MQuery, undefined),
    LifeTime = maps:get(<<"lt">>, LwM2MQuery, undefined),
    Ver = maps:get(<<"lwm2m">>, LwM2MQuery, undefined),
    case check_lwm2m_version(Ver) of
        false ->
            ?LOG(error, "Reject REGISTER from ~p due to unsupported version: ~p", [ChId, Ver]),
            quit(ChId), {error, precondition_failed};
        true ->
            case check_epn(Epn) andalso check_lifetime(LifeTime) of
                true ->
                    start_lwm2m_emq_client(ChId, LwM2MQuery, LwM2MPayload);
                false ->
                    ?LOG(error, "Reject REGISTER from ~p due to wrong parameters, epn=~p, lifetime=~p", [ChId, Epn, LifeTime]),
                    quit(ChId),
                    {error, bad_request}
            end
    end.

process_update(ChId, LwM2MQuery, Location, LwM2MPayload) ->
    LocationPath = binary_util:join_path(Location),
    case get(lwm2m_context) of
        #lwm2m_context{location = LocationPath} ->
            RegInfo = append_object_list(LwM2MQuery, LwM2MPayload),
            emqx_lwm2m_mqtt_adapter:update_reg_info(ChId, RegInfo),
            {ok, changed, #coap_content{}};
        undefined ->
            ?LOG(error, "Location: ~p not found", [Location]),
            {error, forbidden};
        TrueLocation ->
            ?LOG(error, "Wrong Location: ~p, registered location record: ~p", [Location, TrueLocation]),
            {error, not_found}
    end.

start_lwm2m_emq_client(ChId, LwM2MQuery = #{<<"ep">> := Epn}, LwM2MPayload) ->
    RegInfo = append_object_list(LwM2MQuery, LwM2MPayload),
    process_flag(trap_exit, true),
    case emqx_lwm2m_mqtt_adapter:start_link(self(), Epn, ChId, RegInfo) of
        {ok, LwClientPid} ->
            LocationPath = assign_location_path(Epn),
            ?LOG(info, "REGISTER Success, LwClientPid: ~p, assgined location: ~p", [LwClientPid, LocationPath]),
            {ok, created, #coap_content{location_path = LocationPath}};
        {error, {already_started, _LwClientPid}} ->
            case get(lwm2m_context) of
                #lwm2m_context{epn = Epn, location = LocationPath} ->
                    ?LOG(info, "RE-REGISTER Success, location: ~p", [LocationPath]),
                    emqx_lwm2m_mqtt_adapter:replace_reg_info(ChId, RegInfo),
                    {ok, created, #coap_content{location_path = location_path_list(LocationPath)}};
                TrueLocation ->
                    ?LOG(error, "Wrong EPN: ~p, registered location record: ~p", [Epn, TrueLocation]),
                    {error, forbidden}
            end;
        {error, Error} ->
            ?LOG(error, "REGISTER Failed, error: ~p", [Error]),
            {error, forbidden}
    end.

location_path_list(Location) ->
    binary:split(binary_util:trim(Location, $/), <<$/>>, [global]).

append_object_list(LwM2MQuery, <<>>) when map_size(LwM2MQuery) == 0 -> #{};
append_object_list(LwM2MQuery, <<>>) -> LwM2MQuery;
append_object_list(LwM2MQuery, LwM2MPayload) when is_binary(LwM2MPayload) ->
    {AlterPath, ObjList} = parse_object_list(LwM2MPayload),
    LwM2MQuery#{
        <<"alternatePath">> => AlterPath,
        <<"objectList">> => ObjList
    }.

parse_options(InputQuery) ->
    parse_options(InputQuery, maps:new()).

parse_options([], Query) -> {ok, Query};
parse_options([<<"ep=", Epn/binary>>|T], Query) ->
    parse_options(T, maps:put(<<"ep">>, Epn, Query));
parse_options([<<"lt=", Lt/binary>>|T], Query) ->
    parse_options(T, maps:put(<<"lt">>, binary_to_integer(Lt), Query));
parse_options([<<"lwm2m=", Ver/binary>>|T], Query) ->
    parse_options(T, maps:put(<<"lwm2m">>, Ver, Query));
parse_options([<<"b=", Binding/binary>>|T], Query) ->
    parse_options(T, maps:put(<<"b">>, Binding, Query));
parse_options([CustomOption|T], Query) ->
    case binary:split(CustomOption, <<"=">>) of
        [OptKey, OptValue] when OptKey =/= <<>> ->
            ?LOG(debug, "non-standard option: ~p", [CustomOption]),
            parse_options(T, maps:put(OptKey, OptValue, Query));
        _BadOpt ->
            ?LOG(error, "bad option: ~p", [CustomOption]),
            {error, {bad_opt, CustomOption}}
    end.

parse_object_list(<<>>) -> {<<"/">>, <<>>};
parse_object_list(ObjLinks) when is_binary(ObjLinks) ->
    parse_object_list(binary:split(ObjLinks, <<",">>, [global]));

parse_object_list(FullObjLinkList) when is_list(FullObjLinkList) ->
    case drop_attr(FullObjLinkList) of
        {<<"/">>, _} = RootPrefixedLinks ->
            RootPrefixedLinks;
        {AlterPath, ObjLinkList} ->
            LenAlterPath = byte_size(AlterPath),
            WithOutPrefix =
                lists:map(
                    fun
                        (<<Prefix:LenAlterPath/binary, Link/binary>>) when Prefix =:= AlterPath ->
                            trim(Link);
                        (Link) -> Link
                    end, ObjLinkList),
            {AlterPath, WithOutPrefix}
    end.

drop_attr(LinkList) ->
    lists:foldr(
        fun(Link, {AlternatePath, LinkAcc}) ->
            {MainLink, LinkAttrs} = parse_link(Link),
            case is_alternate_path(LinkAttrs) of
                false -> {AlternatePath, [MainLink | LinkAcc]};
                true  -> {MainLink, LinkAcc}
            end
        end, {<<"/">>, []}, LinkList).

is_alternate_path(#{<<"rt">> := ?OMA_ALTER_PATH_RT}) -> true;
is_alternate_path(_) -> false.

parse_link(Link) ->
    [MainLink | Attrs] = binary:split(trim(Link), <<";">>, [global]),
    {delink(trim(MainLink)), parse_link_attrs(Attrs)}.

parse_link_attrs(LinkAttrs) when is_list(LinkAttrs) ->
    lists:foldl(
        fun(Attr, Acc) ->
            case binary:split(trim(Attr), <<"=">>) of
                [AttrKey, AttrValue] when AttrKey =/= <<>> ->
                    maps:put(AttrKey, AttrValue, Acc);
                _BadAttr -> throw({bad_attr, _BadAttr})
            end
        end, maps:new(), LinkAttrs).

trim(Str)-> binary_util:trim(Str, $ ).
delink(Str) ->
    Ltrim = binary_util:ltrim(Str, $<),
    binary_util:rtrim(Ltrim, $>).

% don't check the lwm2m version for now
%check_lwm2m_version(_) -> true;

check_lwm2m_version(<<"1.0">>) -> true;
check_lwm2m_version(<<"1">>)   -> true;
check_lwm2m_version(_)         -> false.

check_epn(undefined) -> false;
check_epn(_)         -> true.

check_lifetime(undefined) -> false;
check_lifetime(LifeTime) when LifeTime >= 300, LifeTime =< 86400 -> true;
check_lifetime(_)         -> false.


quit(ChId) ->
    self() !{coap_error, ChId, undefined, [], shutdown}.

assign_location_path(Epn) ->
    %Location = list_to_binary(io_lib:format("~.16B", [rand:uniform(65535)])),
    %LocationPath = <<"/rd/", Location/binary>>,
    Location = [<<"rd">>, Epn],
    put(lwm2m_context, #lwm2m_context{epn = Epn, location = binary_util:join_path(Location)}),
    Location.

% end of file
