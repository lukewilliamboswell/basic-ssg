platform "roc-ssg"
    requires {} { main : _ }
    exposes [
        SSG,
        Types,
    ]
    packages {}
    imports []
    provides [mainForHost]

import Types
import PlatformTasks

mainForHost : Types.Args -> Task {} I32
mainForHost = \args ->
    Task.attempt (main args) \res ->
        when res is
            Ok {} -> Task.ok {}
            Err (Exit code) -> Task.err code
            Err err ->
                PlatformTasks.applicationError (Inspect.toStr err)
                |> Task.mapErr \_ -> crash "unreachable : mainForHost"
