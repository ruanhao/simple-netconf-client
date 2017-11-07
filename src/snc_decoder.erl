-module(snc_decoder).
-include("snc_protocol.hrl").
-export([decode_data/1,
         decode_ok/1,
         decode_streams/1,
         forward_xmlns_attr/2,
         decode_caps/3,
         get_local_name_atom/1,
         sax_event/3]).


decode_data([{Tag,Attrs,Content}]) ->
    case get_local_name_atom(Tag) of
        ok ->
            %% when action has return type void
            ok;
        data ->
            %% Since content of data has nothing from the netconf
            %% namespace, we remove the parent's xmlns attribute here
            %% - just to make the result cleaner
            {ok,forward_xmlns_attr(remove_xmlnsattr_for_tag(Tag,Attrs),Content)};
        'rpc-error' ->
            {error,forward_xmlns_attr(Attrs,Content)};
        _Other ->
            {error,{unexpected_rpc_reply,[{Tag,Attrs,Content}]}}
    end;
decode_data(Other) ->
    {error,{unexpected_rpc_reply,Other}}.

get_qualified_name(Tag) ->
    case string:tokens(atom_to_list(Tag),":") of
        [TagStr] -> {[],TagStr};
        [PrefixStr,TagStr] -> {PrefixStr,TagStr}
    end.

get_local_name_atom(Tag) ->
    {_,TagStr} = get_qualified_name(Tag),
    list_to_atom(TagStr).

%% Remove the xmlns attr that points to the tag. I.e. if the tag has a
%% prefix, remove {'xmlns:prefix',_}, else remove default {xmlns,_}.
remove_xmlnsattr_for_tag(Tag,Attrs) ->
    {Prefix,_TagStr} = get_qualified_name(Tag),
    XmlnsTag = xmlnstag(Prefix),
    case lists:keytake(XmlnsTag,1,Attrs) of
        {value,_,NoNsAttrs} ->
            NoNsAttrs;
        false ->
            Attrs
    end.

%% Take all xmlns attributes from the parent's attribute list and
%% forward into all childrens' attribute lists. But do not overwrite
%% any.
forward_xmlns_attr(ParentAttrs,Children) ->
    do_forward_xmlns_attr(get_all_xmlns_attrs(ParentAttrs,[]),Children).

do_forward_xmlns_attr(XmlnsAttrs,[{ChT,ChA,ChC}|Children]) ->
    ChA1 = add_xmlns_attrs(XmlnsAttrs,ChA),
    [{ChT,ChA1,ChC} | do_forward_xmlns_attr(XmlnsAttrs,Children)];
do_forward_xmlns_attr(_XmlnsAttrs,[]) ->
    [].

add_xmlns_attrs([{Key,_}=A|XmlnsAttrs],ChA) ->
    case lists:keymember(Key,1,ChA) of
        true ->
            add_xmlns_attrs(XmlnsAttrs,ChA);
        false ->
            add_xmlns_attrs(XmlnsAttrs,[A|ChA])
    end;
add_xmlns_attrs([],ChA) ->
    ChA.

xmlnstag([]) ->
    xmlns;
xmlnstag(Prefix) ->
    list_to_atom("xmlns:"++Prefix).

get_all_xmlns_attrs([{xmlns,_}=Default|Attrs],XmlnsAttrs) ->
    get_all_xmlns_attrs(Attrs,[Default|XmlnsAttrs]);
get_all_xmlns_attrs([{Key,_}=Attr|Attrs],XmlnsAttrs) ->
    case atom_to_list(Key) of
        "xmlns:"++_Prefix ->
            get_all_xmlns_attrs(Attrs,[Attr|XmlnsAttrs]);
        _ ->
            get_all_xmlns_attrs(Attrs,XmlnsAttrs)
    end;
get_all_xmlns_attrs([],XmlnsAttrs) ->
    XmlnsAttrs.

%% Event function for the sax parser. It builds a simple XML structure.
%% Care is taken to keep namespace attributes and prefixes as in the original XML.
sax_event(Event,_Loc,State) ->
    sax_event(Event,State).

sax_event({startPrefixMapping, Prefix, Uri},Acc) ->
    %% startPrefixMapping will always come immediately before the
    %% startElement where the namespace is defined.
    [{xmlns,{Prefix,Uri}}|Acc];
sax_event({startElement,_Uri,_Name,QN,Attrs},Acc) ->
    %% Pick out any namespace attributes inserted due to a
    %% startPrefixMapping event.The rest of Acc will then be only
    %% elements.
    {NsAttrs,NewAcc} = split_attrs_and_elements(Acc,[]),
    Tag = qn_to_tag(QN),
    [{Tag,NsAttrs ++ parse_attrs(Attrs),[]}|NewAcc];
sax_event({endElement,_Uri,_Name,_QN},[{Name,Attrs,Cont},{Parent,PA,PC}|Acc]) ->
    [{Parent,PA,[{Name,Attrs,lists:reverse(Cont)}|PC]}|Acc];
sax_event(endDocument,[{Tag,Attrs,Cont}]) ->
    {Tag,Attrs,lists:reverse(Cont)};
sax_event({characters,String},[{Name,Attrs,Cont}|Acc]) ->
    [{Name,Attrs,[String|Cont]}|Acc];
sax_event(_Event,State) ->
    State.

split_attrs_and_elements([{xmlns,{Prefix,Uri}}|Rest],Attrs) ->
    split_attrs_and_elements(Rest,[{xmlnstag(Prefix),Uri}|Attrs]);
split_attrs_and_elements(Elements,Attrs) ->
    {Attrs,Elements}.

qn_to_tag({[],Name}) ->
    list_to_atom(Name);
qn_to_tag({Prefix,Name}) ->
    list_to_atom(Prefix ++ ":" ++ Name).

parse_attrs([{_Uri, [], Name, Value}|Attrs]) ->
    [{list_to_atom(Name),Value}|parse_attrs(Attrs)];
parse_attrs([{_Uri, Prefix, Name, Value}|Attrs]) ->
    [{list_to_atom(Prefix ++ ":" ++ Name),Value}|parse_attrs(Attrs)];
parse_attrs([]) ->
    [].

decode_ok([{Tag,Attrs,Content}]) ->
    case get_local_name_atom(Tag) of
        ok ->
            ok;
        'rpc-error' ->
            {error,forward_xmlns_attr(Attrs,Content)};
        _Other ->
            {error,{unexpected_rpc_reply,[{Tag,Attrs,Content}]}}
    end;
decode_ok(Other) ->
    {error,{unexpected_rpc_reply,Other}}.


%% Return a list of {Name,Data}, where data is a {Tag,Value} list for each stream
decode_streams({error,Reason}) ->
    {error,Reason};
decode_streams({ok,[{netconf,_,Streams}]}) ->
    {ok,decode_streams(Streams)};
decode_streams([{streams,_,Streams}]) ->
    decode_streams(Streams);
decode_streams([{stream,_,Stream} | Streams]) ->
    {name,_,[Name]} = lists:keyfind(name,1,Stream),
    [{Name,[{Tag,Value} || {Tag,_,[Value]} <- Stream, Tag /= name]}
     | decode_streams(Streams)];
decode_streams([]) ->
    [].

decode_caps([{capability,[],[?NETCONF_BASE_CAP++Vsn=Cap]} |Caps], Acc, _) ->
    case Vsn of
        V when V =:= ?NETCONF_BASE_CAP_VSN orelse V =:= ?NETCONF_BASE_CAP_VSN_1_1 ->
            decode_caps(Caps, [Cap|Acc], true);
        _ ->
            {error,{incompatible_base_capability_vsn,Vsn}}
    end;
decode_caps([{capability,[],[Cap]}|Caps],Acc,Base) ->
    decode_caps(Caps,[Cap|Acc],Base);
decode_caps([H|_T],_,_) ->
    {error,{unexpected_capability_element,H}};
decode_caps([],_,false) ->
    {error,{incorrect_hello,no_base_capability_found}};
decode_caps([],Acc,true) ->
    {ok,lists:reverse(Acc)}.