
%%----------------------------------------------------------------------
%% A Co-op Node is a single worker element of a Co-op. Every worker
%% element exists to accept data, transform it and pass it on.
%%
%% There are separate pids internal to a Co-op Node used to:
%%    1) terminate the entire co-op (kill_switch)
%%    2) receive control requests (ctl)
%%    3) execute the transform function (task execs task_fn)
%%    4) relay trace information (trace)
%%    5) record log and telemetry data (log)
%%    6) reflect data flow for user display and analysis (reflect)
%%----------------------------------------------------------------------

-record(coop_node_state, {
          kill_switch :: pid(),
          ctl         :: pid(),
          task        :: pid(),
          init_fn     :: coop_init_fn(),
          task_fn     :: coop_task_fn(),
          trace       :: pid(),
          log         :: pid(),
          reflect     :: pid()
         }).
