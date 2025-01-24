app [main!] { pf: platform "../platform/main.roc" }

import pf.SSG
import pf.Types exposing [Args]
import pf.Html exposing [div, link, text, a, html, head, body, meta, ul, li]
import pf.Html.Attributes exposing [class, http_equiv, href, rel, content, lang, title]

main! : Args => Result {} _
main! = \{ input_dir, output_dir } ->

    # get the path and url of markdown files in content directory
    files = SSG.files!(input_dir)?

    # helper Task to process each file
    process_file! = \{ path, relpath, url } ->

        in_html = SSG.parse_markdown!(path)?

        out_html = transform_file_content(url, in_html)

        SSG.write_file!({ output_dir, relpath, content: out_html })

    ## process each file
    List.for_each_try!(files, process_file!)

transform_file_content : Str, Str -> Str
transform_file_content = \current_url, html_content ->
    when List.find_first(nav_links, \{ url } -> url == current_url) is
        Ok(current_nav_link) -> Html.render(view(current_nav_link, html_content))
        Err(_) -> crash("unable to find nav link for URL: $(current_url)")

NavLink : {
    url : Str,
    title : Str,
    text : Str,
}

nav_links : List NavLink
nav_links = [
    { url: "/index.html", title: "Home", text: "Home" },
    { url: "/fruit/apple.html", title: "Gratia Pagina", text: "Apple" },
    { url: "/fruit/banana.html", title: "Pagina Musa", text: "Banana" },
    { url: "/fruit/cherry.html", title: "Exempli Cerasus", text: "Cherry" },
    { url: "/people/index.html", title: "People", text: "People" },
]

view : NavLink, Str -> Html.Node
view = \current_nav_link, html_content ->
    html([lang("en")], [
        head([], [
            meta([http_equiv("content-type"), content("text/html; charset=utf-8")]),
            Html.title([], [text(current_nav_link.title)]),
            link([rel("stylesheet"), href("/style.css")]),
        ]),
        body([], [
            div([class("main")], [
                div([class("navbar")], [
                    view_navbar(current_nav_link),
                ]),
                div([class("article")], [
                    # For now `text` is not escaped so we can use it to insert HTML
                    # We'll probably want something more explicit in the long term though!
                    text(html_content),
                ]),
            ]),
        ]),
    ])

view_navbar : NavLink -> Html.Node
view_navbar = \current_nav_link ->
    ul(
        [],
        List.map(nav_links, \nl -> view_nav_link((nl == current_nav_link), nl)),
    )

view_nav_link : Bool, NavLink -> Html.Node
view_nav_link = \is_current, navlink ->
    if is_current then
        li([class("nav-link nav-link--current")], [
            text(navlink.text),
        ])
    else
        li([class("nav-link")], [
            a(
                [href(navlink.url), title(navlink.title)],
                [text(navlink.text)],
            ),
        ])
