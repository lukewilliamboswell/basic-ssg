app "simple"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Task.{Task},
        pf.SSG,
        pf.Html.{ html, head, body, div, text, a, ul, li, link, meta },
        pf.Html.Attributes.{ httpEquiv, content, href, rel, lang, class, title },
        "style.css" as styleCss : Str,
    ]
    provides [main] to pf

main : SSG.Args -> Task {} _
main = \{inputDir, outputDir} ->

    # get the path and url of markdown files in content directory
    files = SSG.files! inputDir

    # helper Task to process each file
    processFile = \{path, url} ->

        inHtml = SSG.parseMarkdown! path

        outHtml = 
            transform url inHtml 
            |> Task.fromResult
            |> Task.mapErr! \err -> (ErrorGeneratingHtml path err)

        SSG.writeFile {
            outputDir, 
            relPath: url, 
            content: outHtml,
        }

    # process each file
    Task.forEach! files processFile

    # copy across our static asset 
    SSG.writeFile! {
        outputDir,
        relPath: "style.css",
        content: styleCss,
    }

navLinks = [
    { url: "/apple.html", title: "Foo", text: "First" },
    { url: "/subFolder/apple.html", title: "Bar", text: "Second" },
    { url: "/banana.html", title: "Baz", text: "Third" },
    { url: "/cherry.html", title: "FooBar", text: "Fourth" },
]

transform : Str, Str -> Result Str _
transform = \currentUrl, inHtml ->
    
    currentPage <- 
        navLinks
        |> List.findFirst  \{ url } -> url == currentUrl
        |> Result.try
        
    view currentPage inHtml 
    |> Html.render
    |> Ok

view = \currentPage, inHtml ->
    html [lang "en"] [
        head [] [
            meta [httpEquiv "content-type", content "text/html; charset=utf-8"],
            Html.title [] [text currentPage.title],
            link [rel "stylesheet", href "/style.css"],
        ],
        body [] [
            div [class "main"] [
                div [class "navbar"] [
                    ul [] (List.map navLinks \nl -> viewNavLink (nl == currentPage) nl),
                ],
                div [class "article"] [
                    # For now `text` is not escaped so we can use it to insert HTML
                    # We'll probably want something more explicit in the long term though!
                    text inHtml,
                ],
            ],
        ],
    ]

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
    