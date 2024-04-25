platform "roc-ssg"
    requires {} { main : _ }
    exposes [
        SSG,
        Types,
        Task,
    ]
    packages {}
    imports [Effect.{Effect}, Task.{Task}, Types]
    provides [mainForHost]

mainForHost : Types.Args -> Task {} I32
mainForHost = \args ->
    Task.attempt (main args) \res ->
        when res is
            Ok {} -> Task.ok {}
            Err (Exit code) -> Task.err code
            Err err -> 
                Effect.applicationError (Inspect.toStr err)
                |> Effect.map Ok
                |> Task.fromEffect
    