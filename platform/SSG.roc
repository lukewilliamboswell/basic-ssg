module [
    files,
    parseMarkdown,
    writeFile,
]

import PlatformTask
import Types exposing [Path, RelPath, Files]

files : Path -> Task (List Files) [FilesError Str]_
files = \path ->
    PlatformTask.findFiles (Types.pathToStr path)
    |> Task.mapErr FilesError

parseMarkdown : Path -> Task Str [ParseError Str]_
parseMarkdown = \path ->
    PlatformTask.parseMarkdown (Types.pathToStr path)
    |> Task.mapErr ParseError

writeFile : { outputDir : Path, relpath : RelPath, content : Str } -> Task {} [WriteError Str]_
writeFile = \{ outputDir, relpath, content } ->
    PlatformTask.writeFile (Types.pathToStr outputDir) (Types.relPathToStr relpath) content
    |> Task.mapErr WriteError
