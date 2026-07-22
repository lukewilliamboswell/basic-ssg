## A small template included by the orchard guide documentation.
# This is a comment
app [transform_file_content] { pf: platform "platform/main.roc" }

import pf.Html
import pf.HtmlAttributes exposing [http_equiv, content, href, rel, lang, class, title]

NavLink : {
	# this is another comment
	url : Str,
	title : Str,
	text : Str,
}

nav_links : List(NavLink)
nav_links = [
	{ url: "apple.html", title: "Exempli Gratia Pagina Pomi", text: "Apple" },
	{ url: "banana.html", title: "Exempli Gratia Pagina Musa", text: "Banana" },
	{ url: "cherry.html", title: "Exempli Pagina Cerasus", text: "Cherry" },
]

transform_file_content : Str, Str -> Str
transform_file_content = |current_url, html_content|
	match nav_links.find_first(|{ url }| url == current_url) {
		Ok(current_nav_link) => Html.render_document(view(current_nav_link, html_content))
		Err(_) => ""
	}

### start snippet view
view : NavLink, Str -> Html.Node
view = |current_nav_link, html_content|
	Html.html(
		[lang("en")],
		[
			Html.head(
				[],
				[
					Html.meta([http_equiv("content-type"), content("text/html; charset=utf-8")]),
					Html.title([], [Html.text(current_nav_link.title)]),
					Html.link([rel("stylesheet"), href("style.css")]),
				],
			),

			### start snippet body
			Html.body(
				[],
				[
					Html.div(
						[class("main")],
						[
							Html.div(
								[class("navbar")],
								[
									view_navbar(current_nav_link),
								],
							),
							Html.div(
								[class("article")],
								[
									# This site's checked-in Markdown content is trusted. Use
									# `Html.text` instead for user-controlled content.
									Html.raw(html_content),
								],
							),
						],
					),
				],
			),

			### end snippet body
		],
	)

### end snippet view

view_navbar : NavLink -> Html.Node
view_navbar = |current_nav_link|
	Html.ul(
		[],
		nav_links.map(|nl| view_nav_link(nl == current_nav_link, nl)),
	)

view_nav_link : Bool, NavLink -> Html.Node
view_nav_link = |is_current, navlink|
	if is_current {
		Html.li(
			[class("nav-link nav-link--current")],
			[
				Html.text(navlink.text),
			],
		)
	} else {
		Html.li(
			[class("nav-link")],
			[
				Html.a(
					[href(navlink.url), title(navlink.title)],
					[Html.text(navlink.text)],
				),
			],
		)
	}
