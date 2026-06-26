## Static site generation effects: discover markdown files, render markdown to
## HTML, and write generated files to disk.
SSG := [].{
    ## A markdown source file discovered under the input directory.
    ##
    ## - `path` is the path to the markdown source file.
    ## - `relpath` is the path of the output file relative to the output directory (extension rewritten to `.html`).
    ## - `url` is the site-absolute URL of the output file (a leading `/` plus `relpath`).
    Files : {
        url : Str,
        path : Str,
        relpath : Str,
    }

    # ---- Host functions (the FFI boundary) -------------------------------------

    host_find_files! : Str => Try(List(Files), Str)
    host_parse_markdown! : Str => Try(Str, Str)
    host_write_file! : Str, Str, Str => Try({}, Str)

    # ---- Ergonomic wrappers ----------------------------------------------------

    ## Find the markdown (`.md`) files in the given directory (searched recursively).
    files! : Str => Try(List(Files), [FilesError(Str), ..])
    files! = |input_dir|
        match SSG.host_find_files!(input_dir) {
            Ok(found) => Ok(found)
            Err(msg) => Err(FilesError(msg))
        }

    ## Render a markdown file to an HTML string.
    parse_markdown! : Str => Try(Str, [ParseError(Str), ..])
    parse_markdown! = |path|
        match SSG.host_parse_markdown!(path) {
            Ok(html) => Ok(html)
            Err(msg) => Err(ParseError(msg))
        }

    ## Write `content` to `relpath` underneath `output_dir`, creating parent directories as needed.
    write_file! : { output_dir : Str, relpath : Str, content : Str } => Try({}, [WriteError(Str), ..])
    write_file! = |{ output_dir, relpath, content }|
        match SSG.host_write_file!(output_dir, relpath, content) {
            Ok({}) => Ok({})
            Err(msg) => Err(WriteError(msg))
        }
}
