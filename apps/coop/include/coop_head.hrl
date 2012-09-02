
-record(coop_head_state, {
          kill_switch :: pid(),
          ctl         :: pid(),
          data        :: pid(),
          root        :: pid(),
          log         :: pid(),
          trace       :: pid(),
          reflect     :: pid(),
          coop_root_node :: coop_node() | none
         }).

