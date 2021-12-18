flatlog
=====

A custom formatter for the logger application that turns maps into single line text logs

Why?
----

Structured logging is a better approach to logging in general. Fields are more clearly defined, tool-assisted parsing and consuming of logs is simpler, and the structure is amenable to good filtering in global or handler filters for the Erlang `logger` library.

You could, for example, emit all your logs as structured logs (just maps), and set up multiple handlers for them:

- an audit handler, for all critical issues and configuration changes, which get stored on disk and remotely for long periods of time
- an info log for users, which gets a shorter term durability
- an error log for support tickets, which may instead have a targeted retention for a few weeks
- a special handler that parses the structured logs and forwards them to a distributed tracing
  framework such as opencensus
- extract or hide metrics from logs if you integrate with such a system, and do it cheaply by
  just nesting (or removing) a metrics map in the overall report.

This can be done transparently and after the fact, without major structural impact to the call site. It lets you far more easily decouple log generation from its consumption at no heavy cost.

This formatter focuses on providing a text-based single-line format for structured logs, which can be human-readable, while being useful to people who use grep or awk to process logs, or want to forward them to a consumer like syslogd.

Usage
-----

It is recommended that if you are providing a library, you do not add this
project as a dependency. A code formatter of this kind should be added to a
project in its release repository as a top-level final presentational concern.

Once the project is added, replace the formatter of the default handler (or add a custom handler) for structured logging to your `sys.config` file:

```erlang
[
 {kernel, [
    {logger, [
        {handler, default, logger_std_h,
         #{formatter => {flatlog, #{
            map_depth => 3,
            term_depth => 50
          }}}
        }
    ]},
    {logger_level, info}
 ]}
].
```

The logging output will then be supported. Calling the logger like:

```erlang
?LOG_ERROR(
    #{type => event, in => config, user => #{name => <<"bobby">>, id => 12345},
      action => change_password, result => error, details => {entropy, too_low},
      txt => <<"user password not strong enough">>}
)
```

Will produce a single log line like:
```
when=2018-11-15T18:16:03.411822+00:00 level=error pid=<0.134.0>
at=config:update/3:450 user_name=bobby user_id=12345 type=event
txt="user password not strong enough" result=error in=config
details={entropy,too_low} action=change_password
```

Do note that the `user` map gets flattened such that `#{user => #{name => bobby}}` gets
turned into `user_name=bobby`, ensuring that various subfields in distinct maps
will not clash.

The default template supplied with the library also includes optional fields for
identifiers as used in distributed tracing framework which can be set in the metadata
for the logger framework, either explicitly or as a process state. The fields are:

- `id` for individual request identifiers
- `parent_id` for the event or command that initially caused the current logging event to happen
- `correlation_id` for groupings of related events


Logs that are not reports (maps) are going to be formatted and handled such that they can be
put inside a structured log. For example:

```erlang
?LOG_INFO("hello ~s", ["world"])
```

Will result in:

```
when=2018-11-15T18:16:03.411822+00:00 level=info pid=<0.134.0>
at=some:code/0:15 unstructured_log="hello world"
```

Do note that if you are building a release, you will need to manually add
the `flatlog` dependency to your `relx` configuration, since it is
technically not a direct dependency of any application in your system.

Test
----

    $ rebar3 check

Features
--------

- Printing rules similar to the default Erlang logger formatter, but extended for
  binary values that can be represented as text. I.e. rather than `<<"hello">>`, the
  value `hello` will be output. A non-representable value will revert to `<<...>>`
- Linebreaks are escaped to ensure all logs are always on one line, and strings that
  contain spaces or equal signs (` ` and `=`) are quoted such that
  `"key=name"="hello world"` to be clear.
- Term depth applies on a per-term basis before a data structure is elided with `...`
- Map depth is controllable independently to deal with recursion vs. complexity of terms
- Colored output can be enabled with `colored => true`. One can color certain parts of
  the output using `colored_start` and `colored_end` in `template`. Per-level colors
  can be configured with `colored_{log level}`.

Caveats
-------

- No max line length is enforced at the formatter level, since the ordering of terms
  in maps is not defined and it could be risky to cut logs early. If a max line length
  is to be enforced, you should wrap this formatter into your own.
- Escaping of keys does not carry well to nested maps. I.e. the map
  `#{a_b => #{"c d" => x}}` is not well supported: `a_b_"c d"=x` will be returned, which
  is nonsensical. For nested maps, you have the responsibility of ensuring composability.
- The transformations to the log line format is not lossless; it is not serialization.
  Information is lost regarding whether the initial term was a binary, a string, or an
  atom. Similarly, naming a key `user_password` may make it seem like the `user` map
  leaks a `password` field, but it is an unrelated field that looks similar due to flattening.
  If this is unacceptable, you might want to choose another structured log format such
  as JSON.

Roadmap
-------

- integration tests
- add example basic usage
- add example usage with optional tracing for IDs
- clean up test suites
- incorporating lager's safer truncating logic (might be a breaking change prior to 1.0.0)

Changelog
---------

- 0.1.2: added a check for old `error_logger` calls (thanks @hommeabeil)
- 0.1.1: added optionally colored logs (thanks @pfenoll)
