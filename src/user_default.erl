-module(user_default).
-compile(export_all).

snc_start() ->
    snc_prototype:start_link().

snc_get_scheme() ->
    gen_server:call(snc_prototype, get_scheme).

snc_subscribe() ->
    gen_server:call(snc_prototype, subscription).

snc_info() ->
    gen_server:call(snc_prototype, show_state).