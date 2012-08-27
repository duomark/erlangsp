Co-op Library (Cooperating Processes)
=====================================

A co-op is a collection of processes arranged in a Directed Acyclic Graph (using Erlang's digraph module). Nodes of the graph are processes and edges represent messaging from an upstream process to a downstream process. The structure is maintained as a static digraph template when initially specified, a digraph containing live erlang processes at each graph node, and the same erlang processes connected via internal state references to downstream pids such that messages are sent directly to known pids without name lookup in the normal dataflow case.

