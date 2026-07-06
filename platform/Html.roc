import HtmlAttributes exposing [Attribute]

Html := [].{
	Node :: [
		Text(Str),
		Element(Str, U64, List(Attribute), List(Node)),
		UnclosedElem(Str, U64, List(Attribute)),
	]

	ElementBuilder : List(Attribute), List(Node) -> Node

	UnclosedBuilder : List(Attribute) -> Node

	attribute : Str -> (Str -> Attribute)
	attribute = HtmlAttributes.attribute

	text : Str -> Node
	text = |s| Text(s)

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
	element : Str -> (List(Attribute), List(Node) -> Node)
	element = |tag_name|
		|attrs, children| {
			# While building the node tree, calculate the size of Str it will render to
			with_tag = 2 * (3 + tag_name.count_utf8_bytes())
			with_attrs = attrs.fold(
				with_tag,
				|acc, HtmlAttributes.Attribute.Attribute(name, val)|
					acc + name.count_utf8_bytes() + val.count_utf8_bytes() + 4,
			)
			total_size = children.fold(
				with_attrs,
				|acc, child|
					acc + node_size(child),
			)

			Element(tag_name, total_size, attrs, children)
		}

	unclosed_elem : Str -> (List(Attribute) -> Node)
	unclosed_elem = |tag_name|
		|attrs| {
			# While building the node tree, calculate the size of Str it will render to
			with_tag = 2 * (3 + tag_name.count_utf8_bytes())
			total_size = attrs.fold(
				with_tag,
				|acc, HtmlAttributes.Attribute.Attribute(name, val)|
					acc + name.count_utf8_bytes() + val.count_utf8_bytes() + 4,
			)

			UnclosedElem(tag_name, total_size, attrs)
		}

	# internal helper
	node_size : Node -> U64
	node_size = |node|
		match node {
			Text(content) =>
				content.count_utf8_bytes()

			Element(_, size, _, _) =>
				size

			UnclosedElem(_, size, _) =>
				size
			}

	## Render a Node to an HTML string
	##
	## The output has no whitespace between nodes, to make it small.
	## This is intended for generating full HTML documents, so it
	## automatically adds `<!DOCTYPE html>` to the start of the string.
	## See also `renderWithoutDocType`.
	render : Node -> Str
	render = |node| {
		buffer = Str.reserve("<!DOCTYPE html>", node_size(node))

		render_help(buffer, node)
	}

	## Render a Node to a string, without a DOCTYPE tag
	render_without_doc_type : Node -> Str
	render_without_doc_type = |node| {
		buffer = Str.reserve("", node_size(node))

		render_help(buffer, node)
	}

	# internal helper
	render_help : Str, Node -> Str
	render_help = |buffer, node|
		match node {
			Text(content) =>
				buffer.concat(content)

			Element(tag_name, _, attrs, children) => {
				with_tag_name = "${buffer}<${tag_name}"
				with_attrs = if attrs.is_empty() {
					with_tag_name
				} else {
					attrs.fold(with_tag_name, render_attr)
				}
				with_tag = with_attrs.concat(">")
				# Use explicit recursion (not `children.fold(with_tag, render_help)`)
				# to avoid a compiler ARC-certifier ICE on recursion through a folded closure.
				with_children = render_children(with_tag, children)

				"${with_children}</${tag_name}>"
			}

			UnclosedElem(tag_name, _, attrs) =>
				if attrs.is_empty() {
					"${buffer}<${tag_name}>"
				} else {
					folded = attrs.fold("${buffer}<${tag_name}", render_attr)
					folded.concat(">")
				}
			}

	# internal helper: render each child node in order, threading the buffer.
	render_children : Str, List(Node) -> Str
	render_children = |buffer, nodes|
		match nodes {
			[] => buffer
			[first, .. as rest] => render_children(render_help(buffer, first), rest)
		}

	# internal helper
	render_attr : Str, Attribute -> Str
	render_attr = |buffer, HtmlAttributes.Attribute.Attribute(key, val)|
		"${buffer} ${key}=\"${val}\""

	# Main root
	html : ElementBuilder
	html = element("html")

	# Document metadata
	base : ElementBuilder
	base = element("base")

	head : ElementBuilder
	head = element("head")

	link : UnclosedBuilder
	link = unclosed_elem("link")

	meta : UnclosedBuilder
	meta = unclosed_elem("meta")

	style : ElementBuilder
	style = element("style")

	title : ElementBuilder
	title = element("title")

	# Sectioning root
	body : ElementBuilder
	body = element("body")

	# Content sectioning
	address : ElementBuilder
	address = element("address")

	article : ElementBuilder
	article = element("article")

	aside : ElementBuilder
	aside = element("aside")

	footer : ElementBuilder
	footer = element("footer")

	header : ElementBuilder
	header = element("header")

	h1 : ElementBuilder
	h1 = element("h1")

	h2 : ElementBuilder
	h2 = element("h2")

	h3 : ElementBuilder
	h3 = element("h3")

	h4 : ElementBuilder
	h4 = element("h4")

	h5 : ElementBuilder
	h5 = element("h5")

	h6 : ElementBuilder
	h6 = element("h6")

	main : ElementBuilder
	main = element("main")

	nav : ElementBuilder
	nav = element("nav")

	section : ElementBuilder
	section = element("section")

	# Text content
	blockquote : ElementBuilder
	blockquote = element("blockquote")

	dd : ElementBuilder
	dd = element("dd")

	div : ElementBuilder
	div = element("div")

	dl : ElementBuilder
	dl = element("dl")

	dt : ElementBuilder
	dt = element("dt")

	figcaption : ElementBuilder
	figcaption = element("figcaption")

	figure : ElementBuilder
	figure = element("figure")

	hr : ElementBuilder
	hr = element("hr")

	li : ElementBuilder
	li = element("li")

	menu : ElementBuilder
	menu = element("menu")

	ol : ElementBuilder
	ol = element("ol")

	p : ElementBuilder
	p = element("p")

	pre : ElementBuilder
	pre = element("pre")

	ul : ElementBuilder
	ul = element("ul")

	# Inline text semantics
	a : ElementBuilder
	a = element("a")

	abbr : ElementBuilder
	abbr = element("abbr")

	b : ElementBuilder
	b = element("b")

	bdi : ElementBuilder
	bdi = element("bdi")

	bdo : ElementBuilder
	bdo = element("bdo")

	br : ElementBuilder
	br = element("br")

	cite : ElementBuilder
	cite = element("cite")

	code : ElementBuilder
	code = element("code")

	data : ElementBuilder
	data = element("data")

	dfn : ElementBuilder
	dfn = element("dfn")

	em : ElementBuilder
	em = element("em")

	i : ElementBuilder
	i = element("i")

	kbd : ElementBuilder
	kbd = element("kbd")

	mark : ElementBuilder
	mark = element("mark")

	q : ElementBuilder
	q = element("q")

	rp : ElementBuilder
	rp = element("rp")

	rt : ElementBuilder
	rt = element("rt")

	ruby : ElementBuilder
	ruby = element("ruby")

	s : ElementBuilder
	s = element("s")

	samp : ElementBuilder
	samp = element("samp")

	small : ElementBuilder
	small = element("small")

	span : ElementBuilder
	span = element("span")

	strong : ElementBuilder
	strong = element("strong")

	sub : ElementBuilder
	sub = element("sub")

	sup : ElementBuilder
	sup = element("sup")

	time : ElementBuilder
	time = element("time")

	u : ElementBuilder
	u = element("u")

	# `var` is a reserved keyword in the new compiler, so this constructor
	# for the HTML <var> element is named `var_`.
	var_ : ElementBuilder
	var_ = element("var")

	wbr : ElementBuilder
	wbr = element("wbr")

	# Image and multimedia
	area : ElementBuilder
	area = element("area")

	audio : ElementBuilder
	audio = element("audio")

	img : UnclosedBuilder
	img = unclosed_elem("img")

	map : ElementBuilder
	map = element("map")

	track : ElementBuilder
	track = element("track")

	video : ElementBuilder
	video = element("video")

	# Embedded content
	embed : ElementBuilder
	embed = element("embed")

	iframe : ElementBuilder
	iframe = element("iframe")

	object : ElementBuilder
	object = element("object")

	picture : ElementBuilder
	picture = element("picture")

	portal : ElementBuilder
	portal = element("portal")

	source : ElementBuilder
	source = element("source")

	# SVG and MathML
	svg : ElementBuilder
	svg = element("svg")

	math : ElementBuilder
	math = element("math")

	# Scripting
	canvas : ElementBuilder
	canvas = element("canvas")

	noscript : ElementBuilder
	noscript = element("noscript")

	script : ElementBuilder
	script = element("script")

	# Demarcating edits
	del : ElementBuilder
	del = element("del")

	ins : ElementBuilder
	ins = element("ins")

	# Table content
	caption : ElementBuilder
	caption = element("caption")

	col : ElementBuilder
	col = element("col")

	colgroup : ElementBuilder
	colgroup = element("colgroup")

	table : ElementBuilder
	table = element("table")

	tbody : ElementBuilder
	tbody = element("tbody")

	td : ElementBuilder
	td = element("td")

	tfoot : ElementBuilder
	tfoot = element("tfoot")

	th : ElementBuilder
	th = element("th")

	thead : ElementBuilder
	thead = element("thead")

	tr : ElementBuilder
	tr = element("tr")

	# Forms
	button : ElementBuilder
	button = element("button")

	datalist : ElementBuilder
	datalist = element("datalist")

	fieldset : ElementBuilder
	fieldset = element("fieldset")

	form : ElementBuilder
	form = element("form")

	input : ElementBuilder
	input = element("input")

	label : ElementBuilder
	label = element("label")

	legend : ElementBuilder
	legend = element("legend")

	meter : ElementBuilder
	meter = element("meter")

	optgroup : ElementBuilder
	optgroup = element("optgroup")

	option : ElementBuilder
	option = element("option")

	output : ElementBuilder
	output = element("output")

	progress : ElementBuilder
	progress = element("progress")

	select : ElementBuilder
	select = element("select")

	textarea : ElementBuilder
	textarea = element("textarea")

	# Interactive elements
	details : ElementBuilder
	details = element("details")

	dialog : ElementBuilder
	dialog = element("dialog")

	summary : ElementBuilder
	summary = element("summary")

	# Web Components
	slot : ElementBuilder
	slot = element("slot")

	template : ElementBuilder
	template = element("template")
}

## Html.render emits a doctype and renders attributes without extra whitespace.
expect {
	rendered = Html.render(Html.div([HtmlAttributes.class("main")], [Html.text("Hello")]))
	rendered == "<!DOCTYPE html><div class=\"main\">Hello</div>"
}

## Html.render_without_doc_type renders unclosed elements without a doctype.
expect {
	rendered = Html.render_without_doc_type(Html.meta([HtmlAttributes.charset("utf-8")]))
	rendered == "<meta charset=\"utf-8\">"
}

## HtmlAttributes.aria_hidden renders the aria-hidden attribute.
expect {
	rendered = Html.render_without_doc_type(Html.div([HtmlAttributes.aria_hidden("true")], []))
	rendered == "<div aria-hidden=\"true\"></div>"
}
