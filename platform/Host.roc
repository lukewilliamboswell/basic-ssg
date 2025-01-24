hosted Host
    exposes [
        find_files!,
        parse_markdown!,
        write_file!,
        command_status!,
        command_output!,
        stdout_line!,
        stdout_write!,
        stderr_line!,
        stderr_write!,
        env_dict!,
        env_var!,
        current_arch_os!,
        get_locale!,
        get_locales!,
        posix_time!,
    ]
    imports [Types]

import InternalIOErr
import InternalCmd

# Static Site Generation
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

# ENV
env_dict! : {} => List (Str, Str)
env_var! : Str => Result Str {}
current_arch_os! : {} => { arch : Str, os : Str }

# LOCALE
get_locale! : {} => Result Str {}
get_locales! : {} => List Str

# UTC
posix_time! : {} => U128 # TODO why is this a U128 but then getting converted to a I128 in Utc.roc?
