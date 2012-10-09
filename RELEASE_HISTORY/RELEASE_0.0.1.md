2012-09-16
http://erlang.org/pipermail/erlang-questions/2012-September/069206.html

Erlang Services Platform (Erlang/SP) debuted at the ICFP 2012
Erlang Workshop in Copenhagen on Friday. This is the
first release which is intended as a proof of concept.

Erlang/SP attempts to provide dataflow programming for OTP users.
It creates a network of processes based on a digraph instance.
The graph maps nodes to processes and edges to one-way message
communication channels, each between two processes. A graph
is called a Co-op, short for Co-operating Processes. There is some
limited documentation about the library included in the repo,
along with some materials presented at ICFP in the apps/coop/docs
directory.

The built in constructors provide pipeline and fan-out (optionally
with fan-in) patterns. Good utilities for joining graphs into larger
entities are not yet provided, but coops may receive from and
feed to any normal erlang process including OTP processes.
They also support sys functionality (e.g., trace, suspend, resume,
etc) so will be full-fledged OTP citizens.

It is available at https://github.com/duomark/erlangsp

Comments, suggestions, issues and pull requests are all welcome.

Jay Nelson
DuoMark International, Inc.
@duomark
