module [
    files!,
    parse_markdown!,
    write_file!,
]

import Host
import Types exposing [Path, RelPath, Files]

files! : Path => Result (List Files) [FilesError Str]_
files! = \path ->
    Host.find_files!(Types.path_to_str(path))
    |> Result.map_err(FilesError)

parse_markdown! : Path => Result Str [ParseError Str]_
parse_markdown! = \path ->
    Host.parse_markdown!(Types.path_to_str(path))
    |> Result.map_err(ParseError)

write_file! : { output_dir : Path, relpath : RelPath, content : Str } => Result {} [WriteError Str]_
write_file! = \{ output_dir, relpath, content } ->
    Host.write_file!(Types.path_to_str(output_dir), Types.rel_path_to_str(relpath), content)
    |> Result.map_err(WriteError)
