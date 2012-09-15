%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @reference The license is based on the template for Modified BSD from
%%%   <a href="http://opensource.org/licenses/BSD-3-Clause">OSI</a>
%%% @doc
%%%    Coop Head construct, manages data flow to the Coop Body.
%%%
%%%    Coop Head is built from a Ctl process and a Data process that
%%%    are used to prioritize control commands over data processing.
%%%    Messages in the data queue are sent synchronously to the
%%%    Root Pid which then relays them to the Coop Body. Control
%%%    messages are relayed without any synchronous flow restrictions.
%%%    By acking each data request, after it relays it to the body,
%%%    the Root Pid ensures that all Control messages can be seen ahead
%%%    of queued Data messages.
%%%
%%%    It is possible to send a data message on the control channel.
%%%    This serves as a high-priority bypass, but its use should be
%%%    rare. 
%%%
%%%    Excessive use of control messages will cause queueing at the
%%%    Root Pid rather than in another area of the system, resulting
%%%    in delayed responsiveness to command and control or OTP System
%%%    messages, as well as a lack of data throughput.
%%%
%%%    The Root Pid also responds to OTP System messages so it can
%%%    be suspended, resumed, debugged, traced and managed using OTP
%%%    tools. These are primarily used to restrict data flow when code
%%%    changes require it, or data in transit is too heavy.
%%%
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop_head).
-author('Jay Nelson <jay@duomark.com>').

-include("../erlangsp/include/license_and_copyright.hrl").

%% Graph API
-export([
         %% Create coop_head instances...
         new/2, get_kill_switch/1, 

         %% Send commands to coop_head control process...
         %% ctl_clone/1,
         stop/1, suspend_root/1, resume_root/1, format_status/1,
         %% ctl_trace/1, ctl_untrace/1,
         ctl_stats/3, ctl_log/3, ctl_log_to_file/3
         %% ctl_install_trace_fn/3, ctl_remove_trace_fn/3,
        ]).

%% Internal functions that are exported (not part of the external API)
-export([
         get_root_pid/1, set_root_node/2,

         %% Send commands to coop_head data task process...
         send_ctl_msg/2, send_ctl_change_timeout/2,
         send_data_msg/2, send_priority_data_msg/2,
         send_data_change_timeout/2
 ]).

%% Internal functions for spawned processes
-export([echo_loop/1]).

-include("coop.hrl").
-include("coop_dag.hrl").
-include("coop_head.hrl").

-define(CTL_MSG_TIMEOUT,  500).
-define(SYNC_MSG_TIMEOUT, none).
-define(SYNC_RCV_TIMEOUT, 2000).


%%----------------------------------------------------------------------
%% External interface for sending ctl/data messages
%%----------------------------------------------------------------------
-spec send_ctl_msg(coop_head(), any()) -> ok.
-spec send_ctl_change_timeout(coop_head(), none | pos_integer()) -> ok.
-spec send_data_msg(coop_head(), any()) -> ok.
-spec send_priority_data_msg(coop_head(), any()) -> ok.
-spec send_data_change_timeout(coop_head(), none | pos_integer()) -> ok.

-spec get_kill_switch(coop_head()) -> pid().
-spec get_root_pid(coop_head()) -> pid() | none.

-spec set_root_node(coop_head(), coop_node()) -> boolean().

-spec stop(coop_head()) -> ok.
-spec suspend_root(coop_head()) -> ok.
-spec resume_root(coop_head()) -> ok.
-spec format_status(coop_head()) -> ok.

-spec ctl_stats(coop_head(), boolean() | get, pid()) -> ok | {ok, list()}.

send_ctl_msg_internal (#coop_head{ctl_pid=Head_Ctl_Pid}, Msg) -> Head_Ctl_Pid  ! {?DAG_TOKEN, ?CTL_TOKEN,  Msg}, ok.
send_data_msg_internal(#coop_head{data_pid=Head_Data_Pid}, Msg) -> Head_Data_Pid ! {?DAG_TOKEN, ?DATA_TOKEN, Msg}, ok.
    
send_ctl_msg(Coop_Head, Msg) -> send_ctl_msg_internal(Coop_Head, Msg).
send_ctl_msg(Coop_Head, Msg, Flag, From) -> send_ctl_msg_internal(Coop_Head, {Msg, Flag, From}).
send_ctl_change_timeout(Coop_Head, New_Timeout) -> send_ctl_msg_internal(Coop_Head, {change_timeout, New_Timeout}).
    
send_data_msg(Coop_Head, Msg) -> send_data_msg_internal(Coop_Head, Msg).
send_priority_data_msg(#coop_head{ctl_pid=Head_Ctl_Pid}, Msg) -> Head_Ctl_Pid  ! {?DAG_TOKEN, ?DATA_TOKEN, Msg}, ok.
send_data_change_timeout(#coop_head{data_pid=Head_Data_Pid}, New_Timeout) ->
    Head_Data_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, {change_timeout, New_Timeout}},
    ok.

stop(Coop_Head)          -> send_ctl_msg(Coop_Head, {stop}).
suspend_root(Coop_Head)  -> send_ctl_msg(Coop_Head, {suspend}).
resume_root(Coop_Head)   -> send_ctl_msg(Coop_Head, {resume}).
format_status(Coop_Head) -> send_ctl_msg(Coop_Head, {format_status}).

ctl_stats(Coop_Head, Flag, From) ->
    Ref = make_ref(),
    send_ctl_msg(Coop_Head, stats, Flag, {Ref, From}),
    wait_ctl_response(stats, Ref).

ctl_log(Coop_Head, Flag, From) ->
    Ref = make_ref(),
    send_ctl_msg(Coop_Head, log, Flag, {Ref, From}),
    wait_ctl_response(log, Ref).

ctl_log_to_file(Coop_Head, Flag, From) ->
    Ref = make_ref(),
    send_ctl_msg(Coop_Head, log_to_file, Flag, {Ref, From}),
    wait_ctl_response(log_to_file, Ref).

get_root_pid(Coop_Head) ->
    Ref = make_ref(),
    send_ctl_msg(Coop_Head, {get_root_pid, {Ref, self()}}),
    wait_ctl_response(get_root_pid, Ref).

get_kill_switch(Coop_Head) ->
    Ref = make_ref(),
    send_ctl_msg(Coop_Head, {get_kill_switch, {Ref, self()}}),
    wait_ctl_response(get_kill_switch, Ref).

wait_ctl_response(Type, Ref) ->
    receive {Type, Ref, Info} -> Info
    after ?SYNC_RCV_TIMEOUT -> timeout
    end.

set_root_node({coop_head, _Head_Ctl_Pid, _Head_Data_Pid} = Coop_Head,
              {coop_node, _Node_Ctl_Pid, _Node_Task_Pid} = Coop_Node) ->
    Ref = make_ref(),
    send_ctl_msg(Coop_Head, {set_root_node, Coop_Node, {Ref, self()}}),
    wait_ctl_response(set_root_node, Ref).


%%----------------------------------------------------------------------
%% Create a new coop_head. A coop_head is represented by a pair of
%% pids: a control process and a data process.
%%----------------------------------------------------------------------
-spec new(pid(), pid()) -> coop_head().

new(Kill_Switch, Coop_Node)
  when is_pid(Kill_Switch) ->

    %% Start the root and data processes...
    Root_Pid = make_root_pid(Coop_Node),
    Ctl_Pid  = make_ctl_pid (Root_Pid, ?CTL_MSG_TIMEOUT),
    Data_Pid = make_data_pid(Root_Pid, ?SYNC_MSG_TIMEOUT),

    %% Start support processes and initialize the control process internal state...
    {Trace_Pid, Log_Pid, Reflect_Pid} = make_support_pids(),
    Ctl_State = #coop_head_state{kill_switch=Kill_Switch, ctl=Ctl_Pid, data=Data_Pid,
                                 root=Root_Pid, log=Log_Pid, trace=Trace_Pid,
                                 reflect=Reflect_Pid, coop_root_node=Coop_Node},
    Ctl_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, {init_state, Ctl_State}},

    %% Link all pids to the Kill_Switch and return the coop_head.
    Kill_Link_Args = [Ctl_Pid, Data_Pid, Root_Pid, Trace_Pid, Log_Pid, Reflect_Pid],
    coop_kill_link_rcv:link_to_kill_switch(Kill_Switch, Kill_Link_Args),
    #coop_head{ctl_pid=Ctl_Pid, data_pid=Data_Pid}.


make_root_pid(none) ->
    proc_lib:spawn(coop_head_root_rcv, sync_pass_thru_loop, [none]);
make_root_pid(#coop_node{} = Coop_Node) ->
    proc_lib:spawn(coop_head_root_rcv, sync_pass_thru_loop, [Coop_Node]).

make_data_pid(Root_Pid, Timeout) when is_pid(Root_Pid) ->
    proc_lib:spawn(coop_head_data_rcv, one_at_a_time_loop, [Root_Pid, Timeout]).

make_ctl_pid(Root_Pid, Timeout) when is_pid(Root_Pid) ->
    proc_lib:spawn(coop_head_ctl_rcv, msg_loop, [{}, Root_Pid, Timeout]).

make_support_pids() ->
    Trace_Pid = proc_lib:spawn(?MODULE, echo_loop, ["HTRC"]),
    [Log_Pid, Reflect_Pid]
        = [proc_lib:spawn(?MODULE, echo_loop, [Type]) || Type <- ["HLOG", "HRFL"]],
    {Trace_Pid, Log_Pid, Reflect_Pid}.


%%----------------------------------------------------------------------
%% Coop Head receive loops for support pids.
%%----------------------------------------------------------------------
-spec echo_loop(string()) -> no_return().

%% Trace, Log and Reflect process receive loop
echo_loop(Type) ->
    receive
        {stop} -> exit(stopped);
        Any -> error_logger:info_msg("~p ~p ~p: ~p~n", [?MODULE, Type, self(), Any])
    end,
    echo_loop(Type).
