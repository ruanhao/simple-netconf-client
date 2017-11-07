-module(snc_encoder).
-export([encode_rpc_operation/2,
         encode_hello/1]).

-include("snc_protocol.hrl").

-define(is_timeout(T),
        (is_integer(T) orelse T == infinity)).
-define(is_simple_xml(Xml),
        (is_atom(Xml) orelse (is_tuple(Xml) andalso is_atom(element(1,Xml))))).
-define(is_filter(F),
        (?is_simple_xml(F) orelse (F==[]) orelse (is_list(F) andalso ?is_simple_xml(hd(F))))).
-define(is_string(S),
        (is_list(S) andalso is_integer(hd(S)))).


%%%-----------------------------------------------------------------
encode_hello(Options) when is_list(Options) ->
    UserCaps = [{capability, UserCap} ||
                   {capability, UserCap} <- Options,
                   is_list(hd(UserCap))],
    {hello, ?NETCONF_NAMESPACE_ATTR,
     [{capabilities,
       [{capability,[?NETCONF_BASE_CAP++?NETCONF_BASE_CAP_VSN]}|
        UserCaps]}]}.

%%%-----------------------------------------------------------------
encode_rpc_operation(Lock,[Target]) when Lock==lock; Lock==unlock ->
    {Lock,[{target,[Target]}]};
encode_rpc_operation(get,[Filter]) ->
    {get,filter(Filter)};
encode_rpc_operation(get_config,[Source,Filter]) ->
    {'get-config',[{source,[Source]}] ++ filter(Filter)};
encode_rpc_operation(edit_config,[Target,Config,OptParams]) ->
    {'edit-config',[{target,[Target]}] ++ OptParams ++ [{config,[Config]}]};
encode_rpc_operation(delete_config,[Target]) ->
    {'delete-config',[{target,[Target]}]};
encode_rpc_operation(copy_config,[Target,Source]) ->
    {'copy-config',[{target,[Target]},{source,[Source]}]};
encode_rpc_operation(action,[Action]) ->
    {action,?ACTION_NAMESPACE_ATTR,[{data,[Action]}]};
encode_rpc_operation(kill_session,[SessionId]) ->
    {'kill-session',[{'session-id',[integer_to_list(SessionId)]}]};
encode_rpc_operation(close_session,[]) ->
    'close-session';
encode_rpc_operation(create_subscription,
                     [Stream,Filter,StartTime,StopTime]) ->
    {'create-subscription', ?NETCONF_NOTIF_NAMESPACE_ATTR,
     [{stream,[Stream]}] ++
         filter(Filter) ++
         maybe_element(startTime,StartTime) ++
         maybe_element(stopTime,StopTime)}.

%%%-----------------------------------------------------------------
filter(undefined) ->
    [];
filter({xpath,Filter}) when ?is_string(Filter) ->
    [{filter,[{type,"xpath"},{select, Filter}],[]}];
filter(Filter) when is_list(Filter) ->
    [{filter,[{type,"subtree"}],Filter}];
filter(Filter) ->
    filter([Filter]).

maybe_element(_,undefined) ->
    [];
maybe_element(Tag,Value) ->
    [{Tag,[Value]}].