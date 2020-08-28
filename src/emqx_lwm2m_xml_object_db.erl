%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_lwm2m_xml_object_db).

-include("emqx_lwm2m.hrl").
-include_lib("xmerl/include/xmerl.hrl").

% This module is for future use. Disabled now.

%% API
-export([ start_link/0
        , stop/0
        , find_name/1
        , find_objectid/1
        ]).

%% gen_server.
-export([ init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        ]).

-define(LOG(Level, Format, Args),
    logger:Level("LWM2M-OBJ-DB: " ++ Format, Args)).

-define(LWM2M_OBJECT_DEF_TAB, lwm2m_object_def_tab).
-define(LWM2M_OBJECT_NAME_TO_ID_TAB, lwm2m_object_name_to_id_tab).

-record(state, {}).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

find_objectid(ObjectId) ->
    ObjectIdInt =   case is_list(ObjectId) of
                        true -> list_to_integer(ObjectId);
                        false -> ObjectId
                    end,
    case ets:lookup(?LWM2M_OBJECT_DEF_TAB, ObjectIdInt) of
        [] -> error(no_xml_definition);
        [{ObjectId, Xml}] -> Xml
    end.

find_name(Name) ->
    NameBinary = case is_list(Name) of
                     true -> list_to_binary(Name);
                     false -> Name
                 end,
    case ets:lookup(?LWM2M_OBJECT_NAME_TO_ID_TAB, NameBinary) of
        [] ->
            undefined;
        [{NameBinary, ObjectId}] ->
            case ets:lookup(?LWM2M_OBJECT_DEF_TAB, ObjectId) of
                [] -> undefined;
                [{ObjectId, Xml}] -> Xml
            end
    end.

stop() ->
    gen_server:stop(?MODULE).


%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([]) ->
    ets:new(?LWM2M_OBJECT_DEF_TAB, [set, named_table, protected]),
    ets:new(?LWM2M_OBJECT_NAME_TO_ID_TAB, [set, named_table, protected]),
    PluginsEtcDir = emqx:get_env(plugins_etc_dir),
    DefBaseDir = re:replace(PluginsEtcDir, "plugins", "lwm2m_xml", [{return, list}]),
    BaseDir = application:get_env(emqx_lwm2m, xml_dir, DefBaseDir),
    load(BaseDir),
    {ok, #state{}}.

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ets:delete(?LWM2M_OBJECT_DEF_TAB),
    ets:delete(?LWM2M_OBJECT_NAME_TO_ID_TAB),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------
load(BaseDir) ->
    Wild = case lists:last(BaseDir) == $/ of
               true  -> BaseDir++"*.xml";
               false -> BaseDir++"/*.xml"
           end,
    AllXmlFiles = filelib:wildcard(Wild),
    load_loop(AllXmlFiles).

load_loop([]) ->
    ok;
load_loop([FileName|T]) ->
    ObjectXml = load_xml(FileName),
    [#xmlText{value=ObjectIdString}] = xmerl_xpath:string("ObjectID/text()", ObjectXml),
    [#xmlText{value=Name}] = xmerl_xpath:string("Name/text()", ObjectXml),
    ObjectId = list_to_integer(ObjectIdString),
    NameBinary = list_to_binary(Name),
    ?LOG(debug, "load_loop FileName=~p, ObjectId=~p, Name=~p", [FileName, ObjectId, NameBinary]),
    ets:insert(?LWM2M_OBJECT_DEF_TAB, {ObjectId, ObjectXml}),
    ets:insert(?LWM2M_OBJECT_NAME_TO_ID_TAB, {NameBinary, ObjectId}),
    load_loop(T).


load_xml(FileName) ->
    {Xml, _Rest} = xmerl_scan:file(FileName),
    [ObjectXml] = xmerl_xpath:string("/LWM2M/Object", Xml),
    ObjectXml.

