-module(coop_node_SUITE).

-include_lib("common_test/include/ct.hrl").

%% Suite functions
-export([all/0, init_per_suite/1, end_per_suite/1]).

%% Control process loop.
-export([
         node_ctl_kill_one_proc/1, node_ctl_kill_two_proc/1,
         node_ctl_stop_one_proc/1,
         task_compute/1
        ]). 

%% Spawned functions
-export([x3/1]).
 
all() -> [
          node_ctl_kill_one_proc, node_ctl_kill_two_proc,
          node_ctl_stop_one_proc,
          task_compute
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
task_compute(_Config) ->
    Args = [_Kill_Switch, _Node_Fn] = create_new_coop_node_args(),
    {_Node_Ctl_Pid, Node_Task_Pid} = apply(?TM, new, Args),
    [] = ?TM:node_task_get_downstream_pids(Node_Task_Pid),
    
    Receiver = [self()],
    ?TM:node_task_add_downstream_pids(Node_Task_Pid, Receiver),
    Receiver = ?TM:node_task_get_downstream_pids(Node_Task_Pid),

    ?TM:node_task_deliver_data(Node_Task_Pid, 5),
    15 = receive Data -> Data end.


