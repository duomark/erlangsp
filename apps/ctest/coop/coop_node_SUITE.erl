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

         sys_suspend/1, sys_format/1, sys_statistics/1, sys_log/1,
         sys_install/1
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
               {stats,   [sequence], [sys_statistics]},
               {log,     [sequence], [sys_log]},
               {install, [sequence], [sys_install]}
              ]}
            ].
 
all() -> [{group, ctl_tests}, {group, data_tests}, {group, sys_tests}].

init_per_suite(Config) -> Config.
end_per_suite(_Config) -> ok.

init_per_group(_Group, Config) -> Config.
end_per_group(_Group, _Config) -> ok.

%% Test module
-define(TM, coop_node).
-define(CK, coop_kill_link_rcv).


%%----------------------------------------------------------------------
%% Node Control
%%----------------------------------------------------------------------
x3(N) -> N * 3.

create_new_coop_node_args() ->
    Kill_Switch = ?CK:make_kill_switch(),
    true = is_process_alive(Kill_Switch),
    [Kill_Switch, {?MODULE, x3}].

create_new_coop_node_args(Dist_Type) ->
    Kill_Switch = ?CK:make_kill_switch(),
    true = is_process_alive(Kill_Switch),
    [Kill_Switch, {?MODULE, x3}, Dist_Type].

node_ctl_kill_one_proc(_Config) ->
    Args = [Kill_Switch, _Node_Fn] = create_new_coop_node_args(),
    {coop_node, Node_Ctl_Pid, Node_Task_Pid} = apply(?TM, new, Args),
    true = is_process_alive(Node_Ctl_Pid),
    true = is_process_alive(Node_Task_Pid),
    exit(Node_Task_Pid, kill),
    timer:sleep(50),
    false = is_process_alive(Node_Ctl_Pid),
    false = is_process_alive(Node_Task_Pid),
    false = is_process_alive(Kill_Switch).

node_ctl_kill_two_proc(_Config) ->
    Args = [Kill_Switch, _Node_Fn] = create_new_coop_node_args(),
    {coop_node, Node_Ctl_Pid1, Node_Task_Pid1} = apply(?TM, new, Args),
    true = is_process_alive(Node_Ctl_Pid1),
    true = is_process_alive(Node_Task_Pid1),
    {coop_node, Node_Ctl_Pid2, Node_Task_Pid2} = apply(?TM, new, Args),
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
    Coop_Node = {coop_node, Node_Ctl_Pid, Node_Task_Pid} = apply(?TM, new, Args),
    true = is_process_alive(Node_Ctl_Pid),
    true = is_process_alive(Node_Task_Pid),
    ?TM:node_ctl_stop(Coop_Node),
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

setup_no_downstream() ->    
    Args = [_Kill_Switch, _Node_Fn] = create_new_coop_node_args(),
    Coop_Node = apply(?TM, new, Args),
    [] = ?TM:node_task_get_downstream_pids(Coop_Node),
    Coop_Node.

setup_no_downstream(Dist_Type) ->    
    Args = [_Kill_Switch, _Node_Fn, Dist_Type] = create_new_coop_node_args(Dist_Type),
    Coop_Node = apply(?TM, new, Args),
    [] = ?TM:node_task_get_downstream_pids(Coop_Node),
    Coop_Node.
    
task_compute_one(_Config) ->
    Coop_Node = {coop_node, _Node_Ctl_Pid, Node_Task_Pid} = setup_no_downstream(),

    ?TM:node_task_add_downstream_pids(Coop_Node, []),
    [] = ?TM:node_task_get_downstream_pids(Coop_Node),

    Receiver = [self()],
    ?TM:node_task_add_downstream_pids(Coop_Node, Receiver),
    Receiver = ?TM:node_task_get_downstream_pids(Coop_Node),

    ?TM:node_task_deliver_data(Node_Task_Pid, 5),
    15 = receive Data -> Data end.

task_compute_three_round_robin(_Config) ->
    Coop_Node = {coop_node, _Node_Ctl_Pid, Node_Task_Pid} = setup_no_downstream(),
    Receivers = [A,B,C] = [proc_lib:spawn_link(?MODULE, report_result, [[]])
                           || _N <- lists:seq(1,3)],
    ?TM:node_task_add_downstream_pids(Coop_Node, [A]),
    [A] = ?TM:node_task_get_downstream_pids(Coop_Node),
    ?TM:node_task_add_downstream_pids(Coop_Node, [B,C]),
    Receivers = ?TM:node_task_get_downstream_pids(Coop_Node),
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
    Coop_Node = {coop_node, _Node_Ctl_Pid, Node_Task_Pid} = setup_no_downstream(broadcast),
    Receivers = [A,B,C] = [proc_lib:spawn_link(?MODULE, report_result, [[]])
                           || _N <- lists:seq(1,3)],
    ?TM:node_task_add_downstream_pids(Coop_Node, [A]),
    [A] = ?TM:node_task_get_downstream_pids(Coop_Node),
    ?TM:node_task_add_downstream_pids(Coop_Node, [B,C]),
    Receivers = ?TM:node_task_get_downstream_pids(Coop_Node),
    [true = is_process_alive(Pid) || Pid <- Receivers],

    ?TM:node_task_deliver_data(Node_Task_Pid, 5),
    timer:sleep(50),
    [15, 15, 15] = [get_result_data(Pid) || Pid <- Receivers],

    ?TM:node_task_deliver_data(Node_Task_Pid, 6),
    timer:sleep(50),
    [18, 18, 18] = [get_result_data(Pid) || Pid <- Receivers].

task_compute_random(_Config) ->
    Coop_Node = {coop_node, _Node_Ctl_Pid, Node_Task_Pid} = setup_no_downstream(random),
    Receivers = [proc_lib:spawn_link(?MODULE, report_result, [[]])
                 || _N <- lists:seq(1,5)],
    ?TM:node_task_add_downstream_pids(Coop_Node, Receivers),
    Receivers = ?TM:node_task_get_downstream_pids(Coop_Node),
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
    Coop_Node = {coop_node, _Node_Ctl_Pid, Node_Task_Pid} = setup_no_downstream(),
    Receiver = [self()],
    ?TM:node_task_add_downstream_pids(Coop_Node, Receiver),
    Receiver = ?TM:node_task_get_downstream_pids(Coop_Node),

    %% Verify it computes normally...
    ?TM:node_task_deliver_data(Node_Task_Pid, 5),
    15 = receive Data1 -> Data1 end,
    
    %% Suspend message handling and get no result...
    ?TM:node_ctl_suspend(Coop_Node),
    timer:sleep(50),
    ?TM:node_task_deliver_data(Node_Task_Pid, 5),
    0 = receive Data2 -> Data2 after 1000 -> 0 end,
    true = is_process_alive(Node_Task_Pid),

    %% Resume and result appears.
    ?TM:node_ctl_resume(Coop_Node),
    15 = receive Data3 -> Data3 after 100 -> 0 end.

sys_format(_Config) ->
    Coop_Node = {coop_node, _Node_Ctl_Pid, Node_Task_Pid} = setup_no_downstream(random),

    %% Get the custom status information...
    Custom_Running_Fmt = get_custom_fmt(sys:get_status(Node_Task_Pid)),
    ["Status for coop_node", Custom_Running_Props]
        = [proplists:get_value(P, Custom_Running_Fmt) || P <- [header, data]],
    [running, {coop_node_SUITE,x3}, 0, random]
        = [proplists:get_value(P, Custom_Running_Props)
           || P <- ["Status", "Node_Fn", "Downstream_Pid_Count", "Data_Flow_Method"]],

    [A,B,C] = [proc_lib:spawn_link(?MODULE, report_result, [[]]) || _N <- lists:seq(1,3)],
    ?TM:node_task_add_downstream_pids(Coop_Node, [A,B,C]),
    [A,B,C] = ?TM:node_task_get_downstream_pids(Coop_Node),

    ?TM:node_ctl_suspend(Coop_Node),
    timer:sleep(50),
    Custom_Suspended_Fmt = get_custom_fmt(sys:get_status(Node_Task_Pid)),
    Custom_Suspended_Props = proplists:get_value(data, Custom_Suspended_Fmt),
    [suspended, {coop_node_SUITE,x3}, 3, random]
        = [proplists:get_value(P, Custom_Suspended_Props)
           || P <- ["Status", "Node_Fn", "Downstream_Pid_Count", "Data_Flow_Method"]],
    
    ?TM:node_ctl_resume(Coop_Node),
    timer:sleep(50),
    New_Custom_Running_Fmt = get_custom_fmt(sys:get_status(Node_Task_Pid)),
    ["Status for coop_node", New_Custom_Running_Props]
        = [proplists:get_value(P, New_Custom_Running_Fmt) || P <- [header, data]],
    [running, {coop_node_SUITE,x3}, 3, random]
        = [proplists:get_value(P, New_Custom_Running_Props)
           || P <- ["Status", "Node_Fn", "Downstream_Pid_Count", "Data_Flow_Method"]].
    

get_custom_fmt(Status) -> lists:nth(5, element(4, Status)).

send_data(N, {coop_node, _Node_Ctl_Pid, Node_Task_Pid} = Coop_Node) ->
    Receiver = [self()],
    ?TM:node_task_add_downstream_pids(Coop_Node, Receiver),
    Receiver = ?TM:node_task_get_downstream_pids(Coop_Node),

    %% Verify it computes normally...
    [begin
         ?TM:node_task_deliver_data(Node_Task_Pid, 5),
         15 = receive Data -> Data end
     end || _N <- lists:seq(1,N)].
    
sys_statistics(_Config) ->
    Coop_Node = setup_no_downstream(),
    ok = ?TM:node_ctl_stats(Coop_Node, true, self()),
    {ok, Props1} = ?TM:node_ctl_stats(Coop_Node, get, self()),
    [0,0] = [proplists:get_value(P, Props1) || P <- [messages_in, messages_out]],
    send_data(10, Coop_Node),
    {ok, Props2} = ?TM:node_ctl_stats(Coop_Node, get, self()),
    [12,10] = [proplists:get_value(P, Props2) || P <- [messages_in, messages_out]],
    ok = ?TM:node_ctl_stats(Coop_Node, false, self()).

sys_log(_Config) ->
    Coop_Node = setup_no_downstream(),
    %% ok = ?TM:node_ctl_log_to_file(Coop_Node, "./coop.dump", self())
    ok = ?TM:node_ctl_log(Coop_Node, true, self()),
    {ok, []} = ?TM:node_ctl_log(Coop_Node, get, self()),
    send_data(6, Coop_Node),
    {ok, Events} = ?TM:node_ctl_log(Coop_Node, get, self()),
    10 = length(Events),
    Ins = lists:duplicate(5,{in,5}),
    Ins = [{Type,Num} || {{Type,Num}, _Flow, _Fun} <- Events],
    Outs = lists:duplicate(5,{out,15}),
    Outs = [{Type,Num} || {{Type,Num,_Pid}, _Flow, _Fun} <- Events],
    ok = ?TM:node_ctl_log(Coop_Node, false, self()).
    %% ok = ?TM:node_ctl_log_to_file(Coop_Node, false, self()).

sys_install(_Config) ->
    Coop_Node = {coop_node, _Node_Ctl_Pid, Node_Task_Pid} = setup_no_downstream(),
    Pid = spawn_link(fun() ->
                             %% Trace results...
                             receive {15, 30} -> ok;
                                      Bad_Result -> exit(Bad_Result)
                              after 2000 -> exit(timeout)
                              end,
                             
                             %% After trace uninstalled.
                             case receive Data -> Data after 200 -> timeout end of
                                 {data, 21} -> ok;
                                 Bad -> Msg = io_lib:format("Trace_Fn failed ~p",[Bad]),
                                        exit(lists:flatten(Msg))
                             end
                     end),
    F = fun
            ({Ins, Outs, 3}, _Any, round_robin) ->
                Pid ! {Ins, Outs};
            ({Ins, Outs, Count}, {in, Amt}, round_robin) when is_integer(Amt) ->
                {Ins+Amt, Outs, Count+1};
            ({Ins, Outs, Count}, {out, Amt, _Pid}, round_robin) when is_integer(Amt) ->
                {Ins, Outs+Amt, Count};
            ({Ins, Outs, Count}, {in, {add_downstream, _Id}}, round_robin) ->
                {Ins, Outs, Count};
            ({Ins, Outs, Count}, {in, {get_downstream, _Id}}, round_robin) ->
                {Ins, Outs, Count};
            (_State, Unknown, _Extra) ->
                Pid ! {unknown_msg_rcvd, Unknown}
        end,
    ok = ?TM:node_ctl_install_trace_fn(Coop_Node, {F, {0,0,0}}, self()),

    send_data(3, Coop_Node),
    timer:sleep(50),
    ok = ?TM:node_ctl_remove_trace_fn(Coop_Node, F, self()),
    ?TM:node_task_deliver_data(Node_Task_Pid, 7),
    _ = receive Data -> Pid ! {data, Data} after 50 -> 0 end,
    timer:sleep(1000).
