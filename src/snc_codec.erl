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


-define(DEFAULT_STREAM, "NETCONF").


-spec rpc_get(MsgId, Filter) -> Result when
      MsgId  :: integer(),
      Filter :: simple_xml() | xpath(),
      Result :: [simple_xml()].
rpc_get(MsgId, Filter) ->
    FilterSimpleXml = snc_encoder:encode_rpc_operation(get, [Filter]),
    generate_rpc_msg(MsgId, FilterSimpleXml).

rpc_create_subscription(MsgId) ->
    rpc_create_subscription(MsgId,
                            ?DEFAULT_STREAM,
                            undefined,
                            undefined,
                            undefined).
rpc_create_subscription(MsgId, Stream, Filter, StartTime, StopTime) ->
    SimpleXml = snc_encoder:encode_rpc_operation(create_subscription,
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

generate_rpc_msg(MsgId, ContentSimpleXml) ->
    {rpc,
     [{'message-id',MsgId} | ?NETCONF_NAMESPACE_ATTR],
     [ContentSimpleXml]}.
