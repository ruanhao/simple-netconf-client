%%%-------------------------------------------------------------------
%%% @author Hao Ruan <ruanhao1116@google.com>
%%% @copyright (C) 2017, Hao Ruan
%%% @doc
%%%
%%% @end
%%% Created :  6 Nov 2017 by Hao Ruan <ruanhao1116@google.com>
%%%-------------------------------------------------------------------
%% Default port number (RFC 4742/IANA).
-define(DEFAULT_PORT, 830).

%% Default timeout to wait for netconf server to reply to a request
-define(DEFAULT_TIMEOUT, infinity). %% msec

%% Namespaces
-define(NETCONF_NAMESPACE_ATTR,[{xmlns,?NETCONF_NAMESPACE}]).
-define(ACTION_NAMESPACE_ATTR,[{xmlns,?ACTION_NAMESPACE}]).
-define(NETCONF_NOTIF_NAMESPACE_ATTR,[{xmlns,?NETCONF_NOTIF_NAMESPACE}]).
-define(NETMOD_NOTIF_NAMESPACE_ATTR,[{xmlns,?NETMOD_NOTIF_NAMESPACE}]).

-define(NETCONF_NAMESPACE,"urn:ietf:params:xml:ns:netconf:base:1.0").
-define(ACTION_NAMESPACE,"urn:com:ericsson:ecim:1.0").
-define(NETCONF_NOTIF_NAMESPACE,
       "urn:ietf:params:xml:ns:netconf:notification:1.0").
-define(NETMOD_NOTIF_NAMESPACE,"urn:ietf:params:xml:ns:netmod:notification").

%% Capabilities
-define(NETCONF_BASE_CAP,"urn:ietf:params:netconf:base:").
-define(NETCONF_BASE_CAP_VSN,"1.0").

%% Misc
-define(END_TAG,<<"]]>]]>">>).

-define(FORMAT(_F, _A), lists:flatten(io_lib:format(_F, _A))).
