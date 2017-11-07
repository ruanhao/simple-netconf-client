%%%-------------------------------------------------------------------
%%% @author Hao Ruan <ruanhao1116@google.com>
%%% @copyright (C) 2017, Hao Ruan
%%% @doc
%%%
%%% @end
%%% Created :  6 Nov 2017 by Hao Ruan <ruanhao1116@google.com>
%%%-------------------------------------------------------------------

%% Default timeout to wait for netconf server to reply to a request
-define(DEFAULT_TIMEOUT, infinity). %% msec

%% Namespaces
-define(NETCONF_NAMESPACE,       "urn:ietf:params:xml:ns:netconf:base:1.0").
-define(ACTION_NAMESPACE,        "urn:com:ericsson:ecim:1.0").
-define(NETCONF_NOTIF_NAMESPACE, "urn:ietf:params:xml:ns:netconf:notification:1.0").
-define(NETMOD_NOTIF_NAMESPACE,  "urn:ietf:params:xml:ns:netmod:notification").

-define(NETCONF_NAMESPACE_ATTR,       [{xmlns, ?NETCONF_NAMESPACE}]).
-define(ACTION_NAMESPACE_ATTR,        [{xmlns, ?ACTION_NAMESPACE}]).
-define(NETCONF_NOTIF_NAMESPACE_ATTR, [{xmlns, ?NETCONF_NOTIF_NAMESPACE}]).
-define(NETMOD_NOTIF_NAMESPACE_ATTR,  [{xmlns, ?NETMOD_NOTIF_NAMESPACE}]).

%% Capabilities
-define(NETCONF_BASE_CAP,         "urn:ietf:params:netconf:base:").
-define(NETCONF_BASE_CAP_VSN,     "1.0").
-define(NETCONF_BASE_CAP_VSN_1_1, "1.1").

%% END_TAG
-define(END_TAG,<<"]]>]]>">>).
