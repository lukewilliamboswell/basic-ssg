app [main] { pf: platform "../platform/main.roc" }

import pf.Task exposing [Task]
import pf.SSG
import pf.Types exposing [Args]
import pf.Html exposing [div, link, text, a, html, head, body, meta, ul, li]
import pf.Html.Attributes exposing [class, httpEquiv, href, rel, content, lang, title]

main : Args -> Task {} _
main = \{ inputDir, outputDir } ->

    # get the path and url of markdown files in content directory
    files = SSG.files! inputDir

    # helper Task to process each file
    processFile = \{ path, relpath, url } ->

        inHtml = SSG.parseMarkdown! path

        outHtml = transformFileContent url inHtml

        SSG.writeFile { outputDir, relpath, content: outHtml }
    ## process each file
    Task.forEach! files processFile

transformFileContent : Str, Str -> Str
transformFileContent = \currentUrl, htmlContent ->
    when List.findFirst navLinks (\{ url } -> url == currentUrl) is
        Ok currentNavLink -> Html.render (view currentNavLink htmlContent)
        Err _ -> crash "unable to find nav link for URL: $(currentUrl)"

NavLink : {
    url : Str,
    title : Str,
    text : Str,
}

navLinks : List NavLink
navLinks = [
    { url: "/index.html", title: "Home", text: "Home" },
    { url: "/fruit/apple.html", title: "Gratia Pagina", text: "Apple" },
    { url: "/fruit/banana.html", title: "Pagina Musa", text: "Banana" },
    { url: "/fruit/cherry.html", title: "Exempli Cerasus", text: "Cherry" },
    { url: "/people/index.html", title: "People", text: "People" },
]

view : NavLink, Str -> Html.Node
view = \currentNavLink, htmlContent ->
    html [lang "en"] [
        head [] [
            meta [httpEquiv "content-type", content "text/html; charset=utf-8"],
            Html.title [] [text currentNavLink.title],
            link [rel "stylesheet", href "/style.css"],
        ],
        body [] [
            div [class "main"] [
                div [class "navbar"] [
                    viewNavbar currentNavLink,
                ],
                div [class "article"] [
                    # For now `text` is not escaped so we can use it to insert HTML
                    # We'll probably want something more explicit in the long term though!
                    text htmlContent,
                ],
            ],
        ],
    ]

viewNavbar : NavLink -> Html.Node
viewNavbar = \currentNavLink ->
    ul
        []
        (List.map navLinks \nl -> viewNavLink (nl == currentNavLink) nl)

viewNavLink : Bool, NavLink -> Html.Node
viewNavLink = \isCurrent, navlink ->
    if isCurrent then
        li [class "nav-link nav-link--current"] [
            text navlink.text,
        ]
    else
        li [class "nav-link"] [
            a
                [href navlink.url, title navlink.title]
                [text navlink.text],
        ]
