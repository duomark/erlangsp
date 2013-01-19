
-type svc_state() :: new | active | suspended | stop_suspended | stopped.
-record(esp_svc, {status = new       :: svc_state(),
                  overloaded = false :: boolean(),
                  coop               :: coop()}).

-type esp_service() :: #esp_svc{}.
