platform "roc-ssg"
    requires {} { main : _ }
    exposes [
        SSG,
        Task,
    ]
    packages {}
    imports [Effect.{Effect}, Task.{Task}, InternalTypes]
    provides [mainForHost]

mainForHost : InternalTypes.Args -> Task {} I32
mainForHost = \args ->
    Task.attempt (main args) \res ->
        when res is
            Ok {} -> Task.ok {}
            Err (Exit code) -> Task.err code
            Err err -> 
                Effect.applicationError (Inspect.toStr err)
                |> Effect.map Ok
                |> Task.fromEffect
    