platform "roc-ssg"
    requires {} { main! : _ }
    exposes [
        SSG,
        Types,
        Cmd,
    ]
    packages {}
    imports []
    provides [main_for_host!]

import Types
import Host

main_for_host! : Box Types.Args => Result {} I32
main_for_host! = \boxed_args ->
    result = main! (Box.unbox boxed_args)
    when result is
        Ok {} -> Ok {}
        Err (Exit code) -> Err code
        Err err ->
            Host.application_error! (Inspect.toStr err)
            Err 1
