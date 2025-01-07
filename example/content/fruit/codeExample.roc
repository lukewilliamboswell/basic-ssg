## This is a documentation comment
# This is a comment
app [transform_file_content] { pf: platform "platform/main.roc" }

import pf.Html exposing [html, head, body, div, text, a, ul, li, link, meta]
import pf.Html.Attributes exposing [http_equiv, content, href, rel, lang, class, title]

NavLink : {
    # this is another comment
    url : Str,
    title : Str,
    text : Str,
}

nav_links : List NavLink
nav_links = [
    { url: "apple.html", title: "Exempli Gratia Pagina Pomi", text: "Apple" },
    { url: "banana.html", title: "Exempli Gratia Pagina Musa", text: "Banana" },
    { url: "cherry.html", title: "Exempli Pagina Cerasus", text: "Cherry" },
]

transform_file_content : Str, Str -> Str
transform_file_content = \current_url, html_content ->
    List.find_first(nav_links, \{ url } -> url == current_url)
    |> Result.map(\current_nav_link -> view(current_nav_link, html_content))
    |> Result.map(Html.render)
    |> Result.with_default("")

### start snippet view
view : NavLink, Str -> Html.Node
view = \current_nav_link, html_content ->
    html([lang("en")], [
        head([], [
            meta([http_equiv("content-type"), content("text/html; charset=utf-8")], []),
            Html.title([], [text(current_nav_link.title)]),
            link([rel("stylesheet"), href("style.css")], []),
        ]),
        ### start snippet body
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
        ### end snippet body
    ])
### end snippet view

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
