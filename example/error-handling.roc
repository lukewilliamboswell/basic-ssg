app [main!] { pf: platform "../platform/main.roc" }

import pf.IOErr exposing [IOErr]
import pf.OsStr exposing [OsStr]
import pf.Path
import pf.SSG
import pf.Stdout

main! : List(OsStr) => Try({}, [Exit(I32), ExampleErr(Str), StdoutErr(IOErr), ..])
main! = |args|
	match args.drop_first(1) {
		[source_path_arg] => print_title!(Path.from_os_str(source_path_arg))

		_ => Err(Exit(1))
	}

print_title! : Path.Path => Try({}, [ExampleErr(Str), StdoutErr(IOErr), ..])
print_title! = |source_path| {
	html = SSG.parse_markdown!(source_path) ? |ParseError(msg)| ExampleErr("markdown parse failed: ${msg}")
	title = first_h1(html) ?? "Untitled"

	Stdout.line!("title: ${title}")?
	Ok({})
}

first_h1 : Str -> Try(Str, [MissingHeading])
first_h1 = |html| {
	after_open = html.split_on("<h1>").get(1) ? |_| MissingHeading
	heading = after_open.split_on("</h1>").get(0) ? |_| MissingHeading
	Ok(heading)
}

## first_h1 returns the text inside the first h1 element.
expect first_h1("<h1>Fruit</h1><p>Body</p>")? == "Fruit"

## first_h1 reports MissingHeading when there is no h1 element.
expect first_h1("<p>Body</p>") == Err(MissingHeading)
