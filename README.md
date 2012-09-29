Erlang Services Platform (Erlang/SP)
==================================

Erlang/SP is a adjunct to Erlang/OTP that is designed to scale to 10Ks of processor cores. OTP allows a designer to architect distributed systems out of single process behaviours to create scaffoldings in the 100s-1000s of process range geared around a single permanent hierarchical application or a set of single hierarchical applications. SP eschews applications in favor of peer services that replicate and fade as needed, constructing solutions on an architecture functionally composed with patterns of Cooperating Processes (Co-ops). The fundamental unit is a Co-op rather than a Pid.

The ideas behind Erlang/SP are evolving rapidly and constantly in flux. I welcome feedback, but expect any and all interfaces to change without notice. This is an experiment that can run comfortably alongside OTP but revisits the tradeoffs and assumptions underlying the philosphy of OTP.

The basic components of an Erlang/SP solution are:

  * digraph: An instance of the erlang:digraph module to describe a co-op structure
  * co-op: A task-specific (pipeline, round-robin, broadcast) collection of cooperating processes

Users of the library will primarily deal with Co-op instances. The digraphs are generally hidden inside of Co-ops and used to guide the behavior for replication and visualization / reflection.

All components offer both Control and Data channels for more efficient management of services. Supervisor behaviour will not resemble the current incarnation of OTP, and allocation of processes will be more of a batch/bulk-oriented operation (probably eventually requiring VM tweaks to enhance process spawning speed). Some tests of parallel spawning will be done soon.

Goals
=====

The ultimate goal of this project is to provide the average erlang programmer a huge boost in productivity and performance by providing easy access to complex concurrent computation models. In addition the following are considered intermediate goals:

  * Enable dataflow algorithms
  * Promote graph computation and dynamic data storage/access
  * Provide a toolbox with much higher scalability patterns than OTP offers
  * Simplify the code to implement common concurrent architectural patterns
  * Display algorithms in action through the browser

Related Work
============

As of April 12, 2012, I discovered the approach I have been designing is a reinvention of Algorithmic Skeletons (Murray Cole, "Algorithmic Skeletons: structured management of parallel computation" MIT Press, Cambdridge, MA, USA, 1989). I only discovered these references after implementing the first proof-of-concept.  Workflow patterns as implemented in Business Processing Execution Languages (BPEL) also serve as a model for common concurrency patterns.

There are also similarities to http://github.com/vladdu/erl-pipes although I expect this library to go far beyond Hartmann-style pipelines.

On July 13, 2012 I came across http://github.com/bergie/noflo which is a Node.js implementation of Flow-Based Programming. This seems to have many similarities due to the basis on digraphs. They seem to be concentrating on integration with existing flow-based tools and declarative languages like dot (used by graphviz). Erlang/SP intends to be more comfortable to an erlang programmer, and hopefully more graphical with browser-based interactions, however internally adopting a language like dot might be an option.

Travis CI
=========

[![Build Status](http://travis-ci.org/duomark/erlangsp.png)](http://travis-ci.org/duomark/erlangsp])

[Travis-CI](http://about.travis-ci.org/) provides Continuous Integration. Travis automatically builds and runs the unit tests whenever the code is modified. The status of the current build is shown in the image badge directly above this paragraph.

Integration with Travis is provided by the [.travis.yml file](https://raw.github.com/duomark/erlangsp/master/.travis.yml). The automated build is run on R15B.

Included software
=================

This project is built with dependencies on other open source software projects.

The following software is used to build, test or validate the application during development:

  * erlang R14B or later (should work on any version with digraph)
  * meck (git://github.com/eproxus/meck.git)


Compiling and testing erlangsp
==============================

Download and install the source code, then perform the following at the command line:

```
  % make realclean all test dialyze rel
  % rel/erlangsp/bin/erlangsp console
```

You will now be at a shell prompt with erlangsp, coop and any example projects loaded. Try the following erlang commands to ensure that everything compiled and loaded properly:

```
  1> coop:module_info().
  2> erlangsp:module_info().
  3> esp_cache:module_info().
```

You must write erlang code that uses the erlangsp library for your application to take advantage of the services provided. The best way to do that is to use rebar and name erlangsp as an included application in your .app.src application file.

Documentation
=============

The current documentation is rudimentary because the underlying software is changing quickly. There should be enough information to try out the libraries and examples, but it is not formatted in a nice way. There is a separate 'docs' directory in each of the apps or examples directories written in markdown so that it can be easily browsed from github with a browser:

  1. [Tutorial](erlangsp/tree/master/apps/examples/tutorial/README.md)
  1. [Co-op docs](erlangsp/tree/master/apps/coop/docs/README.md)
