import IOErr exposing [IOErr]
import Path

Host := [].{

	Command : {
		program : Str,
		args : List(Str),
		envs : List(Str),
		clear_envs : Bool,
	}

	Output : {
		exit_code : I32,
		stdout : List(U8),
		stderr : List(U8),
	}

	Page : {
		url : Str,
		source_path : Path.Raw,
		output_path : Path.Raw,
	}

	cmd_status! : Command => Try(I32, [CmdError(IOErr)])
	cmd_output! : Command => Output

	env_var! : Str => Try(Str, [VarNotFound(Str)])
	env_dict! : () => List((Str, Str))
	env_arch_os! : () => { arch : Str, os : Str }

	locale_get! : () => Try(Str, [NotAvailable])
	locale_all! : () => List(Str)

	ssg_find_pages! : Path.Raw => Try(List(Page), [PagesError(Str)])
	ssg_parse_markdown! : Path.Raw => Try(Str, [ParseError(Str)])
	ssg_write_file! : Path.Raw, Path.Raw, Str => Try({}, [WriteError(Str)])

	stdout_line! : Str => Try({}, [StdoutErr(IOErr)])
	stdout_write! : Str => Try({}, [StdoutErr(IOErr)])

	stderr_line! : Str => Try({}, [StderrErr(IOErr)])
	stderr_write! : Str => Try({}, [StderrErr(IOErr)])

	utc_now! : () => U128
}
