app [main!] { pf: platform "../platform/main.roc" }

import pf.SSG
import pf.Html
import pf.HtmlAttributes exposing [class, http_equiv, href, rel, content, lang, title]

main! = |args|
    match List.drop_first(args, 1) {
        [input_dir, output_dir] => {
            # get the path and url of markdown files in the content directory
            files = SSG.files!(input_dir)?

            # process each markdown file into an HTML page
            process_all!(files, output_dir)
        }

        _ => Err(Exit(1))
    }

process_all! : List(SSG.Files), Str => Try({}, _)
process_all! = |files, output_dir|
    match files {
        [] => Ok({})
        [file, .. as rest] => {
            _ = process_file!(output_dir, file)?
            process_all!(rest, output_dir)
        }
    }

process_file! : Str, SSG.Files => Try({}, _)
process_file! = |output_dir, file| {
    in_html = SSG.parse_markdown!(file.path)?
    out_html = transform_file_content(file.url, in_html)
    SSG.write_file!({ output_dir, relpath: file.relpath, content: out_html })
}

NavLink : {
    url : Str,
    title : Str,
    text : Str,
}

nav_links : List(NavLink)
nav_links = [
    { url: "/index.html", title: "Home", text: "Home" },
    { url: "/fruit/apple.html", title: "Gratia Pagina", text: "Apple" },
    { url: "/fruit/banana.html", title: "Pagina Musa", text: "Banana" },
    { url: "/fruit/cherry.html", title: "Exempli Cerasus", text: "Cherry" },
    { url: "/people/index.html", title: "People", text: "People" },
]

transform_file_content : Str, Str -> Str
transform_file_content = |current_url, html_content|
    match List.find_first(nav_links, |link| link.url == current_url) {
        Ok(current_nav_link) => Html.render(view(current_nav_link, html_content))
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
                    # For now `text` is not escaped so we can use it to insert HTML.
                    # We'll probably want something more explicit in the long term though!
                    Html.div([class("article")], [Html.text(html_content)]),
                ],
            ),
        ],
    )

view_navbar : NavLink -> Html.Node
view_navbar = |current_nav_link|
    Html.ul(
        [],
        List.map(nav_links, |nl| view_nav_link(nl == current_nav_link, nl)),
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
