-module(coop_head_SUITE).

-include("../../src/license_and_copyright.hrl").
-include_lib("common_test/include/ct.hrl").

%% Suite functions
-export([
         all/0, groups/0,
         init_per_suite/1, end_per_suite/1,
         init_per_group/2, end_per_group/2
        ]).

%% Control process loop.
-export([
         head_ctl_kill_one_proc/1, head_ctl_kill_two_proc/1,
         head_ctl_stop_one_proc/1,

         send_ctl_msgs/1, send_data_msgs/1,

         sys_suspend/1, sys_format/1, sys_statistics/1, sys_log/1
         %% sys_install/1
        ]). 

%% Spawned functions
-export([report_result/0]).
-export([
         fake_node_ctl/0, fake_node_data/0, fake_coop_node/0,
         result_node_ctl/0, result_node_task/0, result_coop_node/0
        ]).

-include_lib("coop/include/coop.hrl").
 
groups() -> [{ctl_tests, [sequence],
              [
               {kill, [sequence], [head_ctl_kill_one_proc, head_ctl_kill_two_proc]},
               {stop, [sequence], [head_ctl_stop_one_proc]}
              ]},
             {send_msgs, [sequence],
              [
               {msgs, [sequence], [send_ctl_msgs, send_data_msgs]}
              ]},
             {sys_tests, [sequence],
              [
               {suspend, [sequence], [sys_suspend]},
               {format,  [sequence], [sys_format]},
               {stats,   [sequence], [sys_statistics]},
               {log,     [sequence], [sys_log]}
               %% {install, [sequence], [sys_install]}
              ]}
            ].
 
all() -> [{group, ctl_tests}, {group, send_msgs}, {group, sys_tests}].

init_per_suite(Config) -> Config.
end_per_suite(_Config) -> ok.

init_per_group(_Group, Config) -> Config.
end_per_group(_Group, _Config) -> ok.

%% Test module
-define(TM, coop_head).

%%----------------------------------------------------------------------
%% Head Control
%%----------------------------------------------------------------------
%% fake_node_ctl()  -> proc_lib:spawn(?MODULE, ctl_loop).
%% fake_node_data() -> proc_lib:spawn(?MODULE, data_loop).
fake_node_ctl()  -> proc_lib:spawn(?TM, echo_loop, ["NCTL"]).
fake_node_data() -> proc_lib:spawn(?TM, echo_loop, ["NDTA"]).
fake_coop_node() -> {coop_node, fake_node_ctl(), fake_node_data()}.
make_kill_switch() -> coop_kill_link_rcv:make_kill_switch().
     

create_new_coop_head_args(Fn) ->
    Kill_Switch = make_kill_switch(),
    true = is_process_alive(Kill_Switch),
    [Kill_Switch, ?MODULE:Fn()].

head_ctl_kill_one_proc(_Config) ->
    Args = [Kill_Switch, _Coop_Node] = create_new_coop_head_args(fake_coop_node),
    #coop_head{ctl_pid=Head_Ctl_Pid, data_pid=Head_Data_Pid} = apply(?TM, new, Args),
    timer:sleep(50),
    [true = is_process_alive(Pid) || Pid <- [Head_Ctl_Pid, Head_Data_Pid]],
    exit(Head_Data_Pid, kill),
    timer:sleep(50),
    [false = is_process_alive(Pid) || Pid <- [Head_Ctl_Pid, Head_Data_Pid, Kill_Switch]],
    ok.

head_ctl_kill_two_proc(_Config) ->
    Args = [Kill_Switch, _Coop_Node] = create_new_coop_head_args(fake_coop_node),
    #coop_head{ctl_pid=Head_Ctl_Pid1, data_pid=Head_Data_Pid1} = apply(?TM, new, Args),
    [true = is_process_alive(Pid) || Pid <- [Head_Ctl_Pid1, Head_Data_Pid1]],
    #coop_head{ctl_pid=Head_Ctl_Pid2, data_pid=Head_Data_Pid2} = apply(?TM, new, Args),
    [true = is_process_alive(Pid) || Pid <- [Head_Ctl_Pid2, Head_Data_Pid2]],
    exit(Head_Ctl_Pid2, kill),
    timer:sleep(50),
    [false = is_process_alive(Pid) || Pid <- [Head_Ctl_Pid1, Head_Data_Pid1, Head_Ctl_Pid2,
                                              Head_Data_Pid2, Kill_Switch]],
    ok.

head_ctl_stop_one_proc(_Config) ->
    Args = [_Kill_Switch, _Coop_Node] = create_new_coop_head_args(fake_coop_node),
    Coop_Node = #coop_head{ctl_pid=Head_Ctl_Pid, data_pid=Head_Data_Pid} = apply(?TM, new, Args),
    [true = is_process_alive(Pid) || Pid <- [Head_Ctl_Pid, Head_Data_Pid]],
    ?TM:stop(Coop_Node),
    timer:sleep(50),
    false = is_process_alive(Head_Ctl_Pid),
    %% false = is_process_alive(Head_Data_Pid),
    %% false = is_process_alive(Kill_Switch).
    ok.

%%----------------------------------------------------------------------
%% Function Tasks
%%----------------------------------------------------------------------
result_node_ctl()  -> proc_lib:spawn(?MODULE, report_result, []).
result_node_task() -> proc_lib:spawn(?MODULE, report_result, []).
result_coop_node() -> #coop_node{ctl_pid=result_node_ctl(), task_pid=result_node_task()}.

report_result() ->
    report_result([]).

report_result(Rcvd) ->
    receive
        {get_oldest, From} ->
            case Rcvd of
                [] -> From ! none, report_result(Rcvd);
                [H|T] -> From ! H, report_result(T)
            end;
        Any -> report_result(Rcvd ++ [Any])
    end.

get_result_data(Pid) ->
    Pid ! {get_oldest, self()},
    receive Any -> Any after 50 -> timeout end.

start_head() ->
    Args = [_Kill_Switch, #coop_node{ctl_pid=Node_Ctl_Pid, task_pid=Node_Task_Pid} = Coop_Node]
        = create_new_coop_head_args(result_coop_node),
    Coop_Head = #coop_head{ctl_pid=Head_Ctl_Pid, data_pid=Head_Data_Pid} = apply(?TM, new, Args),
    Root_Pid = ?TM:get_root_pid(Coop_Head),
    timer:sleep(50),
    [true = is_process_alive(P) || P <- [Head_Ctl_Pid, Head_Data_Pid,
                                         Node_Ctl_Pid, Node_Task_Pid, Root_Pid]],
    {Coop_Head, Root_Pid, Coop_Node}.

send_ctl_msgs(_Config) ->
    {#coop_head{ctl_pid=Head_Ctl_Pid, data_pid=Head_Data_Pid} = Coop_Head,
     Root_Pid, #coop_node{ctl_pid=Node_Ctl_Pid, task_pid=Node_Task_Pid}} = start_head(),
    Procs = [Head_Ctl_Pid, Head_Data_Pid, Node_Ctl_Pid, Node_Task_Pid, Root_Pid],
    [?TM:send_ctl_msg(Coop_Head, N) || N <- lists:seq(2,4)],
    timer:sleep(50),
    [true = is_process_alive(P) || P <- Procs],
    [2,3,4,none] = [get_result_data(Node_Ctl_Pid) || _N <- lists:seq(1,4)],
    [none,none,none,none] = [get_result_data(Node_Task_Pid) || _N <- lists:seq(1,4)],
    ok.

send_data_msgs(_Config) ->
    {#coop_head{ctl_pid=Head_Ctl_Pid, data_pid=Head_Data_Pid} = Coop_Head,
     Root_Pid, #coop_node{ctl_pid=Node_Ctl_Pid, task_pid=Node_Task_Pid}} = start_head(),
    Procs = [Head_Ctl_Pid, Head_Data_Pid, Node_Ctl_Pid, Node_Task_Pid, Root_Pid],
    [?TM:send_data_msg(Coop_Head, N) || N <- lists:seq(5,7)],
    timer:sleep(50),
    [true = is_process_alive(P) || P <- Procs],
    [none,none,none,none] = [get_result_data(Node_Ctl_Pid) || _N <- lists:seq(1,4)],
    [5,6,7,none] = [get_result_data(Node_Task_Pid) || _N <- lists:seq(1,4)],
    ok.

sys_suspend(_Config) ->
    {#coop_head{ctl_pid=Head_Ctl_Pid, data_pid=Head_Data_Pid} = Coop_Head,
     Root_Pid, #coop_node{ctl_pid=Node_Ctl_Pid, task_pid=Node_Task_Pid}} = start_head(),
    Procs = [Head_Ctl_Pid, Head_Data_Pid, Node_Ctl_Pid, Node_Task_Pid, Root_Pid],
    [?TM:send_data_msg(Coop_Head, N) || N <- lists:seq(5,7)],
    timer:sleep(50),
    [true = is_process_alive(P) || P <- Procs],
    [5,6,7,none] = [get_result_data(Node_Task_Pid) || _N <- lists:seq(1,4)],
    
    %% Suspend message handling and get no result...
    ?TM:suspend_root(Coop_Head),
    timer:sleep(50),
    [?TM:send_data_msg(Coop_Head, N) || N <- lists:seq(8,10)],
    [true = is_process_alive(P) || P <- Procs],
    [none,none,none,none] = [get_result_data(Node_Task_Pid) || _N <- lists:seq(1,4)],

    %% Resume and result appears.
    ?TM:resume_root(Coop_Head),
    timer:sleep(50),
    [true = is_process_alive(P) || P <- Procs],
    [8,9,10,none] = [get_result_data(Node_Task_Pid) || _N <- lists:seq(1,4)],
    ok.

sys_format(_Config) ->
    {#coop_head{ctl_pid=Head_Ctl_Pid, data_pid=Head_Data_Pid} = _Coop_Head,
     Root_Pid, #coop_node{ctl_pid=Node_Ctl_Pid, task_pid=Node_Task_Pid}} = start_head(),
    Procs = [Head_Ctl_Pid, Head_Data_Pid, Node_Ctl_Pid, Node_Task_Pid, Root_Pid],

    %% Get the custom status information...
    Custom_Running_Fmt = get_custom_fmt(sys:get_status(Root_Pid)),
    ["Status for coop_head_root_rcv", Custom_Running_Props]
        = [proplists:get_value(P, Custom_Running_Fmt) || P <- [header, data]],
    [running, pass_thru, [{messages, []}]]
        = [proplists:get_value(P, Custom_Running_Props) || P <- ["Status", "Loop", "Messages"]],
    [true = is_process_alive(P) || P <- Procs],

    sys:suspend(Root_Pid),
    timer:sleep(50),
    Custom_Suspended_Fmt = get_custom_fmt(sys:get_status(Root_Pid)),
    Custom_Suspended_Props = proplists:get_value(data, Custom_Suspended_Fmt),
    [suspended, pass_thru, [{messages, []}]]
        = [proplists:get_value(P, Custom_Suspended_Props) || P <- ["Status", "Loop", "Messages"]],
    
    sys:resume(Root_Pid),
    timer:sleep(50),
    New_Custom_Running_Fmt = get_custom_fmt(sys:get_status(Root_Pid)),
    ["Status for coop_head_root_rcv", New_Custom_Running_Props]
        = [proplists:get_value(P, New_Custom_Running_Fmt) || P <- [header, data]],
    [running, pass_thru, [{messages, []}]]
        = [proplists:get_value(P, New_Custom_Running_Props) || P <- ["Status", "Loop", "Messages"]],
    ok.
    

get_custom_fmt(Status) -> lists:nth(5, element(4, Status)).

%% send_data(N, Coop_Head) ->
%%     [begin
%%          ?TM:send_data_msg(Coop_Head, 5),
%%          5 = receive Data -> Data end
%%      end || _N <- lists:seq(1,N)].
    
sys_statistics(_Config) ->
    {#coop_head{ctl_pid=Head_Ctl_Pid, data_pid=Head_Data_Pid} = Coop_Head,
     Root_Pid, #coop_node{ctl_pid=Node_Ctl_Pid, task_pid=Node_Task_Pid}} = start_head(),
    Procs = [Head_Ctl_Pid, Head_Data_Pid, Node_Ctl_Pid, Node_Task_Pid, Root_Pid],

    ok = ?TM:ctl_stats(Coop_Head, true, self()),
    [true = is_process_alive(P) || P <- Procs],
    {ok, Props1} = ?TM:ctl_stats(Coop_Head, get, self()),
    [0,0] = [proplists:get_value(P, Props1) || P <- [messages_in, messages_out]],
    ok = ?TM:send_data_msg(Coop_Head, 10),
    ok = ?TM:send_data_msg(Coop_Head, 11),
    ok = ?TM:send_data_msg(Coop_Head, 12),
    timer:sleep(50),
    {ok, Props2} = ?TM:ctl_stats(Coop_Head, get, self()),
    [3,3] = [proplists:get_value(P, Props2) || P <- [messages_in, messages_out]],
    ok = ?TM:ctl_stats(Coop_Head, false, self()),
    [true = is_process_alive(P) || P <- Procs],
    ok.

sys_log(_Config) ->
    {#coop_head{ctl_pid=Head_Ctl_Pid, data_pid=Head_Data_Pid} = Coop_Head,
     Root_Pid, #coop_node{ctl_pid=Node_Ctl_Pid, task_pid=Node_Task_Pid}} = start_head(),
    Procs = [Head_Ctl_Pid, Head_Data_Pid, Node_Ctl_Pid, Node_Task_Pid, Root_Pid],

    %% ok = ?TM:ctl_log_to_file(Coop_Head, "./coop.dump", self())
    ok = ?TM:ctl_log(Coop_Head, true, self()),
    {ok, []} = ?TM:ctl_log(Coop_Head, get, self()),
    [true = is_process_alive(P) || P <- Procs],
    ?TM:send_data_msg(Coop_Head, 5),
    {ok, Events} = ?TM:ctl_log(Coop_Head, get, self()),
    2 = length(Events),
    Ins = [{in,5}],
    Ins = [{Type,Num} || {{Type,Num}, _Flow, _Fun} <- Events],
    Outs = [{out,5}],
    Outs = [{Type,Num} || {{Type,Num,_Pid}, _Flow, _Fun} <- Events],
    ok = ?TM:ctl_log(Coop_Head, false, self()),
    [true = is_process_alive(P) || P <- Procs],
    ok.

%% sys_install(_Config) ->
%%     Coop_Node = #coop_node{task_pid=Node_Task_Pid} = setup_no_downstream(),
%%     Pid = spawn_link(fun() ->
%%                              %% Trace results...
%%                              receive {15, 30} -> ok;
%%                                       Bad_Result -> exit(Bad_Result)
%%                               after 2000 -> exit(timeout)
%%                               end,
                             
%%                              %% After trace uninstalled.
%%                              case receive Data -> Data after 200 -> timeout end of
%%                                  {data, 21} -> ok;
%%                                  Bad -> Msg = io_lib:format("Trace_Fn failed ~p",[Bad]),
%%                                         exit(lists:flatten(Msg))
%%                              end
%%                      end),
%%     F = fun
%%             ({Ins, Outs, 3}, _Any, round_robin) ->
%%                 Pid ! {Ins, Outs};
%%             ({Ins, Outs, Count}, {in, Amt}, round_robin) when is_integer(Amt) ->
%%                 {Ins+Amt, Outs, Count+1};
%%             ({Ins, Outs, Count}, {out, Amt, _Pid}, round_robin) when is_integer(Amt) ->
%%                 {Ins, Outs+Amt, Count};
%%             ({Ins, Outs, Count}, {in, {add_downstream, _Id}}, round_robin) ->
%%                 {Ins, Outs, Count};
%%             ({Ins, Outs, Count}, {in, {get_downstream, _Id}}, round_robin) ->
%%                 {Ins, Outs, Count};
%%             (_State, Unknown, _Extra) ->
%%                 Pid ! {unknown_msg_rcvd, Unknown}
%%         end,
%%     ok = ?TM:node_ctl_install_trace_fn(Coop_Node, {F, {0,0,0}}, self()),

%%     send_data(3, Coop_Node),
%%     timer:sleep(50),
%%     ok = ?TM:node_ctl_remove_trace_fn(Coop_Node, F, self()),
%%     ?TM:node_task_deliver_data(Node_Task_Pid, 7),
%%     _ = receive Data -> Pid ! {data, Data} after 50 -> 0 end,
%%     timer:sleep(1000).
