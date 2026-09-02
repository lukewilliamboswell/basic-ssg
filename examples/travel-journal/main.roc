app [main!] { pf: platform "../../platform/main.roc" }

import pf.Html
import pf.HtmlAttributes exposing [lang]
import pf.OsStr exposing [OsStr]
import pf.PageDecoder
import pf.Path
import pf.SSG
import pf.Utc

JsonPage : {
	title : Str,
	body : Str,
}

JsonDecodedPage : {
	page : SSG.Page,
	content : JsonPage,
	generated_at : U128,
}

Frontmatter : {
	title : Str,
	author : Str,
}

FrontmatterContent : {
	metadata : Frontmatter,
	body_html : Str,
}

FrontmatterDecodedPage : {
	page : SSG.Page,
	content : FrontmatterContent,
	generated_at : U128,
}

main! : List(OsStr) => Try({}, [Exit(I32), InvalidFrontmatter(Str), InvalidJson(Str), MissingRequiredField(Str), PagesError(Str), ParseError(Str), ReadError(Str), WriteError(Str), ..])
main! = |args|
	match args.drop_first(1) {
		[input_dir_arg, output_dir_arg] => {
			input_dir = Path.from_os_str(input_dir_arg)
			output_dir = Path.from_os_str(output_dir_arg)

			# One site can contain whole-file data pages and Markdown pages with frontmatter.
			json_pages = SSG.pages_with!({ input_dir, source_extension: "json" })?
			frontmatter_pages = SSG.markdown_pages!(input_dir)?

			process_json_pages!(json_pages, output_dir)?
			process_frontmatter_pages!(frontmatter_pages, output_dir)
		}

		_ => Err(Exit(1))
	}

## Decode a whole-file JSON object together with page data and an effectful field.
json_page_decoder! : PageDecoder.Decoder(SSG.Page, JsonDecodedPage, [InvalidJson(Str), MissingRequiredField(Str), ReadError(Str), ..])
json_page_decoder! = {
	content: PageDecoder.from_source(Json.parse),
	generated_at: PageDecoder.from_effect(decode_timestamp!),
	page: PageDecoder.page!,
}.PageDecoder

## Decode JSON frontmatter, then effectfully render the remaining source as Markdown.
frontmatter_page_decoder! : PageDecoder.Decoder(SSG.Page, FrontmatterDecodedPage, [InvalidFrontmatter(Str), InvalidJson(Str), MissingRequiredField(Str), ParseError(Str), ReadError(Str), ..])
frontmatter_page_decoder! = {
	content: frontmatter(Json.parse),
	generated_at: PageDecoder.from_effect(decode_timestamp!),
	page: PageDecoder.page!,
}.PageDecoder

decode_timestamp! : PageDecoder.Input(page) => Try(U128, err)
decode_timestamp! = |_| Ok(Utc.now!())

## Build a frontmatter decoder from any pure metadata parser. `Json.parse` above
## can be replaced by a YAML parser with the same `Str -> Try(value, errors)` shape.
frontmatter : (Str -> Try(metadata, [InvalidFrontmatter(Str), ParseError(Str), ReadError(Str), ..err])) -> PageDecoder.Decoder(SSG.Page, { metadata : metadata, body_html : Str }, [InvalidFrontmatter(Str), ParseError(Str), ReadError(Str), ..err])
frontmatter = |parse_metadata|
	PageDecoder.from_effect(
		|{ page, source }| {
			parts = split_frontmatter(source)?
			metadata = parse_metadata(parts.metadata)?
			body_html = SSG.render_markdown!({ source_path: page.source_path, markdown: parts.body })?
			Ok({ metadata, body_html })
		},
	)

split_frontmatter : Str -> Try({ metadata : Str, body : Str }, [InvalidFrontmatter(Str), ..])
split_frontmatter = |source| {
	normalized = Str.join_with(source.split_on("\r\n"), "\n")

	if !normalized.starts_with("---\n") {
		Err(InvalidFrontmatter("expected an opening --- delimiter"))
	} else {
		after_open = normalized.drop_prefix("---\n")
		match after_open.split_on("\n---\n") {
			[metadata, .. as body_parts] if !body_parts.is_empty() =>
				Ok({ metadata, body: Str.join_with(body_parts, "\n---\n") })

			_ => Err(InvalidFrontmatter("expected a closing --- delimiter"))
		}
	}
}

process_json_pages! : List(SSG.Page), Path.Path => Try({}, [InvalidJson(Str), MissingRequiredField(Str), ReadError(Str), WriteError(Str), ..])
process_json_pages! = |pages, output_dir|
	match pages {
		[] => Ok({})
		[page, .. as rest] => {
			decoded = SSG.decode_page!(page, json_page_decoder!)?
			content = render_json_page(decoded)
			SSG.write_file!({ output_dir, output_path: decoded.page.output_path, content })?
			process_json_pages!(rest, output_dir)
		}
	}

process_frontmatter_pages! : List(SSG.Page), Path.Path => Try({}, [InvalidFrontmatter(Str), InvalidJson(Str), MissingRequiredField(Str), ParseError(Str), ReadError(Str), WriteError(Str), ..])
process_frontmatter_pages! = |pages, output_dir|
	match pages {
		[] => Ok({})
		[page, .. as rest] => {
			decoded = SSG.decode_page!(page, frontmatter_page_decoder!)?
			content = render_frontmatter_page(decoded)
			SSG.write_file!({ output_dir, output_path: decoded.page.output_path, content })?
			process_frontmatter_pages!(rest, output_dir)
		}
	}

render_json_page : JsonDecodedPage -> Str
render_json_page = |{ content, generated_at, page }|
	render_page({
		title: content.title,
		body: Html.p([], [Html.text(content.body)]),
		generated_at,
		url: page.url,
	})

render_frontmatter_page : FrontmatterDecodedPage -> Str
render_frontmatter_page = |{ content, generated_at, page }|
	render_page({
		title: content.metadata.title,
		# The checked-in example source is trusted. Use Html.text for untrusted content.
		body: Html.div([], [Html.raw(content.body_html)]),
		generated_at,
		url: page.url,
	})

render_page : { title : Str, body : Html.Node, generated_at : U128, url : Str } -> Str
render_page = |{ title, body, generated_at, url }|
	Html.render_document(
		Html.html(
			[lang("en")],
			[
				Html.head([], [Html.title([], [Html.text(title)])]),
				Html.body(
					[],
					[
						Html.h1([], [Html.text(title)]),
						body,
						Html.p([], [Html.text("URL: ${url}")]),
						Html.p([], [Html.text("Generated at: ${Str.inspect(generated_at)}")]),
					],
				),
			],
		),
	)

## Frontmatter splitting is independent of the parser used for its metadata.
expect split_frontmatter("---\n{\"title\":\"Hello\"}\n---\n# Body")? == {
	metadata: "{\"title\":\"Hello\"}",
	body: "# Body",
}

## Frontmatter splitting accepts files with Windows CRLF line endings.
expect split_frontmatter("---\r\n{\"title\":\"Hello\"}\r\n---\r\n# Body")? == {
	metadata: "{\"title\":\"Hello\"}",
	body: "# Body",
}
