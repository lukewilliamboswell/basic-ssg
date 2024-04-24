platform "roc-ssg"
    requires {} { main : Task {} _ }
    exposes [
        SSG,
        Task,
    ]
    packages {}
    imports [Effect.{Effect}, Task.{Task}]
    provides [mainForHost]

mainForHost : Task {} I32
mainForHost =
    Task.attempt main \res ->
        when res is
            Ok {} -> Task.ok {}
            Err (Exit code) -> Task.err code
            Err err -> 
                Effect.applicationError (Inspect.toStr err)
                |> Effect.map Ok
                |> Task.fromEffect
    