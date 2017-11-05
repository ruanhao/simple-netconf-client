%%%-------------------------------------------------------------------
%%% @author Hao Ruan <ruanhao1116@google.com>
%%% @copyright (C) 2017, Hao Ruan
%%% @doc
%%%
%%% @end
%%% Created :  5 Nov 2017 by Hao Ruan <ruanhao1116@google.com>
%%%-------------------------------------------------------------------
-module(snc_prototype).
-compile(export_all).
%% Default port number (RFC 4742/IANA).
-define(DEFAULT_PORT, 830).

%% Default timeout to wait for netconf server to reply to a request
-define(DEFAULT_TIMEOUT, infinity). %% msec

%% Namespaces
-define(NETCONF_NAMESPACE,"urn:ietf:params:xml:ns:netconf:base:1.0").
-define(NETCONF_NAMESPACE_ATTR,[{xmlns,?NETCONF_NAMESPACE}]).
-define(ACTION_NAMESPACE_ATTR,[{xmlns,?ACTION_NAMESPACE}]).
-define(NETCONF_NOTIF_NAMESPACE_ATTR,[{xmlns,?NETCONF_NOTIF_NAMESPACE}]).
-define(NETMOD_NOTIF_NAMESPACE_ATTR,[{xmlns,?NETMOD_NOTIF_NAMESPACE}]).


-define(ACTION_NAMESPACE,"urn:com:ericsson:ecim:1.0").
-define(NETCONF_NOTIF_NAMESPACE,
        "urn:ietf:params:xml:ns:netconf:notification:1.0").
-define(NETMOD_NOTIF_NAMESPACE,"urn:ietf:params:xml:ns:netmod:notification").

%% Capabilities
-define(NETCONF_BASE_CAP,"urn:ietf:params:netconf:base:").
-define(NETCONF_BASE_CAP_VSN,"1.0").
-define(NETCONF_BASE_CAP_VSN_1_1,"1.1").

%% Misc
-define(END_TAG,<<"]]>]]>">>).

-define(FORMAT(_F, _A), lists:flatten(io_lib:format(_F, _A))).


-define(error(ConnName,Report),
        error_logger:error_report([{ct_connection,ConnName},
                                   {client,self()},
                                   {module,?MODULE},
                                   {line,?LINE} |
                                   Report])).

-define(is_timeout(T), (is_integer(T) orelse T==infinity)).
-define(is_filter(F),
        (?is_simple_xml(F)
         orelse (F==[])
         orelse (is_list(F) andalso ?is_simple_xml(hd(F))))).
-define(is_simple_xml(Xml),
        (is_atom(Xml) orelse (is_tuple(Xml) andalso is_atom(element(1,Xml))))).
-define(is_string(S), (is_list(S) andalso is_integer(hd(S)))).

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-include_lib("xmerl/include/xmerl.hrl").

%% Logging information for error handler
-record(conn_log, {header=true,
                   client,
                   name,
                   address,
                   conn_pid,
                   action,
                   module}).

%% Client state
-record(state, {
          sock,
          host,
          port,
          connection,      % #connection
          capabilities,
          session_id,
          msg_id = 1,
          hello_status,
          no_end_tag_buff = <<>>,
          buff = <<>>,
          pending = [],    % [#pending]
          event_receiver}).% pid


%% Run-time client options.
-record(options, {ssh = [], % Options for the ssh application
                  host,
                  port = ?DEFAULT_PORT,
                  timeout = ?DEFAULT_TIMEOUT,
                  name,
                  type}).

%% Connection reference
-record(connection, {reference, % {CM,Ch}
                     host,
                     port,
                     name,
                     type}).

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
    process_flag(trap_exit, true),

    {ok, Sock} = gen_tcp:connect("10.74.68.81", 48443, [binary, {packet, 0}]),
    {ok, #state{sock=Sock}, 0}.

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
handle_call(get_scheme, _From, #state{sock=Sock}=State) ->
    Filter = [{'netconf-state', [],[{schemas, []}]}],
    MsgId = State#state.msg_id,
    SimpleXml = encode_rpc_operation(get, [Filter]),
    Bin = snc_utils:indent(to_xml_doc({rpc,
                      [{'message-id',MsgId} | ?NETCONF_NAMESPACE_ATTR],
                      [SimpleXml]})),
    error_logger:info_msg("[~p: ~p] Bin: ~p~n", [?MODULE, ?LINE | [Bin]]),
    gen_tcp:send(Sock, Bin),
    {reply, ok, State};
handle_call(Request, _From, State) ->
    error_logger:info_msg("[~p: ~p] ~p~n", [?MODULE, ?LINE | [State]]),
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
handle_info({tcp, Sock, Data}, State) ->
    error_logger:info_msg("[~p: ~p] receive: ~p~n", [?MODULE, ?LINE | [Data]]),
    handle_data(Data, State);
handle_info(timeout, #state{sock=Sock} = State) ->
    error_logger:info_msg("[~p: ~p] sending client hello msg~n", [?MODULE, ?LINE | []]),
    HelloSimpleXml = client_hello([%{capability, [?NETCONF_BASE_CAP ++ ?NETCONF_BASE_CAP_VSN_1_1]},
                                   {capability, ["urn:ietf:params:netconf:capability:exi:1.0"]}]),
    Bin = snc_utils:indent(to_xml_doc(HelloSimpleXml)),
    gen_tcp:send(Sock, Bin),
    {noreply, State};
handle_info(Info, State) ->
    error_logger:info_msg("[~p: ~p] Info: ~p~n", [?MODULE, ?LINE | [Info]]),
    {noreply, State}.


%    {noreply, State}.

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
call(Client, Msg) ->
    call(Client, Msg, infinity, false).
call(Client, Msg, Timeout) when is_integer(Timeout); Timeout==infinity ->
    call(Client, Msg, Timeout, false);
call(Client, Msg, WaitStop) when is_boolean(WaitStop) ->
    call(Client, Msg, infinity, WaitStop).
call(Client, Msg, Timeout, WaitStop) ->
    case get_handle(Client) of
        {ok,Pid} ->
            case ct_gen_conn:call(Pid,Msg,Timeout) of
                {error,{process_down,Pid,noproc}} ->
                    {error,no_such_client};
                {error,{process_down,Pid,normal}} when WaitStop ->
                    %% This will happen when server closes connection
                    %% before client received rpc-reply on
                    %% close-session.
                    ok;
                {error,{process_down,Pid,normal}} ->
                    {error,closed};
                {error,{process_down,Pid,Reason}} ->
                    {error,{closed,Reason}};
                Other when WaitStop ->
                    MRef = erlang:monitor(process,Pid),
                    receive
                        {'DOWN',MRef,process,Pid,Normal} when Normal==normal;
                                                              Normal==noproc ->
                            Other;
                        {'DOWN',MRef,process,Pid,Reason} ->
                            {error,{{closed,Reason},Other}}
                    after Timeout ->
                            erlang:demonitor(MRef, [flush]),
                            {error,{timeout,Other}}
                    end;
                Other ->
                    Other
            end;
        Error ->
            Error
    end.

get_handle(Client) when is_pid(Client) ->
    {ok,Client};
get_handle(Client) ->
    case ct_util:get_connection(Client, ?MODULE) of
        {ok,{Pid,_}} ->
            {ok,Pid};
        {error,no_registered_connection} ->
            {error,{no_connection_found,Client}};
        Error ->
            Error
    end.

check_options(OptList,Options) ->
    check_options(OptList,undefined,undefined,Options).

check_options([], undefined, _Port, _Options) ->
    {error, no_host_address};
check_options([], _Host, undefined, _Options) ->
    {error, no_port};
check_options([], Host, Port, Options) ->
    {Host,Port,Options};
check_options([{ssh, Host}|T], _, Port, Options) ->
    check_options(T, Host, Port, Options#options{host=Host});
check_options([{port,Port}|T], Host, _, Options) ->
    check_options(T, Host, Port, Options#options{port=Port});
check_options([{timeout, Timeout}|T], Host, Port, Options)
  when is_integer(Timeout); Timeout==infinity ->
    check_options(T, Host, Port, Options#options{timeout = Timeout});
check_options([{timeout, _} = Opt|_T], _Host, _Port, _Options) ->
    {error, {invalid_option, Opt}};
check_options([Opt|T], Host, Port, #options{ssh=SshOpts}=Options) ->
    %% Option verified by ssh
    check_options(T, Host, Port, Options#options{ssh=[Opt|SshOpts]}).

check_session_options([],Options) ->
    {ok,Options};
check_session_options([{timeout, Timeout}|T], Options)
  when is_integer(Timeout); Timeout==infinity ->
    check_session_options(T, Options#options{timeout = Timeout});
check_session_options([Opt|_T], _Options) ->
    {error, {invalid_option, Opt}}.


%%%-----------------------------------------------------------------
set_request_timer(infinity) ->
    {undefined,undefined};
set_request_timer(T) ->
    Ref = make_ref(),
    {ok,TRef} = timer:send_after(T,{Ref,timeout}),
    {Ref,TRef}.

%%%-----------------------------------------------------------------
cancel_request_timer(undefined,undefined) ->
    ok;
cancel_request_timer(Ref,TRef) ->
    _ = timer:cancel(TRef),
    receive {Ref,timeout} -> ok
    after 0 -> ok
    end.

%%%-----------------------------------------------------------------
client_hello(Options) when is_list(Options) ->
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
encode_rpc_operation({create_subscription,_},
                     [Stream,Filter,StartTime,StopTime]) ->
    {'create-subscription',?NETCONF_NOTIF_NAMESPACE_ATTR,
     [{stream,[Stream]}] ++
         filter(Filter) ++
         maybe_element(startTime,StartTime) ++
         maybe_element(stopTime,StopTime)}.

%% filter(undefined) ->
%%     [];
%% filter({xpath,Filter}) when ?is_string(Filter) ->
%%     [{filter,[{type,"xpath"},{select, Filter}],[]}];
%% filter(Filter) when is_list(Filter) ->
%%     [{filter,[{'xmlns:ns0', "urn:ietf:params:xml:ns:netconf:base:1.0"},
%%               {'ns0:type',"subtree"}],Filter}];
%% filter(Filter) ->
%%     filter([Filter]).

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

%%%-----------------------------------------------------------------
%%% Send XML data to server
do_send_rpc(PendingOp,SimpleXml,Timeout,Caller,
            #state{connection=Connection,msg_id=MsgId,pending=Pending} = State) ->
    case do_send_rpc(Connection, MsgId, SimpleXml) of
        ok ->
            {Ref,TRef} = set_request_timer(Timeout),
            {noreply, State#state{msg_id=MsgId+1,
                                  pending=[#pending{tref=TRef,
                                                    ref=Ref,
                                                    msg_id=MsgId,
                                                    op=PendingOp,
                                                    caller=Caller} | Pending]}};
        Error ->
            {reply, Error, State#state{msg_id=MsgId+1}}
    end.

do_send_rpc(Connection, MsgId, SimpleXml) ->
    do_send(Connection,
            {rpc,
             [{'message-id',MsgId} | ?NETCONF_NAMESPACE_ATTR],
             [SimpleXml]}).

do_send(Connection, SimpleXml) ->
    Xml=to_xml_doc(SimpleXml),
    ssh_send(Connection, Xml).

to_xml_doc(Simple) ->
    Prolog = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
    Xml = unicode:characters_to_binary(
            xmerl:export_simple([Simple],
                                xmerl_xml,
                                [#xmlAttribute{name=prolog,
                                               value=Prolog}])),
    <<Xml/binary,?END_TAG/binary>>.

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
            error_logger:info_msg("[~p: ~p] noreply~n", [?MODULE, ?LINE | []]),
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


%% xml does not accept a leading nl and some netconf server add a nl after
%% each ?END_TAG, ignore them
remove_initial_nl(<<"\n", Data/binary>>) ->
    remove_initial_nl(Data);
remove_initial_nl(Data) ->
    Data.

handle_error(Reason, State) ->
    Pending1 = case State#state.pending of
                   [] -> [];
                   Pending ->
                       %% Assuming the first request gets the
                       %% first answer
                       P=#pending{tref=TRef,ref=Ref,caller=Caller} =
                           lists:last(Pending),
                       cancel_request_timer(Ref,TRef),
                       Reason1 = {failed_to_parse_received_data,Reason},
                       ct_gen_conn:return(Caller,{error,Reason1}),
                       lists:delete(P,Pending)
               end,
    {noreply, State#state{pending=Pending1}}.

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
decode({Tag,Attrs,_}=E, #state{connection=Connection,pending=Pending}=State) ->
    %ConnName = Connection#connection.name,
    case get_local_name_atom(Tag) of
        'rpc-reply' ->
            case get_msg_id(Attrs) of
                undefined ->
                    error_logger:error_msg("[~p: ~p] rpc_reply_missing_msg_id ~n", [?MODULE, ?LINE | []]),
                    {noreply,State};
                MsgId ->
                    decode_rpc_reply(MsgId,E,State)
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
                #pending{tref=TRef,ref=Ref,caller=Caller} ->
                    cancel_request_timer(Ref,TRef),
                    case decode_hello(E) of
                        {ok,SessionId,Capabilities} ->
                            ct_gen_conn:return(Caller,ok),
                            {noreply,State#state{session_id = SessionId,
                                                 capabilities = Capabilities,
                                                 hello_status = done}};
                        {error,Reason} ->
                            ct_gen_conn:return(Caller,{error,Reason}),
                            {stop,State#state{hello_status={error,Reason}}}
                    end;
                Other ->
                    error_logger:error_msg("[~p: ~p] got_unexpected_hello: ~p, ~p, ~n",
                                           [?MODULE, ?LINE | [E, Other]]),
                    {noreply,State}
            end;
        notification ->
            EventReceiver = State#state.event_receiver,
            EventReceiver ! E,
            {noreply,State};
        Other ->
            %% Result of send/2, when not sending an rpc request - or
            %% if netconf server sends noise. Can handle this only if
            %% there is just one pending that matches (i.e. has
            %% undefined msg_id and op)
            %% case [P || P = #pending{msg_id=undefined,op=undefined} <- Pending] of
            %%     [#pending{tref=TRef,ref=Ref,caller=Caller}] ->
            %%         cancel_request_timer(Ref,TRef),
            %%         ct_gen_conn:return(Caller,E),
            %%         {noreply,State#state{pending=[]}};
            %%     _ ->
            %%         ?error(ConnName,[{got_unexpected_msg,Other},
            %%                          {expecting,Pending}]),
            %%         {noreply,State}
            %% end

            error_logger:error_msg("[~p: ~p] unexpected msg: ~p~n", [?MODULE, ?LINE | [Other]])

    end.

get_msg_id(Attrs) ->
    case lists:keyfind('message-id',1,Attrs) of
        {_,Str} ->
            list_to_integer(Str);
        false ->
            undefined
    end.

decode_rpc_reply(MsgId,{_,Attrs,Content0}=E,#state{pending=Pending} = State) ->
    case lists:keytake(MsgId,#pending.msg_id,Pending) of
        {value, #pending{tref=TRef,ref=Ref,op=Op,caller=Caller}, Pending1} ->
            cancel_request_timer(Ref,TRef),
            Content = forward_xmlns_attr(Attrs,Content0),
            {CallerReply,{ServerReply,State2}} =
                do_decode_rpc_reply(Op,Content,State#state{pending=Pending1}),
            ct_gen_conn:return(Caller,CallerReply),
            {ServerReply,State2};
        false ->
            %% Result of send/2, when receiving a correct
            %% rpc-reply. Can handle this only if there is just one
            %% pending that matches (i.e. has undefined msg_id and op)
            case [P || P = #pending{msg_id=undefined,op=undefined} <- Pending] of
                [#pending{tref=TRef,
                          ref=Ref,
                          msg_id=undefined,
                          op=undefined,
                          caller=Caller}] ->
                    cancel_request_timer(Ref,TRef),
                    ct_gen_conn:return(Caller,E),
                    {noreply,State#state{pending=[]}};
                _ ->
                    ConnName = (State#state.connection)#connection.name,
                    ?error(ConnName,[{got_unexpected_msg_id,MsgId},
                                     {expecting,Pending}]),
                    {noreply,State}
            end
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
do_decode_rpc_reply({create_subscription,Caller},Result,State) ->
    case decode_ok(Result) of
        ok ->
            {ok,{noreply,State#state{event_receiver=Caller}}};
        Other ->
            {Other,{noreply,State}}
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
%%% Logging

log(Connection,Action) ->
    log(Connection,Action,<<>>).
log(#connection{reference=Ref,host=Host,port=Port,name=Name},Action,Data) ->
    Address =
        case Ref of
            {_,Ch} -> {Host,Port,Ch};
            _ -> {Host,Port}
        end,
    error_logger:info_report(#conn_log{client=self(),
                                       address=Address,
                                       name=Name,
                                       action=Action,
                                       module=?MODULE},
                             Data).


%%%-----------------------------------------------------------------
%%% SSH stuff
ssh_connect(#options{host=Host,timeout=Timeout,port=Port,
                     ssh=SshOpts,name=Name,type=Type}) ->
    case ssh:connect(Host, Port,
                     [{user_interaction,false},
                      {silently_accept_hosts, true}|SshOpts],
                     Timeout) of
        {ok,CM} ->
            Connection = #connection{reference = CM,
                                     host = Host,
                                     port = Port,
                                     name = Name,
                                     type = Type},
            log(Connection,connect),
            {ok,Connection};
        {error,Reason} ->
            {error,{ssh,could_not_connect_to_server,Reason}}
    end.

ssh_channel(#connection{reference=CM}=Connection0,
            #options{timeout=Timeout,name=Name,type=Type}) ->
    case ssh_connection:session_channel(CM, Timeout) of
        {ok,Ch} ->
            case ssh_connection:subsystem(CM, Ch, "netconf", Timeout) of
                success ->
                    Connection = Connection0#connection{reference = {CM,Ch},
                                                        name = Name,
                                                        type = Type},
                    log(Connection,open),
                    {ok, Connection};
                failure ->
                    ssh_connection:close(CM,Ch),
                    {error,{ssh,could_not_execute_netconf_subsystem}};
                {error,timeout} ->
                    ssh_connection:close(CM,Ch),
                    {error,{ssh,could_not_execute_netconf_subsystem,timeout}}
            end;
        {error, Reason} ->
            {error,{ssh,could_not_open_channel,Reason}}
    end.


ssh_open(Options) ->
    case ssh_connect(Options) of
        {ok,Connection} ->
            case ssh_channel(Connection,Options) of
                {ok,_} = Ok ->
                    Ok;
                Error ->
                    ssh_close(Connection),
                    Error
            end;
        Error ->
            Error
    end.

ssh_send(#connection{reference = {CM,Ch}}=Connection, Data) ->
    case ssh_connection:send(CM, Ch, Data) of
        ok ->
            log(Connection,send,Data),
            ok;
        {error,Reason} ->
            {error,{ssh,failed_to_send_data,Reason}}
    end.

ssh_close(Connection=#connection{reference = {CM,Ch}, type = Type}) ->
    _ = ssh_connection:close(CM,Ch),
    log(Connection,close),
    case Type of
        connection_and_channel ->
            ssh_close(Connection#connection{reference = CM});
        _ ->
            ok
    end,
    ok;
ssh_close(Connection=#connection{reference = CM}) ->
    _ = ssh:close(CM),
    log(Connection,disconnect),
    ok.


%%----------------------------------------------------------------------
%% END OF MODULE
%%----------------------------------------------------------------------
test() ->
    Filter = [{netconf_state, [{xmlns, "urn:ietf:params:xml:ns:yang:ietf-netconf-monitoring"}],[{schemas, []}]}],
    MsgId = 1,
    SimpleXml = encode_rpc_operation(get, [Filter]),
    Bin = snc_utils:indent(to_xml_doc({rpc,
                      [{'message-id',MsgId} | ?NETCONF_NAMESPACE_ATTR],
                                       [SimpleXml]})),

    Bin.