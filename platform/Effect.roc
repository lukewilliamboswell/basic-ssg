hosted Effect
    exposes [
        Effect,
        after,
        map,
        always,
        forever,
        loop,

        # platform effects
        applicationError,
        findFiles,
        parseMarkdown,
        writeFile,
    ]
    imports [Types]
    generates Effect with [after, map, always, forever, loop]

applicationError : Str -> Effect {}
findFiles : Str -> Effect (Result (List Types.Files) Str)
parseMarkdown : Str -> Effect (Result Str Str)
writeFile : Str, Str, Str -> Effect (Result {} Str)