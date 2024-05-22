interface SSG
    exposes [
        files,
        parseMarkdown,
        writeFile,
    ]
    imports [Effect, Task.{Task}, Types.{Path, RelPath, Files}]

files : Path -> Task (List Files) [FilesError Str]_
files = \path ->
    Effect.findFiles (Types.pathToStr path)
    |> Effect.map \res -> Result.mapErr res FilesError
    |> Task.fromEffect

parseMarkdown : Path -> Task Str [ParseError Str]_
parseMarkdown = \path ->
    Effect.parseMarkdown (Types.pathToStr path)
    |> Effect.map \res -> Result.mapErr res ParseError
    |> Task.fromEffect

writeFile : {outputDir : Path, relpath : RelPath, content : Str} -> Task {} [WriteError Str]_
writeFile = \{outputDir, relpath, content} ->
    Effect.writeFile (Types.pathToStr outputDir) (Types.relPathToStr relpath) content
    |> Effect.map \res -> Result.mapErr res WriteError
    |> Task.fromEffect
