-module(esp_cache_SUITE).

-include("../../src/license_and_copyright.hrl").
-include_lib("common_test/include/ct.hrl").

%% Suite functions
-export([all/0, init_per_suite/1, end_per_suite/1]).

%% Test Coop Node functionality individually
-export([
         datum_value/1,
         worker_value/1, worker_mfa/1, worker_replace/1,
         value_request_lookup/1, value_request_add_replace/1
        ]).

%% Test full coop
-export([cache_coop/1]).

%% Spawned functions must be exported
-export([check_worker/2, compute_value/1]).

-include_lib("coop/include/coop.hrl").
-include_lib("coop/include/coop_dag.hrl").
-include_lib("esp_cache/include/esp_cache.hrl").

all() -> [
          datum_value,
          worker_value, worker_mfa, worker_replace,
          value_request_lookup, value_request_add_replace,
          cache_coop
         ].

init_per_suite(Config) -> Config.
end_per_suite(_Config) -> ok.


%%----------------------------------------------------------------------
%% Final stage Datum Coop Node tests
%%----------------------------------------------------------------------
make_fake_head() ->
    Head_Kill_Switch = coop_kill_link_rcv:make_kill_switch(),
    coop_head:new(Head_Kill_Switch, none).

datum_value(_Config) ->

    %% Get original value...
    Kill_Switch = coop_kill_link_rcv:make_kill_switch(),
    #coop_node{task_pid=Node_Task_Pid} = Coop_Node
        = esp_cache:new_datum_node(make_fake_head(), Kill_Switch, 17),
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
    meck:new(coop_head, [passthrough]),
    meck:expect(coop_head, get_kill_switch, fun(_Coop_Head) -> Self end),
    Fake_Coop_Head = #coop_head{ctl_pid=Self, data_pid=Self},
    Coop_Node = esp_cache:new_worker_node(Fake_Coop_Head),
    ?CTL_MSG({link, _Pids1}) = receive A -> A after 1000 -> timeout end,

    %% Create a new cached datum node from the value expression...
    R1 = make_ref(),
    Rcvr = proc_lib:spawn_link(?MODULE, check_worker, [R1, []]),
    coop:relay_data(Coop_Node, {add, {age, Value_Expr, {R1, Rcvr}}}),
    Results = check_worker([]),
    2 = length(Results),
    [?CTL_MSG({link, _Pids2})] = [I || I <- Results, element(1,element(3, I)) =:= link],
    [?DATA_MSG({new, age, #coop_node{}})]
        = [I || I <- Results, element(1, element(3, I)) =:= new],
    timer:sleep(50),
    Rcvr ! {results, Self},
    [[Answer]] = check_worker([]),
    meck:unload(coop_head).

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
    meck:new(coop_head, [passthrough]),
    meck:expect(coop_head, get_kill_switch, fun(_Coop_Head) -> Self end),
    Fake_Coop_Head = #coop_head{ctl_pid=Self, data_pid=Self},
    Coop_Node = esp_cache:new_worker_node(Fake_Coop_Head),
    ?CTL_MSG({link, _Pids1}) = receive A -> A after 1000 -> timeout end,

    %% Create a new cached datum node from a simple value...
    R1 = make_ref(),
    Rcvr = proc_lib:spawn_link(?MODULE, check_worker, [R1, []]),
    coop:relay_data(Coop_Node, {add, {age, {?VALUE, 37}, {R1, Rcvr}}}),
    Results = check_worker([]),
    2 = length(Results),
    [?CTL_MSG({link, _Pids2})] = [I || I <- Results, element(1,element(3, I)) =:= link],
    [?DATA_MSG({new, age, #coop_node{} = New_Datum_Cache_Node})]
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
    meck:unload(coop_head).

%%----------------------------------------------------------------------
%% First stage Directory Coop Node tests
%%----------------------------------------------------------------------
value_request_lookup(_Config) ->
    Key = foo,
    Exp_Value = 29,

    %% Create a directory node...
    Self = self(),
    meck:new(coop_head, [passthrough]),
    meck:expect(coop_head, get_kill_switch, fun(_Coop_Head) -> Self end),
    Fake_Coop_Head = #coop_head{ctl_pid=Self, data_pid=Self},
    Directory_Node = esp_cache:new_directory_node(Fake_Coop_Head),
    ?CTL_MSG({link, _Pids1}) = receive A -> A after 1000 -> timeout end,
    check_directory_empty(Directory_Node, Key),

    %% Create a datum Coop_Node...
    Value_Node = insert_value(Directory_Node, Key, Exp_Value),

    %% Delete the value and check the count.
    R1 = make_ref(),
    coop:relay_data(Directory_Node, {remove, {Key, {R1, Self}}}),
    timer:sleep(50),
    R2 = make_ref(),
    coop:relay_data(Directory_Node, {num_keys, {R2, Self}}),
    timer:sleep(50),
    [{R1, Exp_Value}, {R2, 0}] = check_worker([]),
    false = coop:is_live(Value_Node),

    %% Delete again to make sure it doesn't fail...
    R3 = make_ref(),
    coop:relay_data(Directory_Node, {remove, {Key, {R3, Self}}}),
    R4 = make_ref(),
    coop:relay_data(Directory_Node, {num_keys, {R4, Self}}),
    timer:sleep(50),
    [{R3, undefined}, {R4, 0}] = check_worker([]),
    false = coop:is_live(Value_Node),
    true = coop:is_live(Directory_Node),

    meck:unload(coop_head).

check_directory_empty(Directory_Node, Key) ->
    Self = self(),
    R1 = make_ref(),
    coop:relay_data(Directory_Node, {num_keys, {R1, Self}}),
    R2 = make_ref(),
    coop:relay_data(Directory_Node, {lookup, {Key, {R2, Self}}}),
    R3 = make_ref(),
    coop:relay_data(Directory_Node, {num_keys, {R3, Self}}),
    timer:sleep(50),
    [{R1, 0}, {R2, undefined}, {R3, 0}] = check_worker([]),
    ok.
    
insert_value(Directory_Node, Key, Exp_Value) ->
    Self = self(),

    %% Create a datum Coop_Node...
    Value_Node = esp_cache:new_datum_node(make_fake_head(), Self, Exp_Value),
    ?CTL_MSG({link, _Pids2}) = receive B -> B after 1000 -> timeout end,
    coop:relay_data(Directory_Node, {new, Key, Value_Node}),
    R1 = make_ref(),
    coop:relay_data(Directory_Node, {num_keys, {R1, Self}}),
    timer:sleep(50),
    [{R1, 1}] = check_worker([]),
    true = coop:is_live(Value_Node),

    %% Check that value is present.
    R2 = make_ref(),
    coop:relay_data(Directory_Node, {lookup, {Key, {R2, Self}}}),
    R3 = make_ref(),
    coop:relay_data(Directory_Node, {lookup, {Key, {R3, Self}}}),
    timer:sleep(50),
    [{R2, Exp_Value}, {R3, Exp_Value}] = check_worker([]),
    R4 = make_ref(),
    coop:relay_data(Directory_Node, {num_keys, {R4, Self}}),
    timer:sleep(50),
    [{R4, 1}] = check_worker([]),
    true = coop:is_live(Value_Node),
    
    Value_Node.

value_request_add_replace(_Config) ->
    Key1 = foo,
    Exp_Value = 13,
    Chngd_Value = 27,

    %% Create a directory node...
    Self = self(),
    meck:new(coop_head, [passthrough]),
    meck:expect(coop_head, get_kill_switch, fun(_Coop_Head) -> Self end),
    Fake_Coop_Head = #coop_head{ctl_pid=Self, data_pid=Self},
    Directory_Node = esp_cache:new_directory_node(Fake_Coop_Head),
    ?CTL_MSG({link, _Pids1}) = receive A -> A after 1000 -> timeout end,
    check_directory_empty(Directory_Node, Key1),

    %% Add a new value, then change it...
    Value_Node = insert_value(Directory_Node, Key1, Exp_Value),
    R1 = make_ref(),
    coop:relay_data(Directory_Node, {replace, {Key1, {?VALUE, Chngd_Value}, {R1, Self}}}),
    R2 = make_ref(),
    coop:relay_data(Directory_Node, {lookup, {Key1, {R2, Self}}}),
    timer:sleep(50),
    [{R1, Chngd_Value}, {R2, Chngd_Value}] = check_worker([]),
    true = coop:is_live(Value_Node),

    %% Try to add a value when it already exists...
    R3 = make_ref(),
    coop:relay_data(Directory_Node, {add, {Key1, {?VALUE, Chngd_Value}, {R3, Self}}}),
    timer:sleep(50),
    [{R3, defined}] = check_worker([]),
    true = coop:is_live(Value_Node),

    meck:unload(coop_head).
    

%%----------------------------------------------------------------------
%% Complete Co-op testing
%%----------------------------------------------------------------------
cache_coop(_Config) ->
    Cache_Coop = esp_cache:new_cache_coop(5),
    {Key1, Key2} = {foo, bar},
    {Val1, Val2} = {17, 4},
    Self = self(),

    %% Verify directory empty, add a value, then see it is there.
    R1 = make_ref(),
    coop:relay_data(Cache_Coop, {num_keys, {R1, Self}}),
    timer:sleep(50),
    true = coop:is_live(Cache_Coop),
    [{R1, 0}] = check_worker([]),
    R2 = make_ref(),
    coop:relay_data(Cache_Coop, {add, {Key1, {?VALUE, Val1}, {R2, Self}}}),
    timer:sleep(50),
    true = coop:is_live(Cache_Coop),
    R3 = make_ref(),
    coop:relay_data(Cache_Coop, {lookup, {Key1, {R3, Self}}}),
    timer:sleep(50),
    true = coop:is_live(Cache_Coop),
    [{R2, Val1},{R3, Val1}] = check_worker([]),
    R4 = make_ref(),
    coop:relay_data(Cache_Coop, {num_keys, {R4, Self}}),
    timer:sleep(50),
    true = coop:is_live(Cache_Coop),
    [{R4, 1}] = check_worker([]),
    
    %% Replace the value, then see if it can be retrieved.
    R5 = make_ref(),
    coop:relay_data(Cache_Coop, {replace, {Key1, {?VALUE, Val2}, {R5, Self}}}),
    timer:sleep(50),
    R6 = make_ref(),
    coop:relay_data(Cache_Coop, {num_keys, {R6, Self}}),
    timer:sleep(50),
    true = coop:is_live(Cache_Coop),
    [{R5, Val2}, {R6, 1}] = check_worker([]),
    R7 = make_ref(),
    coop:relay_data(Cache_Coop, {lookup, {Key1, {R7, Self}}}),
    timer:sleep(50),
    true = coop:is_live(Cache_Coop),
    R8 = make_ref(),
    coop:relay_data(Cache_Coop, {num_keys, {R8, Self}}),
    timer:sleep(50),
    true = coop:is_live(Cache_Coop),
    [{R7, Val2},{R8, 1}] = check_worker([]),
    
    %% Verify that missing values return undefined.
    R9 = make_ref(),
    coop:relay_data(Cache_Coop, {lookup, {Key2, {R9, Self}}}),
    timer:sleep(50),
    true = coop:is_live(Cache_Coop),
    RA = make_ref(),
    coop:relay_data(Cache_Coop, {num_keys, {RA, Self}}),
    timer:sleep(50),
    true = coop:is_live(Cache_Coop),
    [{R9, undefined},{RA, 1}] = check_worker([]),
    
    %% Verify that remove works.
    RB = make_ref(),
    coop:relay_data(Cache_Coop, {remove, {Key1, {RB, Self}}}),
    timer:sleep(50),
    true = coop:is_live(Cache_Coop),
    RC = make_ref(),
    coop:relay_data(Cache_Coop, {num_keys, {RC, Self}}),
    timer:sleep(50),
    true = coop:is_live(Cache_Coop),
    RD = make_ref(),
    coop:relay_data(Cache_Coop, {lookup, {Key2, {RD, Self}}}),
    timer:sleep(50),
    true = coop:is_live(Cache_Coop),
    RE = make_ref(),
    coop:relay_data(Cache_Coop, {remove, {Key1, {RE, Self}}}),
    timer:sleep(50),
    true = coop:is_live(Cache_Coop),
    [{RB,Val2},{RC,0},{RD,undefined},{RE,undefined}] = check_worker([]).

