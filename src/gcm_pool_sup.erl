-module(gcm_pool_sup).

-behaviour(supervisor).

-export([start_link/0, create_pool/4,create_pool/5,delete_pool/1]).
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================
%% @hidden
-spec start_link() -> {ok, pid()} | ignore | {error, {already_started, pid()} | shutdown | term()}.
start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).


%% ===================================================================
%% @doc create new pool.
%% @end
%% ===================================================================
-spec(create_pool(PoolName::atom(), ApiKey::binary() , Size::integer(), OverFlow::integer()) ->
  {ok, pid()} | {error,{already_started, pid()}}).

create_pool(PoolName, ApiKey, Size, OverFlow) ->
  create_pool(local, PoolName, ApiKey, Size, OverFlow).

%% ===================================================================
%% @doc create new pool, selectable name zone global or local.
%% @end
%% ===================================================================
-spec(create_pool(GlobalOrLocal::atom(), PoolName::atom(),  ApiKey::binary(), Size::integer(), OverFlow::integer()) ->
  {ok, pid()} | {error,{already_started, pid()}}).

create_pool(GlobalOrLocal, PoolName, ApiKey, Size, OverFlow)
  when GlobalOrLocal =:= local;
  GlobalOrLocal =:= global ->

  SizeArgs = [{size, Size}, {max_overflow, OverFlow}],
  PoolArgs = [{name, {GlobalOrLocal, PoolName}}, {worker_module, gcm_srv}],
  PoolSpec = poolboy:child_spec(PoolName, PoolArgs ++ SizeArgs, ApiKey),

  supervisor:start_child(?MODULE, PoolSpec).

%% ===================================================================
%% @doc delete pool.
%% @end
%% ===================================================================
-spec(delete_pool(PoolName::atom()) -> ok | {error,not_found}).

delete_pool(PoolName) ->
  supervisor:terminate_child(?MODULE, PoolName),
  supervisor:delete_child(?MODULE, PoolName).


%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
%% @hidden
%-spec init(_) ->  {ok, {{simple_one_for_one, 5, 10}, [{connection, {apns_connection, start_link, []}, transient, 5000, worker, [apns_connection]}]}}.
init(_) ->
  {ok,
    {{one_for_one, 5, 10},
      [
      ]
    }
  }.

