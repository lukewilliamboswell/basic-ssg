platform ""
	requires {
		main! : List([Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]) => Try({}, [Exit(I32), ..])
	}
	exposes [SSG, AsciiDoc, PageDecoder, Path, OsStr, Html, HtmlAttributes, IOErr, Stdout, Stderr, Cmd, Env, Locale, Utc]
	packages {
		# Pure filesystem path operations come from roc-lang/path. The SSG
		# module uses this shared type at the platform boundary.
		path: "https://github.com/roc-lang/path/releases/download/4.0.0/7YfABZPwJAXtLBY2vm8FqMyGAtNxncCJ65HdNKHFGNnE.tar.zst",
	}
	provides { "roc_main": main_for_host! }
	hosted {
		"hosted_stdout_line": Host.stdout_line!,
		"hosted_stdout_write": Host.stdout_write!,
		"hosted_stderr_line": Host.stderr_line!,
		"hosted_stderr_write": Host.stderr_write!,
		"hosted_cmd_status": Host.cmd_status!,
		"hosted_cmd_output": Host.cmd_output!,
		"hosted_env_var": Host.env_var!,
		"hosted_env_dict": Host.env_dict!,
		"hosted_env_arch_os": Host.env_arch_os!,
		"hosted_locale_get": Host.locale_get!,
		"hosted_locale_all": Host.locale_all!,
		"hosted_utc_now": Host.utc_now!,
		"hosted_ssg_find_pages": Host.ssg_find_pages!,
		"hosted_ssg_read_source": Host.ssg_read_source!,
		"hosted_ssg_parse_markdown": Host.ssg_parse_markdown!,
		"hosted_ssg_render_markdown": Host.ssg_render_markdown!,
		"hosted_ssg_parse_asciidoc": Host.ssg_parse_asciidoc!,
		"hosted_ssg_parse_asciidoc_source": Host.ssg_parse_asciidoc_source!,
		"hosted_ssg_write_file": Host.ssg_write_file!,
	}
	targets: {
		inputs_dir: "targets/",
		x64mac: { inputs: ["libhost.a", app] },
		arm64mac: { inputs: ["libhost.a", app] },
		x64win: { inputs: ["host.lib", "advapi32.lib", "bcrypt.lib", "crypt32.lib", "dbghelp.lib", "iphlpapi.lib", "kernel32.lib", "ncrypt.lib", "ntdll.lib", "ole32.lib", "secur32.lib", "shell32.lib", "user32.lib", "userenv.lib", "ws2_32.lib", app] },
		x64musl: { inputs: ["crt1.o", "libhost.a", "libunwind.a", app, "libc.a"] },
		arm64musl: { inputs: ["crt1.o", "libhost.a", "libunwind.a", app, "libc.a"] },
	}

import SSG
import AsciiDoc
import PageDecoder
import Path
import OsStr
import Host
import Html
import HtmlAttributes
import IOErr
import Stdout
import Stderr
import Cmd
import Env
import Locale
import Utc

main_for_host! : List(OsStr.OsStr) => I32
main_for_host! = |args|
	match main!(args) {
		Ok({}) => 0
		Err(Exit(code)) => code
		Err(other) => {
			Stderr.line!("Program exited with error: ${Str.inspect(other)}") ?? {}
			1
		}
	}
