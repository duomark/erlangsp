Co-op Library (Cooperating Processes)
=====================================

A Co-op is a collection of processes arranged in a Directed Acyclic Graph (using Erlang's digraph module). Nodes of the graph are processes; edges represent messaging from an upstream process to a downstream process. The structure is maintained as a static digraph template when initially specified, a digraph containing live erlang processes at each graph node, and the same erlang processes connected via internal state references to downstream pids such that messages are sent directly to known pids without name lookup in the normal dataflow case.

```
Here is a simple example of a Pipeline Co-op calculating 3*(x+2) - Number_of_Data_Items_Seen:

-module(example).
-export([plus2/2, times3/2, minus_seen/2]).

plus2 (Ignored_State, X) -> {Ignored_State, X+2}.
times3(Ignored_State, X) -> {Ignored_State, X*3}.
minus_seen(Num_Seen = _State, X) -> {Num_Seen+1, X-Num_Seen}.

%% Pipeline_Fns is equivalent to [ {example, plus2}, {example, times3}, {example, minus5} ]
%% Corresponding digraph is:  plus2 => times3 => minus_seen => Receiver

Coop_Head = coop:new_pipeline(Pipeline_Fns, self()),
coop:relay_data(Coop_Head, 4),
receive Any -> Any end.
```

Setting up the constituent pipeline functions involves filling in records with an init function for the initial State (which is consistently ignored in this example) plus setting the function task to execute. The call to coop:new_pipeline/2 creates a graph and a process for each stage of the pipeline, with each one executing the corresponding exported function. The data relayed in (4 in this case) is passed through the first stage (4+2 => 6) and then to the next stage (6*3 => 18) and finally to the last stage (18-0 => 18, while the State is incremented by one so that on the next pass it will be 1) with the result sent as a message to the Receiver which was set to self(), where we can safely fetch it from the erlang message queue. If the calculation were change to be 3*(x-Num_Seen) + 2 we could just rearrange the order of the functions in the pipeline and make a new instance of the Co-op to perform the new calculation. The focus is on representing the computation as the flow of data from function to function, allowing the VM to execute the functions concurrently on different problem instances simultaneously.

In a pipeline the only choice is to serially pass the data from stage to stage. The current version also allows a fanout rather than a pipeline, in which case the data can be sent to one of the children nodes, or all of the children nodes.

Co-op Structure
===============

A Co-op is a single computation entity which can only accurately compute if all its constituent process components are present and operating normally. If any process fails, the entire Co-op network fails and is removed from memory in the erlang node. This is accomplished via a Kill_Switch process per Co-op which is connected to all processes used within a single Co-op Body (a second Kill_Switch can be maintained for just the Co-op Head so that the loss of a Body does not eliminate the Co-op Head and all pending messages for the Co-op).

The Co-op Head serves as the publicly visible access point for delivering data to the Co-op (and unfortunately a potetially fatal choke point for certain traffic patterns) but it allows the passing of both control and data to the Co-op via dedicated processes, one for each type of message. Internally, both the data queue and the control queue are delivered to the Root process, which then forwards them to the Co-op Body's Root Co-op Node. Data messages are sent synchronously so that only one at a time may enter the Co-op Body, but control messages are sent asynchronously, so they get delivered more quickly by bypassing all pending data messages. Control messages should be infrequent and data messages should be very nearly 100% of the traffic to a Co-op. It is possible to send "high priority" data messages to a Co-op. Internally, the Data is sent via the control process so it bypasses all pending Data messages. Overuse of this option will flood the Root Pid with many messages, when its Erlang Mailbox should generally have just one Data message and one Control message at any given time. The Control Pid should generally have an empty queue, and the Data Pid may have many messages under load.


```
+------------+
|  Control   |-----------|
+------------+           V
                  +--------------+       +------------+
                  |   Root Pid   |------>| Root Node  |--->
                  +--------------+       +------------+
+------------+           ^
|  Data      |-----------|
+------------+
```


The Co-op Body is where computation takes place. The primary goal of the library is to encourage the use of more processes, but to do so using a principled and structured approach. If the VM is running on a chip with 10K cores, the program should have 50K or more processes to take full advantage of the hardware's capabilitites. The general strategy is to push towards one process per function (although internally the Coop Node will use 6 or more processes to fully represent the computation including realtime tap and trace, GUI reflection and other advanced options). The architect should use functional decomposition with the goals of:

  1. Isolating subsystems and computational elements from failure
  1. Encouraging overlapped computation (concurrent calculations) as much as possible
  1. Expressing the algorithm as a traceable network of elements
  1. Allowing variable data traffic and adaptive subsystems

Many problems or transactions should be flowing through the system simultaneously, each one following an algorithmic path that touches on a sequence of processes and functions. Concurrency is not used to speed up a single task, but to allow many similar tasks to follow different solution paths at the same time, and also to encourage algorithmic decomposition for better understanding, tracing and debugging of logic. When performance is an issue, graphs can be transformed and processes can be merged in real time, to produce a more efficient computation at the expense of clarity of intermediate results and traceability of logic.

Any Coop Node, and quite often the final tier of a graph, can emit results as one or more messages. Coop Nodes may deliver their messages to normal Erlang pids, other Coop Nodes or to Coops via their Coop Heads. A complete system snaps together graphs in a way similar to Lego(tm) bricks. Since Coops are implemented on the assumption that they are directed and acyclic, intermediary processes are normally used to introduce loops in the system. Loops can cause non-termination or just a multiplicative flood of message traffic, so care must be taken to use loops appropriately. There is currently a shortcut that allows access to the Head of the currently executing Coop, so it is prossible to emit messages without an intermediary process but it must be done programmatically rather than declaratively through the graph structure.

Version 0.0.1 Code Layout
=========================

The directory erlangsp/apps/coop/ contains the source and include code for the Co-op library. The coop.app.src specification does not start any application, it just bundles the modules into a library that can be included in another application. The src code is organized into the following modules:

```
  coop: Create Co-ops (currently pipeline or fan out/fan in patterns only)
  coop_flow: Construct and return digraph instances
  coop_head: Interact with the head of a Co-op
  coop_head_ctl_rcv_erl: The message receive loop for the Co-op Head Control process
  coop_head_data_rcv_erl: The message receive loop for the Co-op Head Data process
  coop_head_root_rcv_erl: The message receive loop for the Co-op Head Root process
  coop_node: Interact with a body node of a Co-op
  coop_node_ctl_rcv_erl: The message receive loop for the Co-op Node Control process
  coop_node_data_rcv_erl: The message receive loop for the Co-op Node Data process
  coop_node_util: Miscellaneous Co-op Node functions
```

The erlangsp/apps/coop/include directory contains:

```
  coop_dag.hrl: Type definitions and records for Co-ops
  coop_head.hrl: The internal state record definition for a coop_head instance
  coop_node.hrl: The internal state record definition for a coop_node instance
```

Version 0.0.1 Data Structures
=============================

A Co-op consists of a Co-op Head and a Co-op Body (which is made up of one or more Co-op Nodes with message channels connected according to the computational graph structure from which it was constructed). Data is delivered to the Co-op Head, it flows to the Root Co-op Body Node (all co-op graphs emanate from a single root node). The Co-op module is a convenient wrapper and the primary external API, but Co-op Head and Co-op Node may need to be contacted directly.

Co-op API
=========

The Co-op external interface mainly allows creating and sending data to a Co-op:

```
  new_pipeline(Pipe_Stage_Fns, Receiver)

     Creates a pipeline graph and populates it with one process per function specified
     in the Pipe_Stage_Fns (see #coop_dag_node{} below). The Receiver can be a pid(),
     a coop_head(), a coop_node(), or 'none'.

  new_fanout(Router_Fn, Worker_Fns, Receiver)

     Creates a fanout graph with an optional fan in to the Receiver and populates it
     with one process per function specified in the Worker_Fns (see #coop_dag_node{}
     below). The Receiver is the same fomrat as in new_pipeline, while the Router_Fn
     is also a #coop_dag_node{}. The Router_Fn determines the distribution method for
     the fanout: either round_robin, random or broadcast.

  get_kill_switch(Coop_Head): Gets the Kill_Switch pid for the Co-op Head
  relay_data(Receiver, Data): Sends a Data message to pid(), coop_head() or coop_node()
  relay_high_priority_data(Coop_Head, Data): Sends a Data message via Coop_Head_Ctl pid
```

coop_dag.hrl defines the records used in a Co-op. The #coop_dag_node{} is used to define a graph node. The generated graph could have a Name for each Node, but must have a Label which contains an executable function reference which will execute inside the process corresponding to the graph node.

The record structure is as follows:

```
  name: The name of the graph node, mainly for documentation purposes.
  label: A #coop_node_fn{} to identify the functionality and dataflow of the node.
```

The #coop_node_fn{} structure is:

```
  init: {Mod, Fun, Args} for the initial internal state of a Coop_Node, called as Mod:Fun(Args)
  task: {Mod, Fun} for the computation performed in a Coop_Node, called as Mod:Fun(State, Data)
  flow: round_robin | random | broadcast to identify fanout policy
```

When a Co-op Node is created, it is initialized with a State which is passed to the receive loop. When a data message arrives, the receive loop performs:

```
  Task_Module:Task_Function(State, Data) -> {New_State, Result}
```

The receive loop is called with New_State and the result is delivered to one or more downstream receivers based on the dataflow policy:

```
  round_robin: the next fanout node when cycling through all listed
  random: a random fanout node of all listed
  broadcast: all fanout nodes listed
```

In the case of a pipeline, the dataflow policy defaults to broadcast and there is only one downstream node.

Co-op Head
==========

A Co-op Head is a single entity with 2 externally visible processes and 1 internally hidden process (the number of internal processes will increase when tracing, logging and display are enabled).

```
  Identifier:  {coop_head, Head_Ctl_Pid, Head_Data_Pid}
  Head_Ctl_Pid: normal Erlang pid, only messages the Coop Head Root asynchronously
  Head_Data_Pid: normal Erlang pid, only messages the Coop Head Root synchronously
  Coop Head Root: normal Erlang pid, only messages the Coop Root Node asynchronously
```

The following coop_head exported functions are the primary ones to use:

```
  new(Kill_Switch, Coop_Root_Node): create a new Coop Head hooked to Coop_Root_Node
  get_kill_switch(Coop_Head): return the pid of the Coop Head Kill_Switch
```

The following coop_head exported functions are used for sys style debugging / tracing:

```
  stop(Coop_Head): Terminates the Coop_Head_Root pid, which will kill the Co-op
  suspend_root(Coop_Head): Issues a sys:suspend to the Coop_Head_Root pid
  resume_root(Coop_Head): Issues a sys:resume to the Coop_Head_Root pid
  format_status(Coop_Head): Returns the status of the Coop_Head_Root pid's internal state
  ctl_stats(Coop_Head, Flag, From): Issues sys:statistics to be delivered to From
  ctl_log(Coop_Head, Flag, From): Issues sys:log to be delivered to From
  ctl_log_to_file(Coop_Head, Flag, From): Issues sys:log_to_file to be delivered to From
```

Co-op Node
==========

A Co-op Node is a single entity with 2 externally visible processes and multiple internally hidden process.

```
  Identifier:  {coop_node, Node_Ctl_Pid, Node_Task_Pid}
  Node_Ctl_Pid: normal Erlang pid, handles control messages to the Co-op Node
  Node_Data_Pid: normal Erlang pid, executes task function on Co-op Node Data arriving
```

Normally (99.99% of the time) there is no need to access a Co-op Node directly. The built-in data delivery and execution mechanisms allow data to flow from the Co-op Head through the relevant nodes of the Co-op Body executing the task function on each data element arriving.

The following coop_node exported functions are the primary ones to use if you are debugging erlangsp or a specific Co-op Node function that is broken:

```
  new(Kill_Switch, Node_Fn, Init_Fn): create a coop_node instance with 'broadcast' dataflow
  new(Kill_Switch, Node_Fn, Init_Fn, Data_Flow_Method): create a coop_node instance
```

To diagnose messaging issues, access to the downstream receivers may be useful:

```
  node_task_get_downstream_pids(Coop_Node): list of pid(), coop_head(), coop_node() or 'none'
  node_task_add_downstream_pids(Coop_Node, Receivers): add to downstream list
```

The following coop_node exported functions are used for sys style debugging / tracing:

```
  node_ctl_stop(Coop_Node): Terminate this Coop Node and take down the whole Coop
  node_ctl_suspend(Coop_Node): Issue sys:suspend to Node_Task_Pid
  node_ctl_resume(Coop_Node): Issue sys:resume to Node_Task_Pid
  node_ctl_trace(Coop_Node): Issue sys:trace to Node_Task_Pid (in/out messages)
  node_ctl_untrace(Coop_Node): Issue sys:untrace to Node_Task_Pid
  node_ctl_stats(Coop_Node, Flag, From): Issue sys:stats to Node_Task_Pid
  node_ctl_log(Coop_Node, Flag, From): Issue sys:log to Node_Task_Pid
  node_ctl_log_to_file(Coop_Node, Flag, From): Issue sys:log_to_file to Node_Task_Pid
  node_ctl_install_trace_fn(Coop_Node, {Func, Func_State), From): Issue sys:install to Node_Task_Pid
  node_ctl_remove_trace_Fn(Coop_Node, Func, From): Issue sys:remove to Node_Task_Pid
```

Version 0.0.1 Graph Structures
==============================

The following graph structures are supported:

```
  1. Pipeline - multiple functions executed serially, one process per function
  1. Fanout - a single router leading to multiple worker processes
```

The fanout pattern can optional fan in to a single receiver. The dataflow style for a Pipeline defaults to 'broadcast' with a special optimization strategy for deliver data downstream when there is only one downstream receiver. The dataflow styles for Fanout can be round_robin, random or broadcast. On fan in, the dataflow parameter is ignored and the data is delivered to the single receiver.

In all cases, the task functions must accept M:F(State, Data) and must return {New_State, Result}.
