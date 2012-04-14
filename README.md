Erlang Services Platform (Erlang/SP)
==================================

Erlang/SP is a replacement for Erlang/OTP that is designed to scale to 10Ks of processors. OTP allows a designer to architect distributed systems out of single process behaviours to create scaffoldings in the 100s-1000s of process range geared around a single permanent hierarchical application or a set of single hierarchical applications. SP eschews applications in favor of peer services that replicate and fade as needed, constructing solutions on an architecture functionally composed with patterns of Cooperating Processes. The fundamental unit is a coop (pronounced co'-op) rather than a Pid.

The ideas behind Erlang/SP are evolving rapidly and constantly in flux. I welcome feedback, but expect any and all interfaces to change without notice. This is an experiment that can run comfortably alongside OTP and is only a "replacement" in the sense that it revisits the tradeoffs and assumptions underlying the philosphy of OTP.

The basic components of an Erlang/SP solution are:

  * [joule: The smallest unit of work]
  * coop: A task-specific (pipeline, round-robin) collection of cooperating processes
  * spree: A flash of activity coordinated amongst several coops
  * cluster: A pack of coops working together to solve a subproblem
  * constellation: A network of clusters
  * universe: A complete system solution

All components offer both Control and Data channels for more efficient management of services. There will be some concept of Overlords/Fiefs which monitor and manage clusters and sprees, as well as a coordinator of constellation topography and migration, but that will require some experience with the basic components to understand what the requirements are. In any event, supervisor behaviour will not resemble the current incarnation of OTP, and allocation of processes will be more of a batch/bulk-oriented operation (probably eventually requiring VM tweaks to enhance process spawning speed).

Goals
=====

The ultimate goal of this project is to provide the average erlang programmer a huge boost in productivity and performance by providing easy access to complex concurrent computation models. In addition the following are considered intermediate goals:

  * Enable dataflow algorithms
  * Promote graph computation and data storage/access
  * Provide a toolbox with much higher scalability patterns than OTP offers
  * Simplify the code to implement common concurrent architectural patterns

Related Work
============

As of April 12, 2012, I discovered the approach I have been designing is a reinvention of Algorithmic Skeletons (http://www.macs.hw.ac.uk/~pm175/F21DP2/l08_handout.pdf) or Skeletal Parallel Programming (http://homepages.inf.ed.ac.uk/mic/Pubs/manifesto.pdf). I only discovered these references after implementing the first proof-of-concept.

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
