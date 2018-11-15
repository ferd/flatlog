-module(prop_flatlog).
-compile(export_all).
-include_lib("proper/include/proper.hrl").
-include_lib("stdlib/include/assert.hrl").

prop_end_to_end(doc) ->
    "log message and formatting can take place over the logger API".
prop_end_to_end() ->
    ?SETUP(fun setup/0,
    ?FORALL({Lvl, Msg, Meta}, {level(), log_map(), meta()},
        begin
            logger:Lvl(Msg, Meta),
            true % this property fails on teardown when failing
        end)).

prop_map_keys(doc) ->
    "all keys of a map can be found in the log line".
prop_map_keys() ->
    ?FORALL({Event, Cfg}, {inner_call(), config()},
        begin
            Line = flatlog:format(Event, Cfg),
            #{msg := {report, Msg}} = Event,
            {Map, Rest} = parse_kv(Line),
            Res = maps:filter(
                fun(K, _) ->
                    SK = format(K),
                    maps:find(SK, Map) =:= error
                end,
                Msg
            ),
            case map_size(Res) == 0 of
                true -> Rest == [];
                false ->
                    io:format("Generated log: ~ts => ~p~n", [Line, Res]),
                    false
            end
        end).

prop_nested_map_keys(doc) ->
    "all keys of a nested map can be found in the log line with the proper "
    "key prefixes".
prop_nested_map_keys() ->
    ?FORALL({Event, Cfg}, {inner_call_nested(), config()},
        begin
            Line = flatlog:format(Event, Cfg),
            #{msg := {report, Msg}} = Event,
            Map = parse_nested_map(Line),
            Keys = flattened_keys(Msg),
            Res = lists:filter(fun(K) ->
                    SK = [format(KPart) || KPart <- K],
                    recursive_lookup(SK, Map) =:= error
                end,
                Keys
            ),
            case Res of
                [] ->
                    true;
                _ ->
                    io:format("Msg ~p~n Generated log: ~ts => ~p~n",
                              [Msg, Line, Res]),
                    false
            end
        end).

prop_meta(doc) ->
    "The metadata fields are rendered fine without interference from the data".

prop_meta() ->
    ?FORALL({Lvl, Msg, Meta, Cfg}, {level(), meta(), meta(), config()},
        begin
            Event = #{level => Lvl, msg => {report, Msg}, meta => Meta},
            Line = flatlog:format(Event, Cfg),
            {Map, _} = parse_kv(Line),
            ExpectedLevel = format(Lvl),
            ExpectedTime = calendar:system_time_to_rfc3339(
                maps:get(time, Meta),
                [{unit, microsecond}, {offset, 0},
                 {time_designator, $T}]
            ),
            %% pid is a dupe value between the default template and the
            %% submitted message; by parsing order, the Msg pid is last
            %% and should be expected in the parsed result.
            ExpectedPid = format(maps:get(pid, Msg)),
            case Map of
                #{"pid" := ExpectedPid,
                  "level" := ExpectedLevel,
                  "when" := ExpectedTime} ->
                    true;
                _ ->
                    io:format("non-matching line~n~s parsed as ~p~n", [Line, Map]),
                    io:format("expected ~p~n",
                              [#{"pid" => ExpectedPid,
                                 "level" => ExpectedLevel,
                                 "when" => ExpectedTime}]),
                    false
            end
        end).

prop_string_printable(doc) ->
    "unescaped strings do not require quotation marks".
prop_string_printable() ->
    ?FORALL(S, printable([{escape, false}, {quote, false}]),
        begin
            Formatted = flatlog:to_string(S, #{term_depth => undefined}),
            re:run(Formatted, "^<<.*>>$", [unicode, dotall]) == nomatch andalso
            re:run(Formatted, "^\".*\"$", [unicode, dotall]) == nomatch andalso
            re:run(Formatted, "[\n\r\n\\\\]", [unicode, dotall]) == nomatch
        end).

prop_string_quotable(doc) ->
    "strings containing = or spaces are quotable and surrounded by quotes".
prop_string_quotable() ->
    ?FORALL(S, printable([{escape, false}, {quote, true}]),
        begin
            Formatted = flatlog:to_string(S, #{term_depth => undefined}),
            re:run(Formatted, "^<<.*>>$", [unicode, dotall]) == nomatch andalso
            re:run(Formatted, "^\".*\"$", [unicode, dotall]) =/= nomatch andalso
            re:run(Formatted, "[\n\r\n\\\\]", [unicode, dotall]) == nomatch
        end).

prop_string_escapable(doc) ->
    "strings that contain escapable characters are quoted; also ensure that "
    "binaries never contain <<>> as long as they're printable".
prop_string_escapable() ->
    ?FORALL(S, printable([{escape, true}]),
        begin
            Formatted = flatlog:to_string(S, #{term_depth => undefined}),
            (re:run(Formatted, "^<<.*>>$", [unicode, dotall]) =/= nomatch orelse
             re:run(Formatted, "^\".*\"$", [unicode, dotall]) =/= nomatch) andalso
            re:run(Formatted, "[\n\r\n\\\\]", [unicode, dotall]) =/= nomatch andalso
            re:run(Formatted, "^<<\".*\">>$", [unicode, dotall]) == nomatch
        end).

prop_string_unescapable(doc) ->
    "unescapable strings or binaries revert to their byte-level output (as in "
    "printing with ~w)".
prop_string_unescapable() ->
    ?FORALL(S, unprintable(),
        begin
            Formatted = flatlog:to_string(S, #{term_depth => undefined}),
            re:run(Formatted, "^\"?\\[(.+,?)*\\]\"?$") =/= nomatch orelse
            re:run(Formatted, "^<<([0-9:]+,?)+>>$") =/= nomatch
        end).

prop_empty_keys(doc) ->
    "empty keys are supported and show up as literally nothing".
prop_empty_keys() ->
    ?FORALL({Lvl, Msg, Meta, Cfg, K, V},
            {level(), meta(), meta(), config(),
             oneof([<<>>, "", '']), printable([])},
        begin
            Event = #{level => Lvl,
                      msg => {report, Msg#{K => V}},
                      meta => Meta},
            Line = flatlog:format(Event, Cfg),
            string:find(Line, [" =",format(V)]) =/= nomatch
        end).

prop_empty_vals(doc) ->
    "empty values are supported and show up as literally nothing".
prop_empty_vals() ->
    ?FORALL({Lvl, Msg, Meta, Cfg, K, V},
            {level(), meta(), meta(), config(),
             printable([]), oneof([<<>>, "", ''])},
        begin
            Event = #{level => Lvl,
                      msg => {report, Msg#{K => V}},
                      meta => Meta},
            Line = flatlog:format(Event, Cfg),
            string:find(Line, [format(K),"= "]) =/= nomatch
        end).

%%%%%%%%%%%%%%%
%%% HELPERS %%%
%%%%%%%%%%%%%%%
setup() ->
    Handler = #{
      config => #{},
      level => all,
      filter_default => log,
      formatter => {flatlog, #{}}
     },
    logger:add_handler_filter(
      default,
      test_run,
      {fun(Event = #{meta := M}, _) ->
         case maps:get(test_meta, M, false) of
             true -> stop;
             false -> Event
         end
       end, ok}
     ),
    logger:add_handler(structured, silent_logger, Handler),
    fun() ->
        logger:remove_handler(structured),
        logger:remove_handler_filter(default, test_run)
    end.

parse_nested_map(Str) ->
    {Map, _} = parse_kv(Str),
    %% Break up the map into sets of nested key vals...
    %%   #{a_b_c => x, a_b_d => x, a_c => y}
    %% yields
    %%   #{[a,b,c] => x, [a,b,d] => x, [a,c] => y}
    Split = [{string:split(K, "_", all), V}
             || {K, V} <- maps:to_list(Map)],
    %% Merge maps according to prefixes:
    %% [{a => #{b => #{c => x, d => x}, c => y}}]
    merge_down(lists:sort(Split)).

merge_down(List) -> merge_down(List, #{}).

merge_down([], Map) -> Map;
merge_down([{K, V} | Rest], Map) ->
    merge_down(Rest, insert_into(K, V, Map)).

insert_into([K], V, Map) ->
    Map#{K => V};
insert_into([H|T], V, Map) ->
    SubMap = maps:get(H, Map, #{}),
    Map#{H => insert_into(T, V, SubMap)}.

parse_kv(Str) -> parse_k(Str, #{}).

parse_k(Str0, Map) ->
    Str = string:trim(Str0, leading, " "),
    case string:next_grapheme(Str) of
        [$\n | Rest] -> {Map, Rest};
        [$" | Rest] -> parse_quoted_k(Rest, "", Map);
        _ -> parse_k(Str, "", Map)
    end.

parse_k(Str, Acc, Map) ->
    case string:next_grapheme(Str) of
        [$= | Rest] -> parse_v(Rest, lists:reverse(Acc), Map);
        [G | Rest] -> parse_k(Rest, [G|Acc], Map)
    end.

parse_quoted_k(Str, Acc, Map) ->
    case string:next_grapheme(Str) of
        [$" | Rest] ->
            parse_k(Rest, Acc, Map);
        [$\\ | Next] ->
            [G | Rest] = string:next_grapheme(Next),
            parse_quoted_k(Rest, [G|Acc], Map);
        [G | Rest] ->
            parse_quoted_k(Rest, [G|Acc], Map)
    end.

parse_v(Str, Key, Map) ->
    case string:next_grapheme(Str) of
        [$" | Rest] -> parse_quoted_v(Rest, Key, "", Map);
        _ -> parse_v(Str, Key, "", Map)
    end.

parse_v(Str, Key, Acc, Map) ->
    case string:next_grapheme(Str) of
        [$\n | Rest] -> {Map#{Key => lists:reverse(Acc)}, Rest};
        [$\s | _] -> parse_k(Str, Map#{Key => lists:reverse(Acc)});
        [G | Rest] -> parse_v(Rest, Key, [G|Acc], Map)
    end.

parse_quoted_v(Str, Key, Acc, Map) ->
    case string:next_grapheme(Str) of
        [$" | Rest] ->
            parse_v(Rest, Key, Acc, Map);
        [$\\ | Next] ->
            [G | Rest] = string:next_grapheme(Next),
            parse_quoted_v(Rest, Key, [G|Acc], Map);
        [G | Rest] ->
            parse_quoted_v(Rest, Key, [G|Acc], Map)
    end.

flattened_keys(Map) -> flattened_keys(Map, []).

flattened_keys(Map, Parents) ->
    maps:fold(fun(K, V, Acc) when is_map(V) ->
                    flattened_keys(V, [K|Parents]) ++ Acc
              ;  (K, _, Acc) ->
                    [lists:reverse(Parents, [K]) | Acc]
                end, [], Map).

recursive_lookup([K], Map) -> maps:find(K, Map);
recursive_lookup([H|T], Map) ->
    case maps:find(H, Map) of
        {ok, NewMap} -> recursive_lookup(T, NewMap);
        error -> error
    end.

format(K) when is_tuple(K) ->
    lists:flatten(io_lib:format("~0tp", [K]));
format(K) when is_integer(K) ->
    integer_to_list(K);
format(K) when is_float(K) ->
    lists:flatten(io_lib:format("~0tp", [K]));
format(K) ->
    lists:flatten(io_lib:format("~ts", [K])).


%%%%%%%%%%%%%%%%%%
%%% GENERATORS %%%
%%%%%%%%%%%%%%%%%%
inner_call() ->
    ?LET({Lvl, Msg, Meta}, {level(), printable_log_map(), meta()},
         #{level => Lvl, msg => {report, Msg}, meta => Meta}).

inner_call_nested() ->
    ?LET({Lvl, Msg, Meta}, {level(), printable_nested_log_map(), meta()},
         #{level => Lvl, msg => {report, Msg}, meta => Meta}).

level() ->
    oneof([emergency, alert, critical, error, warning, notice, info, debug]).

meta() ->
    ?LET(
       {Mandatory, Optional},
       {[{time, integer()},
         {test_meta, true}, % used to filter output of test runs from default
         {mfa, oneof([{atom(), atom(), non_neg_integer()},
                      {atom(), atom(), list(term())},
                      string()])},
         {pid, pid()},
         {line, pos_integer()}],
        list(oneof([
           {id, oneof([string(), binary()])},
           {parent_id, oneof([string(), binary()])},
           {correlation_id, oneof([string(), binary()])},
           {"extra", term()}
        ]))},
       maps:merge(maps:from_list(Optional), maps:from_list(Mandatory))
      ).

log_map() ->
    map(oneof([string(), atom(), binary()]), term()).

printable_log_map() ->
    ?LET(S,
         non_empty(list(
            oneof([choose($0,$9), choose($a, $z), choose($A, $Z), $_, $-, $\s])
         )),
         map(oneof([S, list_to_atom(S), iolist_to_binary(S)]),
             term())
    ).

printable_nested_log_map() -> printable_nested_log_map(3).

printable_nested_log_map(0) -> "cut";
printable_nested_log_map(N) ->
    frequency([
        {5, ?LAZY(
            ?LET(L, non_empty(list({nesting_key(),
                                    ?SUCHTHAT(T, term(), not is_map(T))})),
                 maps:from_list(L))
        )},
        {1, ?LAZY(
            ?LET(L, list({nesting_key(), printable_nested_log_map(N-1)}),
                 maps:from_list(L))
        )}
    ]).

nesting_key() ->
    ?LET(S,
         non_empty(list(
            oneof([choose($0,$9), choose($a, $z), choose($A, $Z), $-])
         )),
         oneof([S, list_to_atom(S), unicode:characters_to_binary(S)])).

printable(Props) ->
    Escape = proplists:get_value(escape, Props, false),
    Quote = proplists:get_value(quote, Props, false),
    Printable = case io:printable_range() of
        latin1 ->
            ?SUCHTHAT(S, list(range(0,255)), io_lib:printable_list(S));
        unicode ->
            ?LET(S, utf8(), unicode:characters_to_list(S))
    end,
    String = case {Escape, Quote} of
        {true, _} ->
            ?SUCHTHAT(S,
                      ?LET(S, non_empty(list(oneof([Printable, "\"", "\n", "\r\n", "\\"]))),
                           lists:flatten(S)),
                      re:run(S, "[\"\n\r\n\\\\]", [unicode]) =/= nomatch);
        {false, true} ->
            ?SUCHTHAT(
              Str,
              ?LET(S, non_empty(list(oneof([" ", "=", Printable]))),
                 [Char || Char <- lists:flatten(S),
                          not lists:member(Char, [$", $\n, $\r, $\\])]),
              re:run(Str, "[ =]", [unicode]) =/= nomatch
            );
        {false, false} ->
            ?LET(S, Printable,
                 [Char || Char <- S,
                          not lists:member(Char, [$", $\s, $=, $\n, $\r, $\\])])
    end,
    ?LET(S, String,
         oneof([S, unicode:characters_to_binary(S), list_to_atom(S)]
               ++ case Escape orelse Quote of
                    false -> [number()];
                    true -> []
                  end)).

unprintable() ->
    oneof([non_empty(list([atom(), float()])),
           ?SUCHTHAT(B, non_empty(bitstring()),
                     bit_size(B) rem 8 =/= 0),
           ?SUCHTHAT(B, non_empty(binary()),
                     not (io_lib:printable_list(binary_to_list(B))
                          orelse io_lib:printable_list(unicode:characters_to_list(B))))
          ]).


%% fake pid, otherwise we can't store counterexamples
pid() ->
    ?LET(N, pos_integer(), "<0." ++ integer_to_list(N) ++ ".0>").

config() ->
    ?LET(List,
         [{unicode, boolean()}],
         maps:from_list(List)).
