%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%    Default receive loop for coop_node data.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop_node_ctl_rcv).

-include("../erlangsp/include/license_and_copyright.hrl").
-author(jayn).

%% Graph API
-export([node_ctl_loop/6]).

-include("coop_dag.hrl").
-include("coop_node.hrl").

%%----------------------------------------------------------------------
%% Coop Node data is executed using Node_Fn and the results are
%% passed to one or more of the downstream workers.
%%----------------------------------------------------------------------
-spec node_ctl_loop(pid(), pid(), task_function(), pid(), pid(), pid()) -> no_return().

node_ctl_loop(Kill_Switch, Task_Pid, Node_Fn, Trace_Pid, Log_Pid, Reflect_Pid) ->
    node_ctl_loop(#coop_node_state{kill_switch=Kill_Switch, ctl=self(), task=Task_Pid,
                                   task_fn=Node_Fn, trace=Trace_Pid, log=Log_Pid, reflect=Reflect_Pid}).

node_ctl_loop(#coop_node_state{task=Task_Pid, trace=Trace_Pid} = Coop_Node_State) ->
    receive
        %% Commands for controlling the entire Coop_Node element...
        {?DAG_TOKEN, ?CTL_TOKEN, stop}    -> exit(stopped);
        {?DAG_TOKEN, ?CTL_TOKEN, clone}   -> node_clone(Coop_Node_State);

        %% Commands for controlling/monitoring the Task_Pid...
        {?DAG_TOKEN, ?CTL_TOKEN, suspend } -> sys:suspend(Task_Pid);
        {?DAG_TOKEN, ?CTL_TOKEN, resume  } -> sys:resume(Task_Pid);
        {?DAG_TOKEN, ?CTL_TOKEN, trace   } -> erlang:trace(Task_Pid, true,  trace_options(Trace_Pid));
        {?DAG_TOKEN, ?CTL_TOKEN, untrace } -> erlang:trace(Task_Pid, false, trace_options(Trace_Pid));

        {?DAG_TOKEN, ?CTL_TOKEN, log,         Flag,  {Ref, From}} -> From ! {node_ctl_log, Ref, sys:log(Task_Pid, Flag)};
        {?DAG_TOKEN, ?CTL_TOKEN, log_to_file, File,  {Ref, From}} -> From ! {node_ctl_log_to_file, Ref, sys:log_to_file(Task_Pid, File)};
        {?DAG_TOKEN, ?CTL_TOKEN, stats,       Flag,  {Ref, From}} -> From ! {node_ctl_stats, Ref, sys:statistics(Task_Pid, Flag)};

        {?DAG_TOKEN, ?CTL_TOKEN, install_trace_fn, FInfo, {Ref, From}} -> From ! {node_ctl_install_trace_fn, Ref, sys:install(Task_Pid, FInfo)};
        {?DAG_TOKEN, ?CTL_TOKEN, remove_trace_fn, FInfo, {Ref, From}}  -> From ! {node_ctl_remove_trace_fn,  Ref, sys:remove(Task_Pid, FInfo)};

        %% All others are unknown commands, just unqueue them.
        _Skip_Unknown_Msgs                -> do_nothing
    end,
    node_ctl_loop(Coop_Node_State).

node_clone(#coop_node_state{} = _Coop_Node_State) -> ok.
trace_options(Tracer_Pid) -> [{tracer, Tracer_Pid}, send, 'receive', procs, timestamp].
