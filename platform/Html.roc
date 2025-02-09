module [
    Node,
    Attribute,
    render,
    render_without_doc_type,
    element,
    unclosed_elem,
    text,
    attribute,
    html,
    base,
    head,
    link,
    meta,
    style,
    title,
    body,
    address,
    article,
    aside,
    footer,
    header,
    h1,
    h2,
    h3,
    h4,
    h5,
    h6,
    main,
    nav,
    section,
    blockquote,
    dd,
    div,
    dl,
    dt,
    figcaption,
    figure,
    hr,
    li,
    menu,
    ol,
    p,
    pre,
    ul,
    a,
    abbr,
    b,
    bdi,
    bdo,
    br,
    cite,
    code,
    data,
    dfn,
    em,
    i,
    kbd,
    mark,
    q,
    rp,
    rt,
    ruby,
    s,
    samp,
    small,
    span,
    strong,
    sub,
    sup,
    time,
    u,
    var,
    wbr,
    area,
    audio,
    img,
    map,
    track,
    video,
    embed,
    iframe,
    object,
    picture,
    portal,
    source,
    svg,
    math,
    canvas,
    noscript,
    script,
    del,
    ins,
    caption,
    col,
    colgroup,
    table,
    tbody,
    td,
    tfoot,
    th,
    thead,
    tr,
    button,
    datalist,
    fieldset,
    form,
    input,
    label,
    legend,
    meter,
    optgroup,
    option,
    output,
    progress,
    select,
    textarea,
    details,
    dialog,
    summary,
    slot,
    template,
]

import Html.Attributes

Node : [
    Text Str,
    Element Str U64 (List Attribute) (List Node),
    UnclosedElem Str U64 (List Attribute),
]

Attribute : Html.Attributes.Attribute

attribute : Str -> (Str -> Attribute)
attribute = Html.Attributes.attribute

text : Str -> Node
text = Text

## Define a non-standard HTML Element
##
## You can use this to add elements that are not already supported.
## For example, you could bring back the obsolete <blink> element,
## and add some 90's nostalgia to your web page!
##
## blink : List Attribute, List Node -> Node
## blink = element "blink"
##
## html = blink [] [ text "This text is blinking!" ]
##
element : Str -> (List Attribute, List Node -> Node)
element = \tag_name ->
    \attrs, children ->
        # While building the node tree, calculate the size of Str it will render to
        with_tag = 2 * (3 + Str.count_utf8_bytes(tag_name))
        with_attrs = List.walk(attrs, with_tag, \acc, Attribute(name, val) ->
            acc + Str.count_utf8_bytes(name) + Str.count_utf8_bytes(val) + 4)
        total_size = List.walk(children, with_attrs, \acc, child ->
            acc + node_size(child))

        Element(tag_name, total_size, attrs, children)

unclosed_elem : Str -> (List Attribute -> Node)
unclosed_elem = \tag_name ->
    \attrs ->
        # While building the node tree, calculate the size of Str it will render to
        with_tag = 2 * (3 + Str.count_utf8_bytes(tag_name))
        total_size = List.walk(attrs, with_tag, \acc, Attribute(name, val) ->
            acc + Str.count_utf8_bytes(name) + Str.count_utf8_bytes(val) + 4)

        UnclosedElem(tag_name, total_size, attrs)

# internal helper
node_size : Node -> U64
node_size = \node ->
    when node is
        Text(content) ->
            Str.count_utf8_bytes(content)

        Element(_, size, _, _) | UnclosedElem(_, size, _) ->
            size

## Render a Node to an HTML string
##
## The output has no whitespace between nodes, to make it small.
## This is intended for generating full HTML documents, so it
## automatically adds `<!DOCTYPE html>` to the start of the string.
## See also `renderWithoutDocType`.
render : Node -> Str
render = \node ->
    buffer = Str.reserve("<!DOCTYPE html>", node_size(node))

    render_help(buffer, node)

## Render a Node to a string, without a DOCTYPE tag
render_without_doc_type : Node -> Str
render_without_doc_type = \node ->
    buffer = Str.reserve("", node_size(node))

    render_help(buffer, node)

# internal helper
render_help : Str, Node -> Str
render_help = \buffer, node ->
    when node is
        Text(content) ->
            Str.concat(buffer, content)

        Element(tag_name, _, attrs, children) ->
            with_tag_name = "$(buffer)<$(tag_name)"
            with_attrs =
                if List.is_empty(attrs) then
                    with_tag_name
                else
                    List.walk(attrs, "$(with_tag_name) ", render_attr)
            with_tag = Str.concat(with_attrs, ">")
            with_children = List.walk(children, with_tag, render_help)

            "$(with_children)</$(tag_name)>"

        UnclosedElem(tag_name, _, attrs) ->
            if List.is_empty(attrs) then
                "$(buffer)<$(tag_name)>"
            else
                attrs
                |> List.walk("$(buffer)<$(tag_name) ", render_attr)
                |> Str.concat(">")

# internal helper
render_attr : Str, Attribute -> Str
render_attr = \buffer, Attribute(key, val) ->
    "$(buffer) $(key)=\"$(val)\""

# Main root
html = element("html")

# Document metadata
base = element("base")
head = element("head")
link = unclosed_elem("link")
meta = unclosed_elem("meta")
style = element("style")
title = element("title")

# Sectioning root
body = element("body")

# Content sectioning
address = element("address")
article = element("article")
aside = element("aside")
footer = element("footer")
header = element("header")
h1 = element("h1")
h2 = element("h2")
h3 = element("h3")
h4 = element("h4")
h5 = element("h5")
h6 = element("h6")
main = element("main")
nav = element("nav")
section = element("section")

# Text content
blockquote = element("blockquote")
dd = element("dd")
div = element("div")
dl = element("dl")
dt = element("dt")
figcaption = element("figcaption")
figure = element("figure")
hr = element("hr")
li = element("li")
menu = element("menu")
ol = element("ol")
p = element("p")
pre = element("pre")
ul = element("ul")

# Inline text semantics
a = element("a")
abbr = element("abbr")
b = element("b")
bdi = element("bdi")
bdo = element("bdo")
br = element("br")
cite = element("cite")
code = element("code")
data = element("data")
dfn = element("dfn")
em = element("em")
i = element("i")
kbd = element("kbd")
mark = element("mark")
q = element("q")
rp = element("rp")
rt = element("rt")
ruby = element("ruby")
s = element("s")
samp = element("samp")
small = element("small")
span = element("span")
strong = element("strong")
sub = element("sub")
sup = element("sup")
time = element("time")
u = element("u")
var = element("var")
wbr = element("wbr")

# Image and multimedia
area = element("area")
audio = element("audio")
img = unclosed_elem("img")
map = element("map")
track = element("track")
video = element("video")

# Embedded content
embed = element("embed")
iframe = element("iframe")
object = element("object")
picture = element("picture")
portal = element("portal")
source = element("source")

# SVG and MathML
svg = element("svg")
math = element("math")

# Scripting
canvas = element("canvas")
noscript = element("noscript")
script = element("script")

# Demarcating edits
del = element("del")
ins = element("ins")

# Table content
caption = element("caption")
col = element("col")
colgroup = element("colgroup")
table = element("table")
tbody = element("tbody")
td = element("td")
tfoot = element("tfoot")
th = element("th")
thead = element("thead")
tr = element("tr")

# Forms
button = element("button")
datalist = element("datalist")
fieldset = element("fieldset")
form = element("form")
input = element("input")
label = element("label")
legend = element("legend")
meter = element("meter")
optgroup = element("optgroup")
option = element("option")
output = element("output")
progress = element("progress")
select = element("select")
textarea = element("textarea")

# Interactive elements
details = element("details")
dialog = element("dialog")
summary = element("summary")

# Web Components
slot = element("slot")
template = element("template")
