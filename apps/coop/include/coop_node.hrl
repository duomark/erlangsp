
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
