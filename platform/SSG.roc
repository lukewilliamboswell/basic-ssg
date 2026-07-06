import Path
import Host

## Static site generation effects: discover markdown pages, render markdown to
## HTML, and write generated files to disk.
SSG := [].{

	## A markdown page discovered under the input directory.
	##
	## - `source_path` is the markdown source file.
	## - `output_path` is relative to the output directory, with extension rewritten to `.html`.
	## - `url` is the site-absolute URL of the output file.
	Page : {
		url : Str,
		source_path : Path.Path,
		output_path : Path.Path,
	}

	## Find the markdown pages in the given directory, searched recursively.
	pages! : Path.Path => Try(List(Page), [PagesError(Str), ..])
	pages! = |input_dir|
		match Host.ssg_find_pages!(Path.to_raw(input_dir)) {
			Ok(host_pages) => Ok(host_pages.map(from_host_page))
			Err(PagesError(msg)) => Err(PagesError(msg))
		}

	## Render a markdown file to an HTML string.
	parse_markdown! : Path.Path => Try(Str, [ParseError(Str), ..])
	parse_markdown! = |source_path|
		match Host.ssg_parse_markdown!(Path.to_raw(source_path)) {
			Ok(html) => Ok(html)
			Err(ParseError(msg)) => Err(ParseError(msg))
		}

	## Write `content` to `output_path` underneath `output_dir`, creating parent directories as needed.
	write_file! : { output_dir : Path.Path, output_path : Path.Path, content : Str } => Try({}, [WriteError(Str), ..])
	write_file! = |{ output_dir, output_path, content }|
		match Host.ssg_write_file!(Path.to_raw(output_dir), Path.to_raw(output_path), content) {
			Ok({}) => Ok({})
			Err(WriteError(msg)) => Err(WriteError(msg))
		}
}

from_host_page : Host.Page -> SSG.Page
from_host_page = |page| {
	url: page.url,
	source_path: Path.from_raw(page.source_path),
	output_path: Path.from_raw(page.output_path),
}
