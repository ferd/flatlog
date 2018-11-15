-module(silent_logger).
-compile(export_all).

adding_handler(Config = #{}) ->
    {ok, Config#{}}.

removing_handler(_Config) ->
    ok.

log(LogEvent, Config) ->
    _Bin = logger_h_common:log_to_binary(LogEvent, Config),
    ok.
