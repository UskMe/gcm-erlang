-module(gcm_srv).
-behaviour(gen_server).

-export([start/2, start/4, stop/1, start_link/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-export([push/3, push/4, sync_push/3, sync_push/4 , push_json/2, push_json/3]).

-define(SERVER, ?MODULE).
-define(RETRY, 3).

-record(state, {key}).

start(Name, Key) ->
    start(Name, Key, 1, 0)
.

start(Name, Key, Size, Overflow) ->
    gcm_pool_sup:create_pool(Name,Key,Size,Overflow)
.

stop(Name) ->
    gcm_pool_sup:delete_pool(Name)
.

push(Name, RegIds, Message) ->
    push(Name, RegIds, Message, ?RETRY)
.

push(Name, RegIds, Message, Retry) ->
    poolboy:transaction(Name, fun(Worker) ->  gen_server:cast(Worker, {send, RegIds, Message, Retry}) end)
.

push_json(Name, Message) ->
  push_json(Name, Message, ?RETRY)
.

push_json(Name, Message, Retry) ->
  poolboy:transaction(Name, fun(Worker) ->  gen_server:cast(Worker, {send, Message, Retry}) end)
.

sync_push(Name, RegIds, Message) ->
    sync_push(Name, RegIds, Message, ?RETRY)
.

sync_push(Name, RegIds, Message, Retry) ->
    poolboy:transaction(Name, fun(Worker) ->  gen_server:cast(Worker, {send, RegIds, Message, Retry}) end)
.

%% OTP
start_link(Key) ->
    gen_server:start_link(?MODULE, [Key], []).

init([Key]) ->
    {ok, #state{key=Key}}.

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};

handle_call({send, RegIds, Message, Retry}, _From, #state{key=Key} = State) ->
    Reply = do_push(RegIds, Message, Key, Retry),
    {reply, Reply, State};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({send, Message, Retry}, #state{key=Key} = State) ->
    io:format("handle cast"),
    do_push_json(Message, Key, Retry),
    {noreply, State}
;
handle_cast({send, RegIds, Message, Retry}, #state{key=Key} = State) ->
  io:format("handle cast oooold"),
  do_push(RegIds, Message, Key, Retry),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}
.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Internal
do_push(_, _, _, 0) ->
    ok;

do_push(RegIds, Message, Key, Retry) ->
    error_logger:info_msg("Sending message: ~p to reg ids: ~p retries: ~p.~n", [Message, RegIds, Retry]),
    case gcm_api:push(RegIds, Message, Key) of
        {ok, GCMResult} ->
            handle_result(GCMResult, RegIds);
        {error, {retry, RetryAfter}} ->
            do_backoff(RetryAfter, RegIds, Message, Retry),
            {error, retry};
        {error, Reason} ->
            {error, Reason}
    end.

%% Internal
do_push_json(_, _, 0) ->
  ok;

do_push_json(Message, Key, Retry) ->
  error_logger:info_msg("Sending message: ~p retries: ~p.~n", [Message, Retry]),
  case gcm_api:push(Message, Key) of
    {ok, GCMResult} ->
      handle_result_json(GCMResult);
    {error, {retry, RetryAfter}} ->
      do_backoff_json(RetryAfter, Message, Retry),
      {error, retry};
    {error, Reason} ->
      {error, Reason}
  end.

handle_result_json(GCMResult) ->
  {_MulticastId, _SuccessesNumber, _FailuresNumber, _CanonicalIdsNumber, Results} = GCMResult %,
  %lists:map(fun({Result, RegId}) -> {RegId, parse(Result)} end, Results)
.

handle_result(GCMResult, RegIds) ->
    {_MulticastId, _SuccessesNumber, _FailuresNumber, _CanonicalIdsNumber, Results} = GCMResult,
    lists:map(fun({Result, RegId}) -> {RegId, parse(Result)} end, lists:zip(Results, RegIds))
.

do_backoff_json(RetryAfter, Message, Retry) ->
  case RetryAfter of
    no_retry ->
      ok;
    _ ->
      error_logger:info_msg("Received retry-after. Will retry: ~p times~n", [Retry-1]),
      timer:apply_after(RetryAfter * 1000, ?MODULE, push_json, [self(), Message, Retry - 1])
  end.

do_backoff(RetryAfter, RegIds, Message, Retry) ->
    case RetryAfter of
        no_retry ->
            ok;
        _ ->
            error_logger:info_msg("Received retry-after. Will retry: ~p times~n", [Retry-1]),
            timer:apply_after(RetryAfter * 1000, ?MODULE, push, [self(), RegIds, Message, Retry - 1])
    end.

parse(Result) ->
    case {
      proplists:get_value(<<"error">>, Result),
      proplists:get_value(<<"message_id">>, Result),
      proplists:get_value(<<"registration_id">>, Result)
     } of
        {Error, undefined, undefined} ->
            Error;
        {undefined, _MessageId, undefined}  ->
            ok;
        {undefined, _MessageId, NewRegId} ->
            {<<"NewRegistrationId">>, NewRegId}
    end.
