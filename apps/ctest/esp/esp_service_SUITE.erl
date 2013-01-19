-module(esp_service_SUITE).

-include("../../erlangsp/include/license_and_copyright.hrl").
-include_lib("common_test/include/ct.hrl").
-include("../../coop/include/coop.hrl").
-include("../../coop/include/coop_dag.hrl").

%% Suite functions
-export([all/0, init_per_suite/1, end_per_suite/1]).

%% Fleshed out behaviour methods
-export([new/1, start/2, stop/1]).
-export([init_multiply/1, multiply/2]).

%% Test message flow control for a service
-export([start_and_stop/1, suspend_and_resume/1]).

%% Test overload flag
-export([check_overload/1]).

all() -> [start_and_stop, suspend_and_resume, check_overload].

init_per_suite(Config) -> Config.
end_per_suite(_Config) -> ok.

-define(ES, esp_service).


%%----------------------------------------------------------------------
%% Fleshed out behaviour methods
%%----------------------------------------------------------------------
new({Multiply_Amt, Checker})
  when is_number(Multiply_Amt), is_pid(Checker) ->
    Init = ?COOP_INIT_FN(init_multiply, {Multiply_Amt}),
    Worker = coop:make_dag_node(Init, ?COOP_TASK_FN(multiply), []),
    Coop = coop:new_pipeline([Worker], Checker),
    ?ES:make_service(Coop).

start(Service, Options) -> ?ES:start(Service, Options).
stop(Service) -> ?ES:stop(Service).

                
%%----------------------------------------------------------------------
%% Coop functions
%%----------------------------------------------------------------------
init_multiply({Amt} = State) when is_number(Amt) -> State.

%% Forward commands to downstream...
multiply(State, Cmd) when is_atom(Cmd) -> {State, Cmd};
%% Multiply numbers when a value is received.
multiply({Amt} = State, Value) when is_number(Value) -> {State, Value*Amt}.

                
%%----------------------------------------------------------------------
%% Test functions
%%----------------------------------------------------------------------
start_multiply() ->
    Multiply_Service = new({3, self()}),
    new = ?ES:status(Multiply_Service),
    {error, not_started} = ?ES:act_on(Multiply_Service, 5),
    Started_Service = ?ES:start(Multiply_Service),
    active = ?ES:status(Started_Service),
    ok = ?ES:act_on(Started_Service, 5),
    15 = receive Any1 -> Any1 after 1000 -> timeout end,
    active = ?ES:status(Started_Service),
    Started_Service.
    
start_and_stop(_Config) ->
    Started_Service = start_multiply(),
    Stopped_Service = ?ES:stop(Started_Service),
    stopped = ?ES:status(Stopped_Service),
    {error, stopped} = ?ES:act_on(Stopped_Service, 4),
    Restarted_Service = ?ES:start(Stopped_Service),
    active = ?ES:status(Restarted_Service),
    ok = ?ES:act_on(Restarted_Service, 4),
    12 = receive Any2 -> Any2 after 1000 -> timeout end,
    ok.

suspend_and_resume(_Config) ->
    Started_Service = start_multiply(),
    Suspended_Service = ?ES:suspend(Started_Service),
    suspended = ?ES:status(Suspended_Service),
    ok = ?ES:act_on(Suspended_Service, 5),
    ok = ?ES:act_on(Suspended_Service, 6),
    timeout = receive Any1 -> Any1 after 100 -> timeout end,
    Resumed_Service = ?ES:resume(Suspended_Service),
    active = ?ES:status(Resumed_Service),
    15 = receive Any2 -> Any2 after 100 -> timeout end,
    18 = receive Any3 -> Any3 after 100 -> timeout end,
    timeout = receive Any4 -> Any4 after 100 -> timeout end,
    ok.

check_overload(_Config) ->
    Started_Service = start_multiply(),
    false = ?ES:is_overloaded(Started_Service),
    Overloaded_Service = ?ES:set_overloaded(Started_Service, true),
    true = ?ES:is_overloaded(Overloaded_Service),
    Underloaded_Service = ?ES:set_overloaded(Overloaded_Service, false),
    false = ?ES:is_overloaded(Underloaded_Service),
    ok.
