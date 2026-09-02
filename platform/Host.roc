import IOErr exposing [IOErr]
import AsciiDoc

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

	Raw : [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]

	Page : {
		url : Str,
		source_path : Raw,
		output_path : Raw,
	}

	cmd_status! : Command => Try(I32, [CmdError(IOErr)])
	cmd_output! : Command => Output

	env_var! : Str => Try(Str, [VarNotFound(Str)])
	env_dict! : () => List((Str, Str))
	env_arch_os! : () => { arch : Str, os : Str }

	locale_get! : () => Try(Str, [NotAvailable])
	locale_all! : () => List(Str)

	ssg_find_pages! : Raw, Str => Try(List(Page), [PagesError(Str)])
	ssg_read_source! : Raw => Try(Str, [ReadError(Str)])
	ssg_parse_markdown! : Raw => Try(Str, [ParseError(Str)])
	ssg_render_markdown! : Raw, Str => Try(Str, [ParseError(Str)])
	ssg_parse_asciidoc! : Raw => Try(AsciiDoc.Document, [ParseError(Str)])
	ssg_parse_asciidoc_source! : Raw, Str => Try(AsciiDoc.Document, [ParseError(Str)])
	ssg_write_file! : Raw, Raw, Str => Try({}, [WriteError(Str)])

	stdout_line! : Str => Try({}, [StdoutErr(IOErr)])
	stdout_write! : Str => Try({}, [StdoutErr(IOErr)])

	stderr_line! : Str => Try({}, [StderrErr(IOErr)])
	stderr_write! : Str => Try({}, [StderrErr(IOErr)])

	utc_now! : () => Try(U128, [ClockBeforeEpoch])
}
