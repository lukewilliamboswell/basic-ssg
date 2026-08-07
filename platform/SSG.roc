import Path
import Host

## Static site generation effects: discover page sources, run application-defined
## decoders, optionally render Markdown, and write generated files to disk.
SSG := [].{

	## A page source discovered under the input directory.
	##
	## - `source_path` is the application-defined page source file.
	## - `output_path` is relative to the output directory, with extension rewritten to `.html`.
	## - `url` is the site-absolute URL of the output file.
	Page : {
		url : Str,
		source_path : Path.Path,
		output_path : Path.Path,
	}

	## Find the markdown pages in the given directory, searched recursively.
	pages! : Path.Path => Try(List(Page), [PagesError(Str), ..])
	pages! = |input_dir| pages_with!({ input_dir, source_extension: "md" })

	## Find pages with `source_extension` in the given directory, searched recursively.
	## The extension must not include a leading dot. Output paths always use `.html`.
	pages_with! : { input_dir : Path.Path, source_extension : Str } => Try(List(Page), [PagesError(Str), ..])
	pages_with! = |{ input_dir, source_extension }|
		match Host.ssg_find_pages!(Path.to_raw(input_dir), source_extension) {
			Ok(host_pages) => Ok(host_pages.map(from_host_page))
			Err(PagesError(msg)) => Err(PagesError(msg))
		}

	## Read a page source as UTF-8 text.
	read_source! : Page => Try(Str, [ReadError(Str), ..])
	read_source! = |page|
		match Host.ssg_read_source!(Path.to_raw(page.source_path)) {
			Ok(source) => Ok(source)
			Err(ReadError(msg)) => Err(ReadError(msg))
		}

	## Read a page source and run a pure or effectful decoder against it.
	decode_page! : Page, ({ page : Page, source : Str } => Try(value, [ReadError(Str), ..err])) => Try(value, [ReadError(Str), ..err])
	decode_page! = |page, decode!| {
		source = read_source!(page)?
		decode!({ page, source })
	}

	## Render a markdown file to an HTML string.
	parse_markdown! : Path.Path => Try(Str, [ParseError(Str), ..])
	parse_markdown! = |source_path|
		match Host.ssg_parse_markdown!(Path.to_raw(source_path)) {
			Ok(html) => Ok(html)
			Err(ParseError(msg)) => Err(ParseError(msg))
		}

	## Render Markdown source to HTML. Replacement directives are resolved relative
	## to `source_path`, which normally identifies the page being decoded.
	render_markdown! : { source_path : Path.Path, markdown : Str } => Try(Str, [ParseError(Str), ..])
	render_markdown! = |{ source_path, markdown }|
		match Host.ssg_render_markdown!(Path.to_raw(source_path), markdown) {
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
from_host_page = |{ url, source_path, output_path }| {
	url,
	source_path: Path.from_raw(source_path),
	output_path: Path.from_raw(output_path),
}
