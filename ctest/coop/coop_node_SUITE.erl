-module(coop_node_SUITE).

-include_lib("common_test/include/ct.hrl").

%% Suite functions
-export([all/0, init_per_suite/1, end_per_suite/1]).

%% Control process loop.
-export([
         node_ctl_kill_one_proc/1, node_ctl_kill_two_proc/1,
         node_ctl_stop_one_proc/1,
         task_compute_one/1, task_compute_three_round_robin/1,
         task_compute_three_broadcast/1, task_compute_random/1
        ]). 

%% Spawned functions
-export([x3/1, report_result/1]).
 
all() -> [
          node_ctl_kill_one_proc, node_ctl_kill_two_proc,
          node_ctl_stop_one_proc,
          task_compute_one, task_compute_three_round_robin,
          task_compute_three_broadcast, task_compute_random
         ].

init_per_suite(Config) -> Config.
end_per_suite(_Config) -> ok.

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
