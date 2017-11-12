Simple Netconf Client
=====

This is a TCP version [ct_netconfc](http://erlang.org/doc/man/ct_netconfc.html).

It can be used as a testtool to analyze Netconf protocol.

For usage reference, have a look at [nm-netconf-client](https://github.com/ruanhao/nm-netconf-client) as an example.


Build
-----

    $ rebar3 compile

Run
-----

    $ rebar3 shell --apps snc


Note
-----

You can use this library to connect to Netconf server and communicate with Netconf XML message.

For example:

1. create a netconf client

``` elrang
{ok, Pid} = snc_client:start_link("10.74.68.81", 8443)
```

2. create subscription

``` erlang
CreateSubscription = ["NETCONF", undefined, undefined, undefined]), % default 
SimpleXml = snc_encoder:encode_rpc_operation(create_subscription, CreateSubscription),
%% SimpleXml:
%% {'create-subscription',[{xmlns,"urn:ietf:params:xml:ns:netconf:notification:1.0"}],
%%                        [{stream,["NETCONF"]}]}
ok = snc_client:rpc_create_subscription(Pid, SimpleXml).
```

All Netconf protocol logic is in module `snc_client.erl`, you can check it for more information.