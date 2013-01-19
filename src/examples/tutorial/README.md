TUTORIAL
========

This tutorial gives a brief introduction to Erlang/SP. It describes the features of the library, gives brief examples of their use and describes what capabilities they enable in a larger system.

CO-OPS (Co-operating Processes)
===============================

Co-ops are used to define a graph computation or network of processes. A co-op is an erlang digraph where nodes are processes and edges are one-way communication channels between processes. Data is intended to flow downstream, being transformed by the functions residing in graph node processes along the way. All processes in a co-op are linked to a shared "kill switch" process. This groups the entire co-op into a dependency star network such that the death of any process or the kill switch causes the entire co-op to go away. A co-op normally has permanent processes rather than transient processes.

![Co-op Pipeline](https://raw.github.com/jaynel/erlangsp/master/apps/examples/tutorial/diagrams/pipeline.gif)

**Figure 1.** A 3-stage pipeline of processes implemented as a single Co-op

The _coop_ library (_erlangsp/apps/coop_) of Erlang/SP provides utilities for creating a digraph instance and labeling the nodes with an init function and a task function. Together these define the work that a node process will implement. The digraph is retained as a template so that the co-op may be cloned. Instantiating or cloning causes a live network of processes to be primed and ready to receive messages, as opposed to the static graph template. Multiple copies of a co-op may be running simultaneously to distribute workload for the same computation across more processors.

Within a co-op, data is passed downstream by default, however, it is possible for each node to emit data to other processes, other co-ops or to prevent data from continuing downstream. The final node(s) of a co-op normally expect another process or co-op to receive the results.

There are currently two static co-op topologies supported:

  1. **Pipeline**: a chain of processes executed in order
  2. **Fan out**:  a single process which leads to N children

Pipeline
--------

Pipelines provide overlapping concurrency. When the first stage receives data, it processes and passes that data to the second stage. Meanwhile the first stage is now free to process the next request. A three-stage pipeline such as in *Figure 1* can be executing three separate requests simultaneously, each at a different point of completion, provided the requests flow in fast enough to keep the pipeline occupied.

Note that a pipeline can process data only as fast as the slowest member, so the computational load of stages are best kept roughly equal. The more processing cores available, the more pipeline stages are preferred (with the caveat that messaging overhead could become significant if the message data size is too large among stages). A good strategy would be to either provide equal processing on the same amount of data across stages, or to reduce the data size at each stage but allow progressively more intense computation in later stages. The characteristics of your platform's CPU speed versus message passing bandwidth will determine which approach works better.


Fan out
-------

Fan out patterns provide discrimination, load balancing, distribution or parallel computation. The fan out pattern also has an option to provide fan in at the next level of the graph. This allows a parallel computation followed by collapsing or ordering the result (_fork/join_, _scatter/gather_, or _map/reduce_ algorithmic skeletons).

![Co-op Pipeline](https://raw.github.com/jaynel/erlangsp/master/apps/examples/tutorial/diagrams/fanout.gif)

**Figure 2.** An example of a fan out discriminating router Co-op

Load balancing can be provided by either random selection or round robin selection of a single child to execute. Currently this is supported via a single process using its erlang message queue to receive requests, therefore creating a serialization point, or by using a forest of fan out graphs and distributed load balancing via an ets table containg each of the fan out roots. Although the ets table is a serialization point it proves to be significantly faster in handling requests than a single erlang process message queue and therefore simulates fully distributed load balancing better.

Parallel computation is offered by broadcasting data to all the children of a fan out root. This is a parallel map implementation, with optional fan in to a single process or co-op.

**Planned enhancements**

  * _Distributed hash equivalent_

      The ability to have a consistent hash load balancing approach that is
      more truly distributed, but the implementation has a more involved
      structure requiring a distributed algorithm to maintain knowledge of
      the peer workers.

  * _Shuffle_

      Orders the children randomly, then visits in round_robin order.
      Re-shuffles before next pass, guaranteeing random order without
      duplication.

  * _Consume_

      Selects 1-N processes in round_robin fashion, but expects them to
      be used to termination. When the number of unassigned processes dips
      below a threshold percent, a group of new processes are spawned and
      added to those available.

Example usage
-------------

Example code and services are provided in the _erlangsp/apps/examples_ directory.

**Code:**

  * _simple_: direct use of base co-op patterns

**Services:**

  * _esp_cache_: caching with a single process per datum
  * _esp_spider_: parsing HTML to collect URLs referenced in a page

