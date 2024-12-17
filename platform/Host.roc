hosted Host
    exposes [
        application_error!,
        find_files!,
        parse_markdown!,
        write_file!,
        command_status!,
        command_output!,
        stdout_line!,
        stdout_write!,
        stderr_line!,
        stderr_write!,
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

# STDIO
stdout_line! : Str => Result {} InternalIOErr.IOErrFromHost
stdout_write! : Str => Result {} InternalIOErr.IOErrFromHost
stderr_line! : Str => Result {} InternalIOErr.IOErrFromHost
stderr_write! : Str => Result {} InternalIOErr.IOErrFromHost
