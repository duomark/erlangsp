%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%    Service behaviour is the basis for all Erlang/SP Services.
%%% @since v0.0.2
%%% @end
%%%------------------------------------------------------------------------------
-module(esp_service).

-include("../../license_and_copyright.hrl").
-author('Jay Nelson <jay@duomark.com>').

%% Public API
-export([
         make_service/1,
         start/1, stop/1, status/1, act_on/2,
         suspend/1, suspend_for/2, resume/1, resume_after/2,
         is_overloaded/1, set_overloaded/2
        ]).

-include_lib("coop/include/coop.hrl").
-include("esp_service.hrl").

-callback new(Args::tuple()) -> Service::esp_service().
-callback start(Service::esp_service(), Options::proplists:proplist()) ->
    esp_service() | {error, already_started | suspended}.
-callback stop(Service::esp_service()) -> esp_service() | {error, already_stopped}.

%%% @doc Construct a service instance from a coop.
-spec make_service(coop()) -> esp_service().
make_service(Coop) ->
    #esp_svc{coop=Coop}.

%%% @doc Services do not operate until they are started.
-spec start(esp_service()) -> esp_service() | {error, already_started | suspended}.
start(#esp_svc{status=Status} = Service) ->
    case Status of
        new       -> Service#esp_svc{status=active};
        active    -> {error, already_started};
        suspended -> {error, suspended};
        stopped        -> Service#esp_svc{status=active};
        stop_suspended -> Service#esp_svc{status=suspended}
    end.

%%% @doc Stopped services do not act on any messages.
-spec stop(esp_service()) -> esp_service() | {error, already_stopped}.
stop(#esp_svc{status=Status} = Service) ->
    case Status of
        new       -> Service#esp_svc{status=stopped};
        active    -> Service#esp_svc{status=stopped};
        suspended -> Service#esp_svc{status=stop_suspended};
        stopped        -> {error, already_stopped};
        stop_suspended -> {error, already_stopped}
    end.

%%% @doc Get the current status of a service.
-spec status(esp_service()) -> svc_state().
status(#esp_svc{status=Status}) -> Status.

%%% @doc Services act_on data by passing it to the implementing coop.
-spec act_on(esp_service(), coop()) -> ok | {error, not_started | stopped}.
act_on(#esp_svc{status=Status, coop=Coop}, Data) ->
    case Status of
        new       -> {error, not_started};
        active    -> coop:relay_data(Coop, Data);
        suspended -> coop:relay_data(Coop, Data);
        stopped        -> {error, stopped};
        stop_suspended -> {error, stopped}
    end.
     

%%% @doc Suspend allows messages to queue, but only acts on system messages
-spec suspend(esp_service()) -> esp_service() | {error, already_suspended | stopped}.
suspend(#esp_svc{status=Status, coop=#coop{instances=#coop_instance{head=Coop_Head}}} = Service) ->
    case Status of
        new       -> coop_head:suspend_root(Coop_Head), Service#esp_svc{status=suspended};
        active    -> coop_head:suspend_root(Coop_Head), Service#esp_svc{status=suspended};
        suspended      -> {error, already_suspended};
        stopped        -> {error, stopped};
        stop_suspended -> {error, stopped}
    end;
suspend(#esp_svc{status=Status, coop=#coop{instances=Instances}} = Service) ->
    case Status of
        new       -> fold_suspend(Instances), Service#esp_svc{status=suspended};
        active    -> fold_suspend(Instances), Service#esp_svc{status=suspended};
        suspended      -> {error, already_suspended};
        stopped        -> {error, stopped};
        stop_suspended -> {error, stopped}
    end.

fold_suspend(Instances) ->
    ets:foldl(fun(#coop_instance{head=Coop_Head}, Count) ->
                      coop_head:suspend_root(Coop_Head), Count+1 end,
              0, Instances).

%%% @doc Suspend_for resumes after the time of suspension ends.
-spec suspend_for(esp_service(), pos_integer()) -> esp_service() | {error, already_suspended | stopped}.
suspend_for(#esp_svc{status=Status, coop=#coop{instances=#coop_instance{head=Coop_Head}}} = Service, Millis) ->
    case Status of
        new       -> suspend_head_for(Coop_Head, Millis), Service#esp_svc{status=suspended};
        active    -> suspend_head_for(Coop_Head, Millis), Service#esp_svc{status=suspended};
        suspended      -> {error, already_suspended};
        stopped        -> {error, stopped};
        stop_suspended -> {error, stopped}
    end;
suspend_for(#esp_svc{status=Status, coop=#coop{instances=Instances}} = Service, Millis) ->
    case Status of
        new       -> fold_suspend_for(Instances, Millis), Service#esp_svc{status=suspended};
        active    -> fold_suspend_for(Instances, Millis), Service#esp_svc{status=suspended};
        suspended      -> {error, already_suspended};
        stopped        -> {error, stopped};
        stop_suspended -> {error, stopped}
    end.

suspend_head_for(Coop_Head, Millis) ->
    coop_head:suspend_root(Coop_Head),
    coop_head:resume_root_after(Coop_Head, Millis).

fold_suspend_for(Instances, Millis) ->
    ets:foldl(fun(#coop_instance{head=Coop_Head}, Count) ->
                      suspend_head_for(Coop_Head, Millis), Count+1 end,
              0, Instances).
    

%%% @doc Resume starts processing on queued messages after suspend was called.
-spec resume(esp_service()) -> esp_service | {error, not_suspended | stopped}.
resume(#esp_svc{status=Status, coop=#coop{instances=#coop_instance{head=Coop_Head}}} = Service) ->
    case Status of
        new       -> {error, not_suspended};
        active    -> {error, not_suspended};
        suspended      -> coop_head:resume_root(Coop_Head), Service#esp_svc{status=active};
        stopped        -> {error, stopped};
        stop_suspended -> {error, stopped}
    end;
resume(#esp_svc{status=Status, coop=#coop{instances=Instances}} = Service) ->
    case Status of
        new       -> {error, not_suspended};
        active    -> {error, not_suspended};
        suspended      -> fold_resume(Instances), Service#esp_svc{status=active};
        stopped        -> {error, stopped};
        stop_suspended -> {error, stopped}
    end.

fold_resume(Instances) ->
    ets:foldl(fun(#coop_instance{head=Coop_Head}, Count) ->
                      coop_head:resume_root(Coop_Head), Count+1 end,
              0, Instances).

%%% @doc Resume_after invokes resume after a time delay.
-spec resume_after(esp_service(), pos_integer()) -> esp_service | {error, not_suspended | stopped}.
resume_after(#esp_svc{status=Status, coop=#coop{instances=#coop_instance{head=Coop_Head}}} = Service, Millis) ->
    case Status of
        new       -> {error, not_suspended};
        active    -> {error, not_suspended};
        suspended      -> coop_head:resume_root_after(Coop_Head, Millis), Service#esp_svc{status=active};
        stopped        -> {error, stopped};
        stop_suspended -> {error, stopped}
    end;
resume_after(#esp_svc{status=Status, coop=#coop{instances=Instances}} = Service, Millis) ->
    case Status of
        new       -> {error, not_suspended};
        active    -> {error, not_suspended};
        %% Not yet, should be when resume actually occurs...
        suspended      -> fold_resume_after(Instances, Millis), Service#esp_svc{status=active};
        stopped        -> {error, stopped};
        stop_suspended -> {error, stopped}
    end.

fold_resume_after(Instances, Millis) ->
    ets:foldl(fun(#coop_instance{head=Coop_Head}, Count) ->
                      coop_head:resume_root_after(Coop_Head, Millis), Count+1 end,
              0, Instances).

%%% @doc Is_overloaded reflects the internal boolean overload flag state
-spec is_overloaded(esp_service()) -> boolean().
is_overloaded(#esp_svc{overloaded=Overloaded}) -> Overloaded.

%%% @doc Set_overloaded potentially changes the boolean overload flag state
-spec set_overloaded(esp_service(), boolean()) -> esp_service().
set_overloaded(#esp_svc{} = Service, Is_Overloaded) ->
    Service#esp_svc{overloaded=Is_Overloaded}.
