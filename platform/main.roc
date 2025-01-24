platform "roc-ssg"
    requires {} { main! : Types.Args => Result {} [Exit I32 Str]_ }
    exposes [
        SSG,
        Types,
        Cmd,
        Stdout,
        Stderr,
        Env,
        Locale,
        Utc,
    ]
    packages {}
    imports []
    provides [main_for_host!]

import Types
import Stderr

main_for_host! : Types.Args => I32
main_for_host! = \args ->
    when main!(args) is
        Ok({}) -> 0
        Err(Exit(code, msg)) ->
            if Str.is_empty(msg) then
                code
            else
                _ = Stderr.line!(msg)
                code

        Err(msg) ->
            help_msg =
                """
                Program exited with error:
                    $(Inspect.to_str(msg))

                Tip: If you do not want to exit on this error, use `Result.map_err` to handle the error. Docs for `Result.map_err`: <https://www.roc-lang.org/builtins/Result#map_err>
                """

            _ = Stderr.line!(help_msg)
            1
