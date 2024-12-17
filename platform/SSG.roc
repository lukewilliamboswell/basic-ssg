module [
    files!,
    parse_markdown!,
    write_file!,
]

import Host
import Types exposing [Path, RelPath, Files]

files! : Path => Result (List Files) [FilesError Str]_
files! = \path ->
    Host.find_files! (Types.path_to_str path)
    |> Result.mapErr FilesError

parse_markdown! : Path => Result Str [ParseError Str]_
parse_markdown! = \path ->
    Host.parse_markdown! (Types.path_to_str path)
    |> Result.mapErr ParseError

write_file! : { outputDir : Path, relpath : RelPath, content : Str } => Result {} [WriteError Str]_
write_file! = \{ outputDir, relpath, content } ->
    Host.write_file! (Types.path_to_str outputDir) (Types.rel_path_to_str relpath) content
    |> Result.mapErr WriteError
