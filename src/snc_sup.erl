%%%-------------------------------------------------------------------
%% @doc snc top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(snc_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%% Helper Macro For Declaring Children Of Supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, temporary, 5000, Type, [I]}).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    {ok, {{one_for_one, 5, 10}, [?CHILD(snc_client_dispatcher, worker)]}}.

%%====================================================================
%% Internal functions
%%====================================================================
