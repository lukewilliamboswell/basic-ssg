platform ""
	requires {
		main! : List(Str) => Try({}, [Exit(I32), ..])
	}
	exposes [SSG, Path, Html, HtmlAttributes, IOErr, Stdout, Stderr, Cmd, Env, Locale, Utc]
	packages {
		# Pure filesystem path operations come from roc-lang/path. The SSG
		# module uses this shared type at the platform boundary.
		path: "https://github.com/roc-lang/path/releases/download/1.0.0/8p8iryUUorAFTUDeqYcwc9bFYSwpbVqhYpuHvRAS5Cq4.tar.zst",
	}
	provides { "roc_main": main_for_host! }
	hosted {
		"hosted_stdout_line": Stdout.host_line!,
		"hosted_stdout_write": Stdout.host_write!,
		"hosted_stderr_line": Stderr.host_line!,
		"hosted_stderr_write": Stderr.host_write!,
		"hosted_cmd_status": Cmd.host_status!,
		"hosted_cmd_output": Cmd.host_output!,
		"hosted_env_var": Env.var!,
		"hosted_env_dict": Env.host_dict!,
		"hosted_env_arch_os": Env.host_arch_os!,
		"hosted_locale_get": Locale.get!,
		"hosted_locale_all": Locale.all!,
		"hosted_utc_now": Utc.now!,
		"hosted_ssg_find_pages": SSG.host_find_pages!,
		"hosted_ssg_parse_markdown": SSG.host_parse_markdown!,
		"hosted_ssg_write_file": SSG.host_write_file!,
	}
	targets: {
		inputs_dir: "targets/",
		x64mac: { inputs: ["libhost.a", app] },
		arm64mac: { inputs: ["libhost.a", app] },
		x64musl: { inputs: ["crt1.o", "libhost.a", "libunwind.a", app, "libc.a"] },
		arm64musl: { inputs: ["crt1.o", "libhost.a", "libunwind.a", app, "libc.a"] },
	}

import SSG
import Path
import Html
import HtmlAttributes
import IOErr
import Stdout
import Stderr
import Cmd
import Env
import Locale
import Utc

main_for_host! : List(Str) => I32
main_for_host! = |args|
	match main!(args) {
		Ok({}) => 0
		Err(Exit(code)) => code
		Err(other) =>
			match Stderr.line!("Program exited with error: ${Str.inspect(other)}") {
				_ => 1
			}
		}
