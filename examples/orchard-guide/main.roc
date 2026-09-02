app [main!] { pf: platform "../../platform/main.roc" }

import pf.SSG
import pf.Path
import pf.OsStr exposing [OsStr]
import pf.Html
import pf.AsciiDoc
import pf.HtmlAttributes exposing [class, http_equiv, href, rel, content, lang, title]

main! : List(OsStr) => Try({}, [Exit(I32), PagesError(Str), ParseError(Str), WriteError(Str), ..])
main! = |args|
	match args.drop_first(1) {
		[input_dir_arg, output_dir_arg] => {
			input_dir = Path.from_os_str(input_dir_arg)
			output_dir = Path.from_os_str(output_dir_arg)

			# get the path and url of markdown pages in the content directory
			pages = SSG.pages!(input_dir)?
			asciidoc_pages = SSG.asciidoc_pages!(input_dir)?

			process_all!(pages, output_dir)?
			process_all_asciidoc!(asciidoc_pages, output_dir)
		}

		_ => Err(Exit(1))
	}

process_all! : List(SSG.Page), Path.Path => Try({}, [ParseError(Str), WriteError(Str), ..])
process_all! = |pages, output_dir|
	match pages {
		[] => Ok({})
		[page, .. as rest] => {
			process_page!(output_dir, page)?
			process_all!(rest, output_dir)
		}
	}

process_page! : Path.Path, SSG.Page => Try({}, [ParseError(Str), WriteError(Str), ..])
process_page! = |output_dir, page| {
	in_html = SSG.parse_markdown!(page.source_path)?
	out_html = transform_file_content(page.url, in_html)
	SSG.write_file!({ output_dir, output_path: page.output_path, content: out_html })
}

process_all_asciidoc! : List(SSG.Page), Path.Path => Try({}, [ParseError(Str), WriteError(Str), ..])
process_all_asciidoc! = |pages, output_dir|
	match pages {
		[] => Ok({})
		[page, .. as rest] => {
			document = SSG.parse_asciidoc!(page.source_path)?
			out_html = transform_file_content(page.url, AsciiDoc.render(document))
			SSG.write_file!({ output_dir, output_path: page.output_path, content: out_html })?
			process_all_asciidoc!(rest, output_dir)
		}
	}

NavLink : {
	url : Str,
	title : Str,
	text : Str,
}

nav_links : List(NavLink)
nav_links = [
	{ url: "/index.html", title: "The Orchard Guide", text: "Home" },
	{ url: "/fruit/apple.html", title: "Growing Apples", text: "Apples" },
	{ url: "/fruit/banana.html", title: "Growing Bananas", text: "Bananas" },
	{ url: "/fruit/cherry.html", title: "Growing Cherries", text: "Cherries" },
	{ url: "/fruit/pear.html", title: "Growing Pears", text: "Pears" },
	{ url: "/people/index.html", title: "Orchard Keepers", text: "People" },
]

transform_file_content : Str, Str -> Str
transform_file_content = |current_url, html_content|
	match nav_links.find_first(|link| link.url == current_url) {
		Ok(current_nav_link) => Html.render_document(view(current_nav_link, html_content))
		Err(_) => {
			crash "unable to find a nav link for the requested URL"
		}
	}

# NOTE: `view` is intentionally split into `view_head`/`view_body` subtree
# helpers rather than building the whole document inline. A single function that
# builds a full-document-sized tree currently triggers a compiler ARC-certifier
# ICE (roc-lang/roc#9825); keeping each function's tree small stays under the
# threshold.
view : NavLink, Str -> Html.Node
view = |current_nav_link, html_content|
	Html.html(
		[lang("en")],
		[
			view_head(current_nav_link),
			view_body(current_nav_link, html_content),
		],
	)

view_head : NavLink -> Html.Node
view_head = |current_nav_link|
	Html.head(
		[],
		[
			Html.meta([http_equiv("content-type"), content("text/html; charset=utf-8")]),
			Html.title([], [Html.text(current_nav_link.title)]),
			Html.link([rel("stylesheet"), href("/style.css")]),
		],
	)

view_body : NavLink, Str -> Html.Node
view_body = |current_nav_link, html_content|
	Html.body(
		[],
		[
			Html.div(
				[class("main")],
				[
					Html.div([class("navbar")], [view_navbar(current_nav_link)]),
					# This site's checked-in Markdown content is trusted, so its rendered HTML
					# can be inserted raw. Use `Html.text` for user-controlled content.
					Html.div([class("article")], [Html.raw(html_content)]),
				],
			),
		],
	)

view_navbar : NavLink -> Html.Node
view_navbar = |current_nav_link|
	Html.ul(
		[],
		nav_links.map(|nl| view_nav_link(nl == current_nav_link, nl)),
	)

view_nav_link : Bool, NavLink -> Html.Node
view_nav_link = |is_current, navlink|
	if is_current {
		Html.li([class("nav-link nav-link--current")], [Html.text(navlink.text)])
	} else {
		Html.li(
			[class("nav-link")],
			[Html.a([href(navlink.url), title(navlink.title)], [Html.text(navlink.text)])],
		)
	}
