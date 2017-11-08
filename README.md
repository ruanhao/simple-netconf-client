Simple Netconf Client
=====

This is a TCP version [ct_netconfc](http://erlang.org/doc/man/ct_netconfc.html).

It can be used as a testtool to analyze Netconf protocol.



Build
-----

    $ rebar3 compile


Run
-----

    $ rebar3 shell --apps snc


    1> {client, Pid} = snc_client_dispatcher:start_client("10.74.68.81", 8443).
    2> gen_server:call(Pid, subscription).
    

