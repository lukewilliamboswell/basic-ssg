hosted Host
    exposes [
        application_error!,
        find_files!,
        parse_markdown!,
        write_file!,
    ]
    imports [Types]

application_error! : Str => {}
find_files! : Str => Result (List Types.Files) Str
parse_markdown! : Str => Result Str Str
write_file! : Str, Str, Str => Result {} Str
