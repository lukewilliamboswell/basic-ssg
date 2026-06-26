import IOErr exposing [IOErr]

## Execute programs in child processes.
Cmd := [].{
    ## Represents a command to be executed in a child process.
    ##
    ## - `envs` is a flat list `[key0, value0, key1, value1, ...]`.
    Command : {
        program : Str,
        args : List(Str),
        envs : List(Str),
        clear_envs : Bool,
    }

    ## Captured output of a command.
    Output : {
        exit_code : I32,
        stdout : List(U8),
        stderr : List(U8),
    }

    # Host function: run the command inheriting stdin/stdout/stderr, return the
    # exit code. Uses a `Str` error at the boundary (see Stdout.roc).
    host_status! : Command => Try(I32, Str)

    # Host function: run the command capturing stdout/stderr.
    host_output! : Command => Output

    ## Create a new command to execute the given program in a child process.
    new : Str -> Command
    new = |program| {
        program,
        args: [],
        envs: [],
        clear_envs: Bool.False,
    }

    ## Add a single argument to the command.
    arg : Command, Str -> Command
    arg = |cmd, value| { ..cmd, args: List.append(cmd.args, value) }

    ## Add multiple arguments to the command.
    args : Command, List(Str) -> Command
    args = |cmd, values| { ..cmd, args: List.concat(cmd.args, values) }

    ## Add a single environment variable to the command.
    env : Command, Str, Str -> Command
    env = |cmd, key, value| { ..cmd, envs: List.append(List.append(cmd.envs, key), value) }

    ## Clear all environment variables, and prevent inheriting from the parent.
    clear_envs : Command -> Command
    clear_envs = |cmd| { ..cmd, clear_envs: Bool.True }

    ## Execute the command, inheriting stdin/stdout/stderr from the parent, and
    ## return its exit code.
    status! : Command => Try(I32, [CmdError(IOErr), ..])
    status! = |cmd|
        match Cmd.host_status!(cmd) {
            Ok(code) => Ok(code)
            Err(msg) => Err(CmdError(Other(msg)))
        }

    ## Execute the command and capture its stdout and stderr.
    output! : Command => Output
    output! = |cmd| Cmd.host_output!(cmd)

    ## Execute a program with arguments, inheriting stdin/stdout/stderr.
    ## Returns `Err(CmdError(...))` on failure, or `Err(NonZeroExit(code))` if the
    ## program exits non-zero.
    exec! : Str, List(Str) => Try({}, [CmdError(IOErr), NonZeroExit(I32), ..])
    exec! = |program, arguments| {
        code = Cmd.status!(Cmd.args(Cmd.new(program), arguments))?
        if code == 0 {
            Ok({})
        } else {
            Err(NonZeroExit(code))
        }
    }
}
