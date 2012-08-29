-module(esp_cache_SUITE).

-include("../../erlangsp/include/license_and_copyright.hrl").
-include_lib("common_test/include/ct.hrl").
-include("../../coop/include/coop_dag.hrl").
-include("../../examples/esp_cache/include/esp_cache.hrl").

%% Suite functions
-export([all/0, init_per_suite/1, end_per_suite/1]).

%% Test Coop Node functionality individually
-export([datum_value/1, worker/1]).

all() -> [datum_value, worker].

init_per_suite(Config) -> Config.
end_per_suite(_Config) -> ok.


%%----------------------------------------------------------------------
%% Coop Node tests
%%----------------------------------------------------------------------
datum_value(_Config) ->

    %% Get original value...
    Kill_Switch = coop_kill_link_rcv:make_kill_switch(),
    {coop_node, _Node_Ctl_Pid, Node_Task_Pid} = Coop_Node
        = esp_cache:new_datum_node(Kill_Switch, 17),
    R1 = make_ref(),
    coop:relay_data(Coop_Node, {get_value, {R1, self()}}),
    17 = check_datum(R1),
    R2 = make_ref(),
    coop:relay_data(Coop_Node, {get_value, {R2, self()}}),
    17 = check_datum(R2),
    
    %% Replace value and get new value...
    R3 = make_ref(),
    coop:relay_data(Coop_Node, {replace, 23, {R3, self()}}),
    23 = check_datum(R3),
    R4 = make_ref(),
    coop:relay_data(Coop_Node, {get_value, {R4, self()}}),
    23 = check_datum(R4),
    
    %% Check for expiration...
    erlang:monitor(process, Node_Task_Pid),
    coop:relay_data(Coop_Node, {expire, {foo, self()}}),
    {exited, _Pid} = check_datum(foo).

check_datum(Ref) ->
    receive
        {Ref, Value} -> Value;
        {'DOWN', _MRef, process, Pid, normal} -> {exited, Pid}
    after 1000 -> timeout
    end.

worker(_Config) ->

    %% Create a worker node...
    Self = self(),
    meck:new(coop, [passthrough]),
    meck:expect(coop, get_kill_switch, fun(_Coop_Head) -> Self end),
    _Kill_Switch = coop_kill_link_rcv:make_kill_switch(),
    Fake_Coop_Head = {coop_head, Self, Self},
    {coop_node, _Node_Ctl_Pid, _Node_Task_Pid} = Coop_Node
        = esp_cache:new_worker_node(Fake_Coop_Head),

    %% Send it a value...
    R1 = make_ref(),
    coop:relay_data(Coop_Node, {add, {age, {?VALUE, 15}}, {R1, Self}}),
    check_worker(R1),

    meck:unload(coop).

check_worker(_Ref) ->
    ok.
