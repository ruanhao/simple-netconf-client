%%%-------------------------------------------------------------------
%%% @author Hao Ruan <ruanhao1116@google.com>
%%% @copyright (C) 2017, Hao Ruan
%%% @doc
%%%
%%% @end
%%% Created :  5 Nov 2017 by Hao Ruan <ruanhao1116@google.com>
%%%-------------------------------------------------------------------
-module(snc_client).

-define(SERVER, ?MODULE).

-define(ERROR(Report),
        error_logger:error_report([{client, self()}, {module, ?MODULE}, {line, ?LINE} | Report])).

-define(INFO(Report),
        error_logger:info_report([{client, self()}, {module, ?MODULE}, {line, ?LINE} | Report])).

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).


-include("snc_protocol.hrl").
-include_lib("xmerl/include/xmerl.hrl").

%% Client state
-record(state, {
          sock,
          host,
          port,
          capabilities,
          session_id,
          msg_id = 1,
          hello_status,
          no_end_tag_buff = <<>>,
          buff = <<>>,
          pending = [],    % [#pending]
          event_callback = fun(_E) -> not_implemented_yet end}).


%% Run-time client options.
-record(options, {host, port=8443, timeout=5000}).

%% Pending replies from server
-record(pending, {tref,    % timer ref (returned from timer:xxx)
                  ref,     % pending ref
                  msg_id,
                  op,
                  caller}).% pid which sent the request

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    %% process_flag(trap_exit, true),
    Option = #options{host="10.74.68.81", port=48443},
    {ok, Sock} = tcp_connect(Option),
    timer:send_after(0, client_hello),
    {ok, #state{sock=Sock}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({get, SimpleXml}, From, State) ->
    do_send_rpc(get, SimpleXml, From, State);
handle_call({create_subscription, SimpleXml}, From, State) ->
    do_send_rpc(create_subscription, SimpleXml, From, State);
handle_call(get_scheme, From, State) ->
    Filter = [{'netconf-state', [],[{schemas, []}]}],
    SimpleXml = snc_encoder:encode_rpc_operation(get, [Filter]),
    do_send_rpc(get, SimpleXml, From, State);
handle_call(subscription, From, State) ->
    SimpleXml = snc_encoder:encode_rpc_operation(create_subscription,
                                                 [?DEFAULT_STREAM,
                                                  undefined,
                                                  undefined,
                                                  undefined]),
    do_send_rpc(create_subscription, SimpleXml, From, State);
handle_call(show_state, _From, State) ->
    {reply, State, State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({tcp, _Sock, Data}, State) ->
    ?INFO([{recv_data, Data}]),
    handle_data(Data, State);
handle_info(client_hello, #state{sock=Sock, hello_status=HelloStatus} = State) ->
    HelloSimpleXml = snc_encoder:encode_hello([{capability, ["urn:ietf:params:netconf:capability:exi:1.0"]}]),
    Bin = snc_utils:to_pretty_xml_doc(HelloSimpleXml),
    case tcp_send(Sock, Bin) of
        ok ->
            case HelloStatus of
                undefined ->
                    Timeout = 5000,
                    {Ref, TRef} = set_request_timer(Timeout),
                    {noreply, State#state{hello_status=#pending{tref=TRef, ref=Ref}}};
                received ->
                    {reply, ok, State#state{hello_status=done}};
                {error,Reason} ->
                    {stop, {error,Reason}, State}
            end;
        Error ->
            {stop, Error, State}
    end;
handle_info({Ref, timeout}, #state{hello_status=#pending{ref=Ref}} = State) ->
    ?ERROR([{hello_session_failed, timeout}]),
    {stop, State#state{hello_status={error, timeout}}};
handle_info({Ref, timeout}, #state{pending=Pending} = State) ->
    {value, #pending{op=Op, caller=Caller}, Pending1} =
        lists:keytake(Ref, #pending.ref, Pending),
    return(Caller, {error,timeout}),
    R = case Op of
	    close_session -> stop;
	    _ -> noreply
	end,
    %% Halfhearted try to get in correct state, this matches
    %% the implementation before this patch
    {R, State#state{pending=Pending1, no_end_tag_buff= <<>>, buff= <<>>}};
handle_info(Info, State) ->
    error_logger:info_msg("[~p: ~p] Info: ~p~n", [?MODULE, ?LINE | [Info]]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================


%%----------------------------------------------------------------------
%% Internal functions
%%----------------------------------------------------------------------


%%%-----------------------------------------------------------------
set_request_timer(infinity) ->
    {undefined, undefined};
set_request_timer(T) ->
    Ref = make_ref(),
    {ok, TRef} = timer:send_after(T, {Ref,timeout}),
    {Ref, TRef}.

%%%-----------------------------------------------------------------
cancel_request_timer(undefined, undefined) ->
    ok;
cancel_request_timer(Ref, TRef) ->
    _ = timer:cancel(TRef),
    receive {Ref,timeout} -> ok
    after 0 -> ok
    end.


%%%-----------------------------------------------------------------
%%% Send XML data to server
do_send_rpc(PendingOp, SimpleXml, Caller,
            #state{sock=Sock, msg_id=MsgId, pending=Pending} = State) ->
    case do_send_rpc(Sock, MsgId, SimpleXml) of
        ok ->
            Timeout = 5000,                     % 5 seconds
            {Ref, TRef} = set_request_timer(Timeout),
            {noreply, State#state{msg_id=MsgId+1,
                                  pending=[#pending{tref=TRef,
                                                    ref=Ref,
                                                    msg_id=MsgId,
                                                    op=PendingOp,
                                                    caller=Caller} | Pending]}};
        Error ->
            {reply, Error, State#state{msg_id=MsgId+1}}
    end.

do_send_rpc(Sock, MsgId, SimpleXml) ->
    do_send(Sock, {rpc,
                   [{'message-id', MsgId} | ?NETCONF_NAMESPACE_ATTR],
                   [SimpleXml]}).

do_send(Sock, SimpleXml) ->
    Xml = snc_utils:to_pretty_xml_doc(SimpleXml),
    tcp_send(Sock, Xml).

%%%-----------------------------------------------------------------
%%% Parse and handle received XML data
%%% Two buffers are used:
%%%   * 'no_end_tag_buff' contains data that is checked and does not
%%%     contain any (part of an) end tag.
%%%   * 'buff' contains all other saved data - it may or may not
%%%     include (a part of) an end tag.
%%% The reason for this is to avoid running binary:split/3 multiple
%%% times on the same data when it does not contain an end tag. This
%%% can be a considerable optimation in the case when a lot of data is
%%% received (e.g. when fetching all data from a node) and the data is
%%% sent in multiple ssh packages.
handle_data(NewData, State0) ->
    NoEndTag0 = State0#state.no_end_tag_buff,
    Buff0 = State0#state.buff,
    Data = <<Buff0/binary, NewData/binary>>,
    case binary:split(Data,?END_TAG,[]) of
        [_NoEndTagFound] ->
            NoEndTagSize = case byte_size(Data) of
                               Sz when Sz<5 -> 0;
                               Sz -> Sz-5
                           end,
            <<NoEndTag1:NoEndTagSize/binary,Buff/binary>> = Data,
            NoEndTag = <<NoEndTag0/binary,NoEndTag1/binary>>,
            {noreply, State0#state{no_end_tag_buff=NoEndTag, buff=Buff}};
        [FirstMsg0,Buff1] ->
            FirstMsg = remove_initial_nl(<<NoEndTag0/binary,FirstMsg0/binary>>),
            SaxArgs = [{event_fun,fun sax_event/3}, {event_state,[]}],
            case xmerl_sax_parser:stream(FirstMsg, SaxArgs) of
                {ok, Simple, _Thrash} ->
                    case decode(Simple, State0#state{no_end_tag_buff= <<>>,
                                                     buff=Buff1}) of
                        {noreply, #state{buff=Buff} = State} when Buff =/= <<>> ->
                            %% Recurse if we have more data in buffer
                            handle_data(<<>>, State);
                        {noreply, _State} = Reply ->
                            Reply
                    end;
                {fatal_error,_Loc,Reason,_EndTags,_EventState} ->
                    error_logger:error_msg("[~p: ~p] error:~p~n", [?MODULE, ?LINE | [Reason]]),
                    handle_error(Reason, State0#state{no_end_tag_buff= <<>>,
                                                      buff= <<>>})
            end
    end.


handle_error(Reason, State) ->
    Pending1 = case State#state.pending of
                   [] -> [];
                   Pending ->
                       %% Assuming the first request gets the
                       %% first answer
                       P=#pending{tref=TRef,ref=Ref,caller=Caller} =
                           lists:last(Pending),
                       cancel_request_timer(Ref, TRef),
                       Reason1 = {failed_to_parse_received_data,Reason},
                       return(Caller, {error,Reason1}),
                       lists:delete(P, Pending)
               end,
    {noreply, State#state{pending=Pending1}}.

%% xml does not accept a leading nl and some netconf server add a nl after
%% each ?END_TAG, ignore them
remove_initial_nl(<<"\n", Data/binary>>) ->
    remove_initial_nl(Data);
remove_initial_nl(Data) ->
    Data.

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

xmlnstag([]) ->
    xmlns;
xmlnstag(Prefix) ->
    list_to_atom("xmlns:"++Prefix).

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


%%%-----------------------------------------------------------------
%%% Decoding of parsed XML data
decode({Tag,Attrs,_} = E, #state{pending = Pending} = State) ->
    case get_local_name_atom(Tag) of
        'rpc-reply' ->
            case get_msg_id(Attrs) of
                undefined ->
                    ?ERROR([{rpc_reply_missing_msg_id, E}]),
                    {noreply,State};
                MsgId ->
                    decode_rpc_reply(MsgId, E, State)
            end;
        hello ->
            case State#state.hello_status of
                undefined ->
                    case decode_hello(E) of
                        {ok,SessionId,Capabilities} ->
                            {noreply,State#state{session_id = SessionId,
                                                 capabilities = Capabilities,
                                                 hello_status = received}};
                        {error,Reason} ->
                            {noreply,State#state{hello_status = {error,Reason}}}
                    end;
                #pending{tref=TRef,ref=Ref} ->
                    cancel_request_timer(Ref,TRef),
                    case decode_hello(E) of
                        {ok,SessionId,Capabilities} ->
                            {noreply,State#state{session_id = SessionId,
                                                 capabilities = Capabilities,
                                                 hello_status = done}};
                        {error,Reason} ->
                            {stop,State#state{hello_status={error,Reason}}}
                    end;
                Other ->
                    ?ERROR([{got_unexpected_hello, E, Other}]),
                    {noreply,State}
            end;
        notification ->
            EventCallback = State#state.event_callback,
            EventCallback(E),
            ?INFO([{notification_received, E}]),
            {noreply,State};
        Other ->
            ?ERROR([{got_unexpected_msg, Other}, {expecting, Pending}])
    end.

get_msg_id(Attrs) ->
    case lists:keyfind('message-id',1,Attrs) of
        {_,Str} ->
            list_to_integer(Str);
        false ->
            undefined
    end.

decode_rpc_reply(MsgId, {_, Attrs, Content0} = E, #state{pending = Pending} = State) ->
    case lists:keytake(MsgId, #pending.msg_id, Pending) of
        {value, #pending{tref=TRef, ref=Ref, op=Op, caller=Caller}, Pending1} ->
            cancel_request_timer(Ref,TRef),
            Content = forward_xmlns_attr(Attrs,Content0),
            {CallerReply, {ServerReply, State2}} =
                do_decode_rpc_reply(Op, Content, State#state{pending=Pending1}),
            return(Caller, CallerReply),
            {ServerReply,State2};
        false ->
            ?ERROR([{got_unexpected_msg_id,MsgId}, {expecting,Pending}, {data, E}]),
            {noreply,State}
    end.

do_decode_rpc_reply(Op,Result,State)
  when Op==lock; Op==unlock; Op==edit_config; Op==delete_config;
       Op==copy_config; Op==kill_session ->
    {decode_ok(Result),{noreply,State}};
do_decode_rpc_reply(Op,Result,State)
  when Op==get; Op==get_config; Op==action ->
    {decode_data(Result),{noreply,State}};
do_decode_rpc_reply(close_session,Result,State) ->
    case decode_ok(Result) of
        ok -> {ok,{stop,State}};
        Other -> {Other,{noreply,State}}
    end;
do_decode_rpc_reply(create_subscription, Result, State) ->
    case decode_ok(Result) of
        ok ->
            {ok, {noreply, State}};
        Other ->
            {Other, {noreply, State}}
    end;
do_decode_rpc_reply(get_event_streams,Result,State) ->
    {decode_streams(decode_data(Result)),{noreply,State}};
do_decode_rpc_reply(undefined,Result,State) ->
    {Result,{noreply,State}}.

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


%% Decode server hello to pick out session id and capabilities
decode_hello({hello,_Attrs,Hello}) ->
    case lists:keyfind('session-id',1,Hello) of
        {'session-id',_,[SessionId]} ->
            case lists:keyfind(capabilities,1,Hello) of
                {capabilities,_,Capabilities} ->
                    case decode_caps(Capabilities,[],false) of
                        {ok,Caps} ->
                            {ok,list_to_integer(SessionId),Caps};
                        Error ->
                            Error
                    end;
                false ->
                    {error,{incorrect_hello,capabilities_not_found}}
            end;
        false ->
            {error,{incorrect_hello,no_session_id_found}}
    end.

decode_caps([{capability,[],[?NETCONF_BASE_CAP++Vsn=Cap]} |Caps], Acc, _) ->
    error_logger:info_msg("[~p: ~p] Vsn: ~p~n", [?MODULE, ?LINE | [Vsn]]),
    case Vsn of
        V when V =:= ?NETCONF_BASE_CAP_VSN orelse V =:= ?NETCONF_BASE_CAP_VSN_1_1 ->
            error_logger:info_msg("[~p: ~p] yes~n", [?MODULE, ?LINE | []]),
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

%%%-----------------------------------------------------------------
%%% transportation stuff
tcp_connect(#options{host=Host, timeout=Timeout, port=Port}) ->
    case gen_tcp:connect(Host, Port, [binary, {packet, 0}], Timeout) of
        {ok, Sock} ->
            ?INFO([{tcp_connected, Host}]),
            {ok, Sock};
        {error, Reason} ->
            ?ERROR([{could_not_connect_to_server, Host},{reason, Reason}]),
            could_not_connect_to_server
    end.

tcp_send(Socket, Data) ->
    case gen_tcp:send(Socket, Data) of
        ok ->
            ?INFO([{tcp_send_data, Data}]),
            ok;
        {error, Reason} ->
            ?ERROR([{tcp_failed_to_send_data, Data}, {reason, Reason}]),
            tcp_failed_to_send_data
    end.

return({To,Ref},Result) ->
    To ! {Ref, Result},
    ok.
%%----------------------------------------------------------------------
%% END OF MODULE
%%----------------------------------------------------------------------
