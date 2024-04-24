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
    imports [InternalTypes]
    generates Effect with [after, map, always, forever, loop]

applicationError : Str -> Effect {}
findFiles : Str -> Effect (Result (List InternalTypes.UrlPath) Str)
parseMarkdown : Str -> Effect (Result Str Str)
writeFile : Str, Str, Str -> Effect (Result {} Str)