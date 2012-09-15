%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @reference The license is based on the template for Modified BSD from
%%%   <a href="http://opensource.org/licenses/BSD-3-Clause">OSI</a>
%%% @doc
%%%    Co-operating Process instances modeled on coop_flow graphs.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop).
-author('Jay Nelson <jay@duomark.com>').

-include("../erlangsp/include/license_and_copyright.hrl").

%% External API
-export([
         new_pipeline/2, new_fanout/3,
         make_dag_node/4, make_dag_node/5,
         get_head_kill_switch/1, get_body_kill_switch/1,
         is_live/1, relay_data/2, relay_high_priority_data/2
        ]).

%% For testing purposes only.
-export([pipeline/4, fanout/5]).

-include("coop.hrl").
    

%%----------------------------------------------------------------------
%% Create a Co-op (with a single Co-op Instance)
%%
%% PIPELINE:
%%   A chain of Co-op Nodes, ordered left to right. Data is
%%   received at the left Node, transformed at each Node and emerges
%%   normally at the right Node ending in transfer to the Co-op
%%   Receiver.
%%
%% FANOUT:
%%   A single Co-op Node which has 2 or more immediate downstream
%%   Nodes. Data must flow through the single entry point, but may
%%   then be directed to any one or more of the children Nodes.
%%----------------------------------------------------------------------
-spec new_pipeline([#coop_dag_node{}], coop_receiver()) -> coop() | false.
-spec new_fanout(#coop_dag_node{}, [#coop_dag_node{}], coop_receiver()) -> coop() | false.

new_pipeline([#coop_dag_node{} | _More] = Node_Fns, Receiver) ->
    Head_Kill_Switch = coop_kill_link_rcv:make_kill_switch(),
    Coop_Head = coop_head:new(Head_Kill_Switch, none),
    Body_Kill_Switch = coop_kill_link_rcv:make_kill_switch(),
    {Coop_Root_Node, Template_Graph, Pipeline_Graph}
        = pipeline(Coop_Head, Body_Kill_Switch, Node_Fns, Receiver),
    Coop_Instance = make_coop_instance(1, Coop_Head, Coop_Root_Node, Pipeline_Graph),
    finish_new_coop(Coop_Instance, Head_Kill_Switch, Body_Kill_Switch, Template_Graph).
    
new_fanout(#coop_dag_node{} = Router_Fn, [#coop_dag_node{} | _More] = Workers, Receiver) ->
    Head_Kill_Switch = coop_kill_link_rcv:make_kill_switch(),
    Coop_Head = coop_head:new(Head_Kill_Switch, none),
    Body_Kill_Switch = coop_kill_link_rcv:make_kill_switch(),
    {Coop_Root_Node, Template_Graph, Fanout_Graph}
        = fanout(Coop_Head, Body_Kill_Switch, Router_Fn, Workers, Receiver),
    Coop_Instance = make_coop_instance(1, Coop_Head, Coop_Root_Node, Fanout_Graph),
    finish_new_coop(Coop_Instance, Head_Kill_Switch, Body_Kill_Switch, Template_Graph).
    
finish_new_coop(#coop_instance{head=Coop_Head, body=Coop_Root_Node} = Coop_Instance,
                Head_Kill_Switch, Body_Kill_Switch, Template_Graph) ->
    case coop_head:set_root_node(Coop_Head, Coop_Root_Node) of
        true  -> #coop{instances=Coop_Instance, dataflow=broadcast, dag_template=Template_Graph};
        false ->
            exit(Body_Kill_Switch, kill),
            exit(Head_Kill_Switch, kill),
            false
    end.


%%----------------------------------------------------------------------
%% Functions for making Co-op records
%%----------------------------------------------------------------------
-spec make_coop_instance(integer(), coop_head(), coop_body(), digraph()) -> coop_instance() | {error, invalid_head_or_body}.
-spec make_dag_node(string() | atom(), coop_init_fn(), coop_task_fn(), coop_data_options()) -> coop_dag_node().
-spec make_dag_node(string() | atom(), coop_init_fn(), coop_task_fn(), coop_data_options(), data_flow_method()) -> coop_dag_node() | {error, {invalid_data_flow_method, any()}}.

make_coop_instance(Id, Head, Body, Dag)
  when is_integer(Id), Id > 0 ->
    case {Head, Body} of
        {none,         none}         -> #coop_instance{id=Id, head=Head, body=Body, dag=Dag};
        {none,         #coop_node{}} -> #coop_instance{id=Id, head=Head, body=Body, dag=Dag};
        {#coop_head{}, none}         -> #coop_instance{id=Id, head=Head, body=Body, dag=Dag};
        {#coop_head{}, #coop_node{}} -> #coop_instance{id=Id, head=Head, body=Body, dag=Dag};
        _Other -> {error, invalid_head_or_body}
    end.

make_dag_node(Name, Init_Fn, Task_Fn, Opts) ->
    make_dag_node(Name, Init_Fn, Task_Fn, Opts, broadcast).

make_dag_node(Name, {_Imod, _Ifun, _Iargs} = Init_Fn, {_Mod, _Fun} = Task_Fn, Opts, Data_Flow)
  when is_atom(_Imod), is_atom(_Ifun), is_atom(_Mod), is_atom(_Fun), is_list(Opts) ->
    case length([T || T <- ?DATAFLOW_TYPES, Data_Flow =:= T]) of
        1 -> #coop_dag_node{name=Name, label=#coop_node_fn{init=Init_Fn, task=Task_Fn,
                                                           options=Opts, flow=Data_Flow}};
        0 -> {error, {invalid_data_flow_method, Data_Flow}}
    end.

    
%%----------------------------------------------------------------------
%% Get a reference to the Co-op Head or Co-op Body kill switch Pid.
%%----------------------------------------------------------------------
get_head_kill_switch(Coop_Head) ->
    coop_head:get_kill_switch(Coop_Head).

get_body_kill_switch(Coop_Node) ->
    coop_node:get_kill_switch(Coop_Node).


%%----------------------------------------------------------------------
%% Check if a Coop_Head, Coop_Node or raw Pid is alive.
%%----------------------------------------------------------------------
is_live(none) -> false;
is_live(Pid) when is_pid(Pid) -> is_process_alive(Pid);
is_live(#coop_head{ctl_pid=Ctl_Pid, data_pid=Data_Pid}) ->
    is_process_alive(Ctl_Pid) andalso is_process_alive(Data_Pid);
is_live(#coop_node{ctl_pid=Ctl_Pid, task_pid=Task_Pid}) ->
    is_process_alive(Ctl_Pid) andalso is_process_alive(Task_Pid);
is_live(#coop_instance{head=Coop_Head}) ->
    is_live(Coop_Head);
is_live(#coop{instances=#coop_instance{head=Coop_Head}}) ->
    is_live(Coop_Head);
is_live(#coop{instances=Ets_Table}) ->
    lists:all([is_live(Inst) || Inst <- ets:tab2list(Ets_Table)]).

    

%%----------------------------------------------------------------------
%% Data messaging to Co-op Instances
%%----------------------------------------------------------------------

%% Relay data is used to deliver Node output to Co-op, Co-op Instance,
%% Co-op Head, Co-op Node or raw Pid.
relay_data(#coop{instances=Instances}, Data) ->
    case Instances of
        #coop_instance{} -> relay_data(Instances, Data);
        _Ets_Table -> not_implemented_yet
    end,
    ok;
relay_data(#coop_instance{head=none}, _Data) ->
    ok;
relay_data(#coop_instance{head=Coop_Head}, Data) ->
    coop_head:send_data_msg(Coop_Head, Data);
relay_data(#coop_head{} = Coop_Head, Data) ->
    coop_head:send_data_msg(Coop_Head, Data),
    ok;
relay_data(#coop_node{} = Coop_Node, Data) ->
    coop_node:node_task_deliver_data(Coop_Node, Data),
    ok;
relay_data(Pid, Data) when is_pid(Pid) ->
    Pid ! Data,
    ok;
relay_data(none, _Data) ->
    ok.
    

%% High priority only works for a Coop_Head, bypassing all pending Data requests.
relay_high_priority_data(#coop_head{} = Coop_Head, Data) ->
    coop_head:send_priority_data_msg(Coop_Head, Data),
    ok;
relay_high_priority_data(Dest, Data) ->
    relay_data(Dest, Data),
    ok.


%%----------------------------------------------------------------------
%% Pipeline patterns (can only use serial broadcast dataflow method)
%%----------------------------------------------------------------------
pipeline(Coop_Head, Kill_Switch, [#coop_dag_node{} | _More] = Node_Fns, Receiver) ->
    Pipeline_Graph = coop_flow:pipeline(Node_Fns),
    Vertex_List = [digraph:vertex(Pipeline_Graph, Name) || #coop_dag_node{name=Name} <- Node_Fns],
    pipeline(Coop_Head, Kill_Switch, Pipeline_Graph, Vertex_List, Receiver).

pipeline(Coop_Head, Kill_Switch, Pipeline_Template_Graph, Left_To_Right_Stages, Receiver) ->
    Coops_Graph = digraph:new([acyclic]),
    digraph:add_vertex(Coops_Graph, outbound, Receiver),
    {First_Stage_Coop_Node, _Second_Stage_Vertex_Name} =
        lists:foldr(fun(Node_Name_Fn_Pair, {_NextStage, _Downstream_Vertex_Name} = Acc) ->
                            spawn_pipeline_stage(Coop_Head, Kill_Switch, Coops_Graph, Node_Name_Fn_Pair, Acc)
                    end, {Receiver, outbound}, Left_To_Right_Stages),

    %% Return the first coop_node, template graph and live coop_node graph.
    {First_Stage_Coop_Node, Pipeline_Template_Graph, Coops_Graph}.

spawn_pipeline_stage(Coop_Head, Kill_Switch, Graph,
                     {Name, #coop_node_fn{init=Init_Fn, task=Task_Fn, options=Opts}},
                     {Receiver, Downstream_Vertex_Name}) ->
    Coop_Node = coop_node:new(Coop_Head, Kill_Switch, Task_Fn, Init_Fn, Opts),  % Defaults to broadcast out
    coop_node:node_task_add_downstream_pids(Coop_Node, [Receiver]),             % And just 1 receiver
    digraph:add_vertex(Graph, Name, Coop_Node),
    digraph:add_edge(Graph, Name, Downstream_Vertex_Name),
    {Coop_Node, Name}.
    

%%----------------------------------------------------------------------
%% Fanout patterns
%%----------------------------------------------------------------------
fanout(Coop_Head, Kill_Switch, #coop_dag_node{name=Inbound} = Router_Fn,
       [#coop_dag_node{} | _More] = Workers, Receiver) ->
    Fanout_Graph = coop_flow:fanout(Router_Fn, Workers, Receiver),
    fanout(Inbound, Coop_Head, Kill_Switch, Fanout_Graph).
    
fanout(Inbound, Coop_Head ,Kill_Switch, Fanout_Template_Graph) ->
    Coops_Graph = digraph:new([acyclic]),
    {Inbound, #coop_node_fn{init=Inbound_Init_Fn, task=Inbound_Task_Fn, options=Opts, flow=Inbound_Dataflow}}
        = digraph:vertex(Fanout_Template_Graph, Inbound),
    Inbound_Node = coop_node:new(Coop_Head, Kill_Switch, Inbound_Task_Fn, Inbound_Init_Fn, Opts, Inbound_Dataflow),
    digraph:add_vertex(Coops_Graph, Inbound, Inbound_Node),
    {Has_Fan_In, Rcvr} = case digraph:vertex(Fanout_Template_Graph, outbound) of
                             false -> {false, none};
                             {outbound, Receiver} ->
                                 digraph:add_vertex(Coops_Graph, outbound, Receiver),
                                 {true, Receiver}
                         end,
    Worker_Nodes = [add_fanout_worker_node(Coop_Head, Kill_Switch, Inbound, Has_Fan_In, Rcvr, Fanout_Template_Graph, Vertex_Name, Coops_Graph)
                    || Vertex_Name <- digraph:out_neighbours(Fanout_Template_Graph, Inbound)],
    coop_node:node_task_add_downstream_pids(Inbound_Node, Worker_Nodes),
    {Inbound_Node, Fanout_Template_Graph, Coops_Graph}.

add_fanout_worker_node(Coop_Head, Kill_Switch, Inbound, Has_Fan_In, Receiver, Template_Graph, Vertex_Name, Coops_Graph) ->
    {Vertex_Name, #coop_node_fn{init=Init_Fn, task=Task_Fn, options=Opts}}
        = digraph:vertex(Template_Graph, Vertex_Name),
    Coop_Node = coop_node:new(Coop_Head, Kill_Switch, Task_Fn, Init_Fn, Opts),  % Defaults to broadcast
    digraph:add_vertex(Coops_Graph, Vertex_Name, Coop_Node),
    digraph:add_edge(Coops_Graph, Inbound, Vertex_Name),
    Has_Fan_In andalso begin
                           digraph:add_edge(Coops_Graph, Vertex_Name, outbound),
                           coop_node:node_task_add_downstream_pids(Coop_Node, [Receiver])
                       end,
    Coop_Node.
    
