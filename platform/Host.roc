hosted Host
    exposes [
        TcpStream,
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
        env_dict!,
        env_var!,
        current_arch_os!,
        get_locale!,
        get_locales!,
        posix_time!,
        send_request!,
        tcp_connect!,
        tcp_read_up_to!,
        tcp_read_exactly!,
        tcp_read_until!,
        tcp_write!,
    ]
    imports [Types]

import InternalIOErr
import InternalCmd
import InternalHttp

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

# ENV
env_dict! : {} => List (Str, Str)
env_var! : Str => Result Str {}
current_arch_os! : {} => { arch : Str, os : Str }

# LOCALE
get_locale! : {} => Result Str {}
get_locales! : {} => List Str

# UTC
posix_time! : {} => U128 # TODO why is this a U128 but then getting converted to a I128 in Utc.roc?

# TCP
send_request! : InternalHttp.RequestToAndFromHost => InternalHttp.ResponseToAndFromHost

TcpStream := Box {}
tcp_connect! : Str, U16 => Result TcpStream Str
tcp_read_up_to! : TcpStream, U64 => Result (List U8) Str
tcp_read_exactly! : TcpStream, U64 => Result (List U8) Str
tcp_read_until! : TcpStream, U8 => Result (List U8) Str
tcp_write! : TcpStream, List U8 => Result {} Str
