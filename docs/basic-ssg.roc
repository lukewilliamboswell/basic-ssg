app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout

## Documentation entrypoint for the `basic-ssg` platform.
main! : List(Str) => Try({}, [Exit(I32), ..])
main! = |_args| {
	Stdout.line!("basic-ssg documentation entrypoint") ? |_| Exit(1)
	Ok({})
}
