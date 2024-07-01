platform "roc-ssg"
    requires {} { main : _ }
    exposes [
        SSG,
        Types,
        Task,
    ]
    packages {}
    imports []
    provides [mainForHost]

import Types
import PlatformTask

mainForHost : Types.Args -> Task {} I32
mainForHost = \args ->
    Task.attempt (main args) \res ->
        when res is
            Ok {} -> Task.ok {}
            Err (Exit code) -> Task.err code
            Err err ->
                PlatformTask.applicationError (Inspect.toStr err)
