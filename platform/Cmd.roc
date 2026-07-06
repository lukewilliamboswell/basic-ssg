import IOErr exposing [IOErr]
import Host

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
		match Host.cmd_status!(cmd) {
			Ok(code) => Ok(code)
			Err(CmdError(err)) => Err(CmdError(err))
		}

	## Execute the command and capture its stdout and stderr.
	output! : Command => Output
	output! = |cmd| Host.cmd_output!(cmd)

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
