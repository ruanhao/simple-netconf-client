-define(ERROR(Msg, Values),
        error_logger:error_msg("[~p|~p|~p] " ++ Msg ++ "~n", [?MODULE, ?LINE, self() | Values])).
-define(ERROR(Msg),
        error_logger:error_msg("[~p|~p|~p] " ++ Msg ++ "~n", [?MODULE, ?LINE, self()])).

-define(INFO(Msg, Values),
        error_logger:info_msg("[~p|~p|~p] " ++ Msg ++ "~n", [?MODULE, ?LINE, self() | Values])).
-define(INFO(Msg),
        error_logger:info_msg("[~p|~p|~p] " ++ Msg ++ "~n", [?MODULE, ?LINE, self()])).