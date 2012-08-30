-module(esp_cache_SUITE).

-include("../../erlangsp/include/license_and_copyright.hrl").
-include_lib("common_test/include/ct.hrl").
-include("../../coop/include/coop_dag.hrl").
-include("../../examples/esp_cache/include/esp_cache.hrl").

%% Suite functions
-export([all/0, init_per_suite/1, end_per_suite/1]).

%% Test Coop Node functionality individually
-export([datum_value/1,
         worker_value/1, worker_mfa/1, worker_replace/1,
         value_request_lookup/1
        ]).

%% Spawned functions must be exported
-export([check_worker/2, compute_value/1]).

all() -> [
          datum_value,
          worker_value, worker_mfa, worker_replace,
          value_request_lookup
         ].

init_per_suite(Config) -> Config.
end_per_suite(_Config) -> ok.


%%----------------------------------------------------------------------
%% Final stage Datum Coop Node tests
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
    23 = check_datum(foo),
    {exited, _Pid} = check_datum(foo).

check_datum(Ref) ->
    receive
        {Ref, Value} -> Value;
        {'DOWN', _MRef, process, Pid, normal} -> {exited, Pid}
    after 1000 -> timeout
    end.

%%----------------------------------------------------------------------
%% Mid-tier worker Coop Node tests
%%----------------------------------------------------------------------
worker_test_age(Value_Expr, Answer) ->

    %% Create a worker node...
    Self = self(),
    meck:new(coop, [passthrough]),
    meck:expect(coop, get_kill_switch, fun(_Coop_Head) -> Self end),
    Fake_Coop_Head = {coop_head, Self, Self},
    Coop_Node = esp_cache:new_worker_node(Fake_Coop_Head),
    ?CTL_MSG({link, _Pids1}) = receive A -> A after 1000 -> timeout end,

    %% Create a new cached datum node from the value expression...
    R1 = make_ref(),
    Rcvr = proc_lib:spawn_link(?MODULE, check_worker, [R1, []]),
    coop:relay_data(Coop_Node, {add, {age, Value_Expr, {R1, Rcvr}}}),
    Results = check_worker([]),
    2 = length(Results),
    [?CTL_MSG({link, _Pids2})] = [I || I <- Results, element(1,element(3, I)) =:= link],
    [?DATA_MSG({new, age, {coop_node, _, _}})]
        = [I || I <- Results, element(1, element(3, I)) =:= new],
    timer:sleep(50),
    Rcvr ! {results, Self},
    [[Answer]] = check_worker([]),
    meck:unload(coop).

check_worker(Acc) ->
    receive Any -> check_worker([Any | Acc])
    after 100   -> lists:reverse(Acc)
    end.
check_worker(Ref, Acc) ->
    receive
        {Ref, Value} -> check_worker(Ref, [Value | Acc]);
        {results, From} -> From ! lists:reverse(Acc)
    after 5000 -> no_msg
    end.

compute_value(X) -> 3*X.

worker_value(_Config) -> worker_test_age({?VALUE, 15}, 15).
worker_mfa(_Config)   -> worker_test_age({?MFA, {?MODULE, compute_value, 7}}, 21).
    
worker_replace(_Config) ->

    %% Create a worker node...
    Self = self(),
    meck:new(coop, [passthrough]),
    meck:expect(coop, get_kill_switch, fun(_Coop_Head) -> Self end),
    Fake_Coop_Head = {coop_head, Self, Self},
    Coop_Node = esp_cache:new_worker_node(Fake_Coop_Head),
    ?CTL_MSG({link, _Pids1}) = receive A -> A after 1000 -> timeout end,

    %% Create a new cached datum node from a simple value...
    R1 = make_ref(),
    Rcvr = proc_lib:spawn_link(?MODULE, check_worker, [R1, []]),
    coop:relay_data(Coop_Node, {add, {age, {?VALUE, 37}, {R1, Rcvr}}}),
    Results = check_worker([]),
    2 = length(Results),
    [?CTL_MSG({link, _Pids2})] = [I || I <- Results, element(1,element(3, I)) =:= link],
    [?DATA_MSG({new, age, {coop_node, _, _} = New_Datum_Cache_Node})]
        = [I || I <- Results, element(1, element(3, I)) =:= new],
    timer:sleep(50),
    Rcvr ! {results, Self},
    [[37]] = check_worker([]),

    %% Replace the cached datum value...
    R2 = make_ref(),
    Rcvr2 = proc_lib:spawn_link(?MODULE, check_worker, [R2, []]),
    coop:relay_data(Coop_Node, {replace, {age, {?MFA, {?MODULE, compute_value, 11}}, {R2, Rcvr2}},
                                New_Datum_Cache_Node}),
    timer:sleep(50),
    Rcvr2 ! {results, Self},
    [[33]] = check_worker([]),
    meck:unload(coop).

%%----------------------------------------------------------------------
%% First stage Directory Coop Node tests
%%----------------------------------------------------------------------
value_request_start(Key, Exp_Value) ->

    %% Create a directory node...
    Self = self(),
    meck:new(coop, [passthrough]),
    meck:expect(coop, get_kill_switch, fun(_Coop_Head) -> Self end),
    Fake_Coop_Head = {coop_head, Self, Self},
    Directory_Node = esp_cache:new_directory_node(Fake_Coop_Head),
    ?CTL_MSG({link, _Pids1}) = receive A -> A after 1000 -> timeout end,

    %% Check that value is missing...
    R1 = make_ref(),
    coop:relay_data(Directory_Node, {num_keys, {R1, Self}}),
    R2 = make_ref(),
    coop:relay_data(Directory_Node, {lookup, {Key, {R2, Self}}}),
    R3 = make_ref(),
    coop:relay_data(Directory_Node, {num_keys, {R3, Self}}),
    timer:sleep(50),
    [{R1, 0}, {R2, undefined}, {R3, 0}] = check_worker([]),

    %% Create a datum Coop_Node...
    Value_Node = esp_cache:new_datum_node(Self, Exp_Value),
    ?CTL_MSG({link, _Pids2}) = receive B -> B after 1000 -> timeout end,
    coop:relay_data(Directory_Node, {new, Key, Value_Node}),
    R4 = make_ref(),
    coop:relay_data(Directory_Node, {num_keys, {R4, Self}}),
    timer:sleep(50),
    [{R4, 1}] = check_worker([]),
    true = coop:is_live(Value_Node),

    %% Check that value is present.
    R5 = make_ref(),
    coop:relay_data(Directory_Node, {lookup, {Key, {R5, Self}}}),
    R6 = make_ref(),
    coop:relay_data(Directory_Node, {lookup, {Key, {R6, Self}}}),
    timer:sleep(50),
    [{R5, Exp_Value}, {R6, Exp_Value}] = check_worker([]),
    R7 = make_ref(),
    coop:relay_data(Directory_Node, {num_keys, {R7, Self}}),
    timer:sleep(50),
    [{R7, 1}] = check_worker([]),
    true = coop:is_live(Value_Node),

    %% Delete the value and check the count.
    R8 = make_ref(),
    coop:relay_data(Directory_Node, {remove, {Key, {R8, Self}}}),
    timer:sleep(50),
    R9 = make_ref(),
    coop:relay_data(Directory_Node, {num_keys, {R9, Self}}),
    timer:sleep(50),
    [{R8, Exp_Value}, {R9, 0}] = check_worker([]),
    false = coop:is_live(Value_Node),

    %% Delete again to make sure it doesn't fail...
    RA = make_ref(),
    coop:relay_data(Directory_Node, {remove, {Key, {RA, Self}}}),
    RB = make_ref(),
    coop:relay_data(Directory_Node, {num_keys, {RB, Self}}),
    timer:sleep(50),
    [{RA, undefined}, {RB, 0}] = check_worker([]),
    false = coop:is_live(Value_Node),
    true = coop:is_live(Directory_Node),

    meck:unload(coop).
    
value_request_lookup(_Config) ->
    value_request_start(foo, 29).
