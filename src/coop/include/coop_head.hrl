
%%----------------------------------------------------------------------
%% A Coop Head is the external interface of a coop graph.
%% It receives control and data requests and passes them on to
%% the Coop Node components of the coop graph.
%%
%% There are separate pids internal to a Coop Head used to:
%%    1) terminate the entire coop (kill_switch)
%%    2) receive control requests (ctl)
%%    3) forward data requests (data)
%%    4) one_at_a_time gateway to Coop Body (root)
%%    4) relay trace information (trace)
%%    5) record log and telemetry data (log)
%%    6) reflect data flow for user display and analysis (reflect)
%%----------------------------------------------------------------------

-record(coop_head_state, {
          kill_switch :: pid(),
          ctl         :: pid(),
          data        :: pid(),
          root        :: pid(),
          log         :: pid(),
          trace       :: pid(),
          reflect     :: pid(),
          coop_root_node :: coop_body()
         }).

