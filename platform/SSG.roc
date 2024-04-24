interface SSG
    exposes [
        UrlPath,
        Args,
        files,
        parseMarkdown,
        writeFile,
    ]
    imports [Effect, Task.{Task}, InternalTypes]

UrlPath : InternalTypes.UrlPath
Args : InternalTypes.Args

files : Str -> Task (List UrlPath) [FilesError Str]_
files = \path ->
    Effect.findFiles path
    |> Effect.map \res -> Result.mapErr res FilesError
    |> Task.fromEffect

parseMarkdown : Str -> Task Str [ParseError Str]_
parseMarkdown = \path ->
    Effect.parseMarkdown path
    |> Effect.map \res -> Result.mapErr res ParseError
    |> Task.fromEffect

writeFile : {outputDir : Str, relPath : Str, content : Str} -> Task {} [WriteError Str]_
writeFile = \{outputDir, relPath, content} ->
    Effect.writeFile outputDir relPath content
    |> Effect.map \res -> Result.mapErr res WriteError
    |> Task.fromEffect