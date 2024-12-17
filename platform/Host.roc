hosted Host
    exposes [
        application_error!,
        find_files!,
        parse_markdown!,
        write_file!,
        command_status!,
        command_output!,
    ]
    imports [Types]

import InternalIOErr
import InternalCmd

application_error! : Str => {}
find_files! : Str => Result (List Types.Files) Str
parse_markdown! : Str => Result Str Str
write_file! : Str, Str, Str => Result {} Str

# COMMAND
command_status! : InternalCmd.Command => Result I32 InternalIOErr.IOErrFromHost
command_output! : InternalCmd.Command => InternalCmd.OutputFromHost
