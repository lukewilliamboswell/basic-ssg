platform "roc-ssg"
    requires {} { main! : _ }
    exposes [
        SSG,
        Types,
    ]
    packages {}
    imports []
    provides [main_for_host!]

import Types
import Host

main_for_host! : Types.Args => Result {} I32
main_for_host! = \args ->
    when main! args is
        Ok {} -> Ok {}
        Err (Exit code) -> Err code
        Err err ->
            Host.application_error! (Inspect.toStr err)
            Err 1
