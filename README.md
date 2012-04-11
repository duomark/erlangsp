Erlang Services Platform (erlang/SP)
==================================

Erlang/SP is a replacement for erlang/OTP that is designed to scale to 10Ks of processors. OTP allows a designer to architect distributed systems out of single process behaviours to create scaffoldings in the 10-100s of process range geared around a single permanent hierarchical application or a set of single hierarchical applications. SP eschews applications in favor of peer services that replicate and fade as needed, constructing solutions on an architecture functionally composed with patterns of Cooperating Processes. The fundamental unit is a coop (pronounced co'-op) rather than a Pid.

The basic components of an Erlang/SP solution are:

  * coop: A task-specific (pipeline, round-robin) collection of cooperating processes
  * spree: A flash of activity coordinated amongst several coops
  * cluster: A pack of coops working together to solve a subproblem
  * constellation: A network of clusters
  * universe: A complete system solution


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

  1. make realclean all eunit dialyze rel

You must write erlang code that uses the erlangsp library for your application to take advantage of the services provided.
