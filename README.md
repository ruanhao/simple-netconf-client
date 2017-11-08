Simple Netconf Client
=====

This is a TCP version [ct_netconfc](http://erlang.org/doc/man/ct_netconfc.html).

It can be used as a testtool to analyze Netconf protocol.

For detailed usage, please take [nm-netconf-client](https://github.com/ruanhao/nm-netconf-client) as an example.


Build
-----

    $ rebar3 compile


Run
-----

    $ rebar3 shell --apps snc

    1> {client, Pid} = snc_client_dispatcher:start_client("10.74.68.81", 8443).
    2> CreateSubscription = ["NETCONF", undefined, undefined, undefined].
    ["NETCONF", undefined, undefined, undefined]
    3> SimpleXml = snc_encoder:encode_rpc_operation(create_subscription, CreateSubscription).
    {'create-subscription',[{xmlns,"urn:ietf:params:xml:ns:netconf:notification:1.0"}],
                       [{stream,["NETCONF"]}]}
    4> gen_server:call(Pid, {create_subscription, SimpleXml}).
    

