%%%-------------------------------------------------------------------
%%% @author Hao Ruan <ruanhao1116@google.com>
%%% @copyright (C) 2017, Hao Ruan
%%% @doc
%%%
%%% @end
%%% Created :  6 Nov 2017 by Hao Ruan <ruanhao1116@google.com>
%%%-------------------------------------------------------------------

-module(snc_codec).
-include("snc_types.hrl").
-include("snc_protocol.hrl").
-include_lib("xmerl/include/xmerl.hrl").
-export([rpc_get/2,
         rpc_create_subscription/1,
         rpc_create_subscription/5,
         to_xml_doc/1,
         to_pretty_xml_doc/1
        ]).

-define(is_timeout(T), (is_integer(T) orelse T==infinity)).
-define(is_filter(F),
        (?is_simple_xml(F)
         orelse (F==[])
         orelse (is_list(F) andalso ?is_simple_xml(hd(F))))).
-define(is_simple_xml(Xml),
        (is_atom(Xml) orelse (is_tuple(Xml) andalso is_atom(element(1,Xml))))).
-define(is_string(S), (is_list(S) andalso is_integer(hd(S)))).
-define(DEFAULT_STREAM, "NETCONF").


-spec rpc_get(MsgId, Filter) -> Result when
      MsgId  :: integer(),
      Filter :: simple_xml() | xpath(),
      Result :: [simple_xml()].
rpc_get(MsgId, Filter) ->
    FilterSimpleXml = encode_rpc_operation(get, [Filter]),
    generate_rpc_msg(MsgId, FilterSimpleXml).

rpc_create_subscription(MsgId) ->
    rpc_create_subscription(MsgId,
                            ?DEFAULT_STREAM,
                            undefined,
                            undefined,
                            undefined).
rpc_create_subscription(MsgId, Stream, Filter, StartTime, StopTime) ->
    SimpleXml = encode_rpc_operation(create_subscription,
                                     [Stream,Filter,StartTime,StopTime]),
    generate_rpc_msg(MsgId, SimpleXml).


-spec to_xml_doc(Simple) -> Result when
      Simple :: simple_xml(),
      Result :: binary.
to_xml_doc(Simple) ->
    Prolog = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
    Xml = unicode:characters_to_binary(
            xmerl:export_simple([Simple],
                                xmerl_xml,
                                [#xmlAttribute{name=prolog,
                                               value=Prolog}])),
    <<Xml/binary,?END_TAG/binary>>.

-spec to_pretty_xml_doc(Simple) -> Result when
      Simple :: simple_xml(),
      Result :: binary.
to_pretty_xml_doc(SimpleXml) ->
    snc_utils:indent(to_xml_doc(SimpleXml)).



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
    {'create-subscription',?NETCONF_NOTIF_NAMESPACE_ATTR,
     [{stream,[Stream]}] ++
         filter(Filter) ++
         maybe_element(startTime,StartTime) ++
         maybe_element(stopTime,StopTime)}.



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


generate_rpc_msg(MsgId, ContentSimpleXml) ->
    {rpc,
     [{'message-id',MsgId} | ?NETCONF_NAMESPACE_ATTR],
     [ContentSimpleXml]}.
