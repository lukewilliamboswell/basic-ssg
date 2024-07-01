hosted PlatformTask
    exposes [
        applicationError,
        findFiles,
        parseMarkdown,
        writeFile,
    ]
    imports [Types]

applicationError : Str -> Task {} *
findFiles : Str -> Task (List Types.Files) Str
parseMarkdown : Str -> Task Str Str
writeFile : Str, Str, Str -> Task {} Str
