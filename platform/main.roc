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
        Tcp,
        Http,
    ]
    packages {}
    imports []
    provides [main_for_host!]

import Types
import Stderr

main_for_host! : Types.Args => I32
main_for_host! = \args ->
    when main! args is
        Ok {} -> 0
        Err (Exit code msg) ->
            if Str.isEmpty msg then
                code
            else
                _ = Stderr.line! msg
                code

        Err msg ->
            helpMsg =
                """
                Program exited with error:
                    $(Inspect.toStr msg)

                Tip: If you do not want to exit on this error, use `Result.mapErr` to handle the error. Docs for `Result.mapErr`: <https://www.roc-lang.org/builtins/Result#mapErr>
                """

            _ = Stderr.line! helpMsg
            1
