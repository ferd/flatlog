-module(flatlog_SUITE).
-compile(export_all).
-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

all() ->
    [term_depth, map_depth, unstructured, colored].

term_depth() ->
    [{docs, "Once a term is too deep, it gets continued with `...'"}].
term_depth(_) ->
    ?assertEqual(
       "\"[\\\"01234567890123456789\\\",abc,[d,e|...]]\"",
        lists:flatten(flatlog:to_string(
          ["01234567890123456789",abc,[d,e,[f,g,h]]]
          , #{term_depth => 6}
        ))
    ),
    ok.

map_depth() ->
    [{docs, "A max number of nesting in maps can be provided"}].
map_depth(_) ->
    %% Use custom templates to drop metadata/templates
    Template = [msg],
    Map = #{a => #{b => #{c => #{d => x}},
                   f => g},
            1 => #{2 => #{3 => x}}},
    ?assertEqual(
        "a_f=g a_b_c=... 1_2_3=x ",
        lists:flatten(
          flatlog:format(#{level => info, msg => {report, Map}, meta => #{}},
                         #{template => Template,
                           map_depth => 3})
        )
    ),
    ?assertEqual(
        "a=... 1=... ",
        lists:flatten(
          flatlog:format(#{level => info, msg => {report, Map}, meta => #{}},
                         #{template => Template,
                           map_depth => 1})
        )
    ),

    ok.

unstructured() ->
    [{docs, "logs that aren't structured get passed through with a re-frame"}].
unstructured(_) ->
    ?assertEqual(
       "unstructured_log=abc ",
       lists:flatten(
         flatlog:format(#{level => info, msg => {string, "abc"}, meta => #{}},
                        #{template => [msg]})
       )
    ),
    ?assertEqual(
       "unstructured_log=abc ",
       lists:flatten(
         flatlog:format(#{level => info, msg => {string, [<<"abc">>]}, meta => #{}},
                        #{template => [msg]})
       )
    ),
    ?assertEqual(
       "unstructured_log=\"hello world\" ",
       lists:flatten(
         flatlog:format(#{level => info, msg => {"hello ~s", ["world"]}, meta => #{}},
                        #{template => [msg]})
       )
    ),
    ok.

colored() ->
    [{docs, "colored output logs"}].
colored(_) ->
    ?assertEqual(
       "\e[1;37mwhen= level=info at=:\e[0m hi=there \n",
        lists:flatten(
          flatlog:format(#{level => info, msg => {report, #{hi => there}}, meta => #{}},
                         #{colored => true})
        )
    ),
    ?assertEqual(
       "\e[1;44mwhen= level=alert at=:\e[0m unstructured_log=abc \n",
       lists:flatten(
         flatlog:format(#{level => alert, msg => {string, "abc"}, meta => #{}},
                        #{colored => true})
       )
    ),
    ok.
