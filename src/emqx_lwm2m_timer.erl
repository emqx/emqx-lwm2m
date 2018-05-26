%%%===================================================================
%%% Copyright (c) 2013-2018 EMQ Inc. All rights reserved.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%===================================================================

-module(emqx_lwm2m_timer).

-include("emqx_lwm2m.hrl").

-export([cancel_timer/1, start_timer/2, kick_timer/1, is_timeout/1]).

-record(timer_state, {kickme, tref, message}).

-define(LOG(Level, Format, Args),
        emqx_logger:Level("LWM2M-TIMER: " ++ Format, Args)).

cancel_timer(#timer_state{tref = TRef}) when is_reference(TRef) ->
    catch erlang:cancel_timer(TRef),
    ok;
cancel_timer(_) ->
    ok.

kick_timer(State=#timer_state{kickme = false}) ->
    State#timer_state{kickme = true};
kick_timer(State=#timer_state{kickme = true}) ->
    State.

start_timer(Sec, Msg) ->
    ?LOG(debug, "emqx_lwm2m_timer:start_timer ~p", [Sec]),
    TRef = erlang:send_after(timer:seconds(Sec), self(), Msg),
    #timer_state{kickme = false, tref = TRef, message = Msg}.


is_timeout(#timer_state{kickme = Bool}) ->
    not Bool.

