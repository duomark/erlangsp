-module(coop_node_SUITE).

-include_lib("../../erlangsp/include/license_and_copyright.hrl").
-include_lib("common_test/include/ct.hrl").

%% Suite functions
-export([
         all/0, groups/0,
         init_per_suite/1, end_per_suite/1,
         init_per_group/2, end_per_group/2
        ]).

%% Control process loop.
-export([
         node_ctl_kill_one_proc/1, node_ctl_kill_two_proc/1,
         node_ctl_stop_one_proc/1,

         task_compute_one/1, task_compute_three_round_robin/1,
         task_compute_three_broadcast/1, task_compute_random/1,

         sys_suspend/1, sys_format/1, sys_statistics/1
        ]). 

%% Spawned functions
-export([x3/1, report_result/1]).
 
groups() -> [{ctl_tests, [sequence],
              [
               {kill, [sequence], [node_ctl_kill_one_proc, node_ctl_kill_two_proc]},
               {stop, [sequence], [node_ctl_stop_one_proc]}
              ]},
             {data_tests, [sequence],
              [
               {compute, [sequence], [task_compute_one, task_compute_three_round_robin,
                                      task_compute_three_broadcast, task_compute_random]}
              ]},
             {sys_tests, [sequence],
              [
               {suspend, [sequence], [sys_suspend]},
               {format,  [sequence], [sys_format]},
               {stats,   [sequence], [sys_statistics]}
              ]}
            ].
 
all() -> [{group, ctl_tests}, {group, data_tests}, {group, sys_tests}].

init_per_suite(Config) -> Config.
end_per_suite(_Config) -> ok.

init_per_group(_Group, Config) -> Config.
end_per_group(_Group, _Config) -> ok.

%% Test module
-define(TM, coop_node).

%%----------------------------------------------------------------------
%% Node Control
%%----------------------------------------------------------------------
x3(N) -> N * 3.

create_new_coop_node_args() ->
    Kill_Switch = ?TM:make_kill_switch(),
    true = is_process_alive(Kill_Switch),
    [Kill_Switch, {?MODULE, x3}].

create_new_coop_node_args(Dist_Type) ->
    Kill_Switch = ?TM:make_kill_switch(),
    true = is_process_alive(Kill_Switch),
    [Kill_Switch, {?MODULE, x3}, Dist_Type].

node_ctl_kill_one_proc(_Config) ->
    Args = [Kill_Switch, _Node_Fn] = create_new_coop_node_args(),
    {Node_Ctl_Pid, Node_Task_Pid} = apply(?TM, new, Args),
    true = is_process_alive(Node_Ctl_Pid),
    true = is_process_alive(Node_Task_Pid),
    exit(Node_Task_Pid, kill),
    timer:sleep(50),
    false = is_process_alive(Node_Ctl_Pid),
    false = is_process_alive(Node_Task_Pid),
    false = is_process_alive(Kill_Switch).

node_ctl_kill_two_proc(_Config) ->
    Args = [Kill_Switch, _Node_Fn] = create_new_coop_node_args(),
    {Node_Ctl_Pid1, Node_Task_Pid1} = apply(?TM, new, Args),
    true = is_process_alive(Node_Ctl_Pid1),
    true = is_process_alive(Node_Task_Pid1),
    {Node_Ctl_Pid2, Node_Task_Pid2} = apply(?TM, new, Args),
    true = is_process_alive(Node_Ctl_Pid2),
    true = is_process_alive(Node_Task_Pid2),
    exit(Node_Ctl_Pid2, kill),
    timer:sleep(50),
    false = is_process_alive(Node_Ctl_Pid1),
    false = is_process_alive(Node_Task_Pid1),
    false = is_process_alive(Node_Ctl_Pid2),
    false = is_process_alive(Node_Task_Pid2),
    false = is_process_alive(Kill_Switch).

node_ctl_stop_one_proc(_Config) ->
    Args = [Kill_Switch, _Node_Fn] = create_new_coop_node_args(),
    {Node_Ctl_Pid, Node_Task_Pid} = apply(?TM, new, Args),
    true = is_process_alive(Node_Ctl_Pid),
    true = is_process_alive(Node_Task_Pid),
    ?TM:node_ctl_stop(Node_Ctl_Pid),
    timer:sleep(50),
    false = is_process_alive(Node_Ctl_Pid),
    false = is_process_alive(Node_Task_Pid),
    false = is_process_alive(Kill_Switch).


%%----------------------------------------------------------------------
%% Function Tasks
%%----------------------------------------------------------------------
report_result(Rcvd) ->
    receive
        {get_oldest, From} ->
            case Rcvd of
                [] -> From ! none, report_result(Rcvd);
                [H|T] -> From ! H, report_result(T)
            end;
        Any -> report_result([Any] ++ Rcvd)
    end.

get_result_data(Pid) ->
    Pid ! {get_oldest, self()},
    receive Any -> Any after 50 -> timeout end.
    
task_compute_one(_Config) ->
    Args = [_Kill_Switch, _Node_Fn] = create_new_coop_node_args(),
    {_Node_Ctl_Pid, Node_Task_Pid} = apply(?TM, new, Args),
    [] = ?TM:node_task_get_downstream_pids(Node_Task_Pid),
    
    Receiver = [self()],
    ?TM:node_task_add_downstream_pids(Node_Task_Pid, Receiver),
    Receiver = ?TM:node_task_get_downstream_pids(Node_Task_Pid),

    ?TM:node_task_deliver_data(Node_Task_Pid, 5),
    15 = receive Data -> Data end.

task_compute_three_round_robin(_Config) ->
    Args = [_Kill_Switch, _Node_Fn] = create_new_coop_node_args(),
    {_Node_Ctl_Pid, Node_Task_Pid} = apply(?TM, new, Args),
    [] = ?TM:node_task_get_downstream_pids(Node_Task_Pid),

    Receivers = [A,B,C] = [proc_lib:spawn_link(?MODULE, report_result, [[]])
                           || _N <- lists:seq(1,3)],
    ?TM:node_task_add_downstream_pids(Node_Task_Pid, [A]),
    [A] = ?TM:node_task_get_downstream_pids(Node_Task_Pid),
    ?TM:node_task_add_downstream_pids(Node_Task_Pid, [B,C]),
    Receivers = ?TM:node_task_get_downstream_pids(Node_Task_Pid),
    [true = is_process_alive(Pid) || Pid <- Receivers],

    ?TM:node_task_deliver_data(Node_Task_Pid, 5),
    timer:sleep(50),
    [15, none, none] = [get_result_data(Pid) || Pid <- Receivers],

    ?TM:node_task_deliver_data(Node_Task_Pid, 5),
    timer:sleep(50),
    [none, 15, none] = [get_result_data(Pid) || Pid <- Receivers],

    ?TM:node_task_deliver_data(Node_Task_Pid, 5),
    timer:sleep(50),
    [none, none, 15] = [get_result_data(Pid) || Pid <- Receivers],

    ?TM:node_task_deliver_data(Node_Task_Pid, 9),
    timer:sleep(50),
    [27, none, none] = [get_result_data(Pid) || Pid <- Receivers],

    ?TM:node_task_deliver_data(Node_Task_Pid, 7),
    ?TM:node_task_deliver_data(Node_Task_Pid, 6),
    timer:sleep(50),
    [none, 21, 18] = [get_result_data(Pid) || Pid <- Receivers].

task_compute_three_broadcast(_Config) ->
    Args = [_Kill_Switch, _Node_Fn, _Dist_Type] = create_new_coop_node_args(broadcast),
    {_Node_Ctl_Pid, Node_Task_Pid} = apply(?TM, new, Args),
    [] = ?TM:node_task_get_downstream_pids(Node_Task_Pid),

    Receivers = [A,B,C] = [proc_lib:spawn_link(?MODULE, report_result, [[]])
                           || _N <- lists:seq(1,3)],
    ?TM:node_task_add_downstream_pids(Node_Task_Pid, [A]),
    [A] = ?TM:node_task_get_downstream_pids(Node_Task_Pid),
    ?TM:node_task_add_downstream_pids(Node_Task_Pid, [B,C]),
    Receivers = ?TM:node_task_get_downstream_pids(Node_Task_Pid),
    [true = is_process_alive(Pid) || Pid <- Receivers],

    ?TM:node_task_deliver_data(Node_Task_Pid, 5),
    timer:sleep(50),
    [15, 15, 15] = [get_result_data(Pid) || Pid <- Receivers],

    ?TM:node_task_deliver_data(Node_Task_Pid, 6),
    timer:sleep(50),
    [18, 18, 18] = [get_result_data(Pid) || Pid <- Receivers].

task_compute_random(_Config) ->
    Args = [_Kill_Switch, _Node_Fn, _Dist_Type] = create_new_coop_node_args(random),
    {_Node_Ctl_Pid, Node_Task_Pid} = apply(?TM, new, Args),
    [] = ?TM:node_task_get_downstream_pids(Node_Task_Pid),

    Receivers = [proc_lib:spawn_link(?MODULE, report_result, [[]])
                 || _N <- lists:seq(1,5)],
    ?TM:node_task_add_downstream_pids(Node_Task_Pid, Receivers),
    Receivers = ?TM:node_task_get_downstream_pids(Node_Task_Pid),
    [true = is_process_alive(Pid) || Pid <- Receivers],

    Ets_Name = crypto_rand_test,
    Key = crypto_rand_stub,
    ets:new(Ets_Name, [named_table, public]),
    ets:insert(Ets_Name, {Key, [4,2,3,1,5]}),
    meck:new(coop_node_util),
    meck:expect(coop_node_util, random_worker, fun(_Tuple) -> [{Key, [H|T]}] = ets:lookup(Ets_Name, Key), ets:insert(Ets_Name, {Key, T}), H end),
    ?TM:node_task_deliver_data(Node_Task_Pid, 3),
    timer:sleep(50),
    [none, none, none, 9, none] = [get_result_data(Pid) || Pid <- Receivers],
    ?TM:node_task_deliver_data(Node_Task_Pid, 4),
    timer:sleep(50),
    [none, 12, none, none, none] = [get_result_data(Pid) || Pid <- Receivers],
    ?TM:node_task_deliver_data(Node_Task_Pid, 5),
    timer:sleep(50),
    [none, none, 15, none, none] = [get_result_data(Pid) || Pid <- Receivers],
    ?TM:node_task_deliver_data(Node_Task_Pid, 6),
    timer:sleep(50),
    [18, none, none, none, none] = [get_result_data(Pid) || Pid <- Receivers],
    ?TM:node_task_deliver_data(Node_Task_Pid, 7),
    timer:sleep(50),
    [none, none, none, none, 21] = [get_result_data(Pid) || Pid <- Receivers],
    meck:unload(coop_node_util),
    ets:delete(Ets_Name).

sys_suspend(_Config) ->
    Args = [_Kill_Switch, _Node_Fn, _Dist_Type] = create_new_coop_node_args(random),
    {_Node_Ctl_Pid, Node_Task_Pid} = apply(?TM, new, Args),
    [] = ?TM:node_task_get_downstream_pids(Node_Task_Pid),
    
    Receiver = [self()],
    ?TM:node_task_add_downstream_pids(Node_Task_Pid, Receiver),
    Receiver = ?TM:node_task_get_downstream_pids(Node_Task_Pid),

    %% Verify it computes normally...
    ?TM:node_task_deliver_data(Node_Task_Pid, 5),
    15 = receive Data1 -> Data1 end,
    
    %% Suspend message handling and get no result...
    sys:suspend(Node_Task_Pid),
    ?TM:node_task_deliver_data(Node_Task_Pid, 5),
    0 = receive Data2 -> Data2 after 100 -> 0 end,
    true = is_process_alive(Node_Task_Pid),

    %% Resume and result appears.
    sys:resume(Node_Task_Pid),
    15 = receive Data3 -> Data3 after 100 -> 0 end.

sys_format(_Config) ->
    Args = [_Kill_Switch, _Node_Fn, _Dist_Type] = create_new_coop_node_args(random),
    {_Node_Ctl_Pid, Node_Task_Pid} = apply(?TM, new, Args),
    [] = ?TM:node_task_get_downstream_pids(Node_Task_Pid),

    %% Get the custom status information...
    Custom_Running_Fmt = get_custom_fmt(sys:get_status(Node_Task_Pid)),
    "Status for coop_node" = proplists:get_value(header, Custom_Running_Fmt),
    Custom_Running_Props = proplists:get_value(data, Custom_Running_Fmt),
    running = proplists:get_value("Status", Custom_Running_Props),
    {coop_node_SUITE,x3} = proplists:get_value("Node_Fn", Custom_Running_Props),
    0 = proplists:get_value("Downstream_Pid_Count", Custom_Running_Props),
    random = proplists:get_value("Data_Flow_Method", Custom_Running_Props),

    [A,B,C] = [proc_lib:spawn_link(?MODULE, report_result, [[]]) || _N <- lists:seq(1,3)],
    ?TM:node_task_add_downstream_pids(Node_Task_Pid, [A,B,C]),
    [A,B,C] = ?TM:node_task_get_downstream_pids(Node_Task_Pid),

    sys:suspend(Node_Task_Pid),
    Custom_Suspended_Fmt = get_custom_fmt(sys:get_status(Node_Task_Pid)),
    Custom_Suspended_Props = proplists:get_value(data, Custom_Suspended_Fmt),
    suspended = proplists:get_value("Status", Custom_Suspended_Props),
    {coop_node_SUITE,x3} = proplists:get_value("Node_Fn", Custom_Suspended_Props),
    3 = proplists:get_value("Downstream_Pid_Count", Custom_Suspended_Props),
    random = proplists:get_value("Data_Flow_Method", Custom_Suspended_Props).

get_custom_fmt(Status) -> lists:nth(5, element(4, Status)).

sys_statistics(_Config) ->
    Args = [_Kill_Switch, _Node_Fn, _Dist_Type] = create_new_coop_node_args(random),
    {_Node_Ctl_Pid, Node_Task_Pid} = apply(?TM, new, Args),
    [] = ?TM:node_task_get_downstream_pids(Node_Task_Pid),
    sys:statistics(Node_Task_Pid, true),
    sys:log(Node_Task_Pid, true),
    sys:trace(Node_Task_Pid, true),
    
    Receiver = [self()],
    ?TM:node_task_add_downstream_pids(Node_Task_Pid, Receiver),
    Receiver = ?TM:node_task_get_downstream_pids(Node_Task_Pid),

    %% Verify it computes normally...
    [begin
         ?TM:node_task_deliver_data(Node_Task_Pid, 5),
         15 = receive Data1 -> Data1 end
     end || _N <- lists:seq(1,10)],

    error_logger:info_msg("Stats: ~p~n", [sys:statistics(Node_Task_Pid, get)]),
    error_logger:info_msg("Last logged: ~p~n", [sys:log(Node_Task_Pid, get)]),
    sys:trace(Node_Task_Pid, false),
    sys:statistics(Node_Task_Pid, false),
    sys:log(Node_Task_Pid, false).
