import HtmlAttributes exposing [Attribute]

Html := [].{
	Node :: [
		Text(Str),
		Raw(Str),
		Element(Str, U64, List(Attribute), List(Node)),
		VoidElement(Str, U64, List(Attribute)),
	]

	ElementBuilder : List(Attribute), List(Node) -> Node

	VoidBuilder : List(Attribute) -> Node

	attribute : Str -> (Str -> Attribute)
	attribute = |name| HtmlAttributes.attribute(name)

	## Create an escaped text node. Characters with special meaning in HTML are
	## encoded when the node is rendered.
	text : Str -> Node
	text = |s| Text(s)

	## Insert trusted HTML without escaping it.
	##
	## Prefer [`text`](#text) for all user-controlled or plain-text content. Use
	## `raw` only for trusted markup, such as `SSG.parse_markdown!` output when
	## the source Markdown is trusted.
	raw : Str -> Node
	raw = |s| Raw(s)

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

	void_element : Str -> (List(Attribute) -> Node)
	void_element = |tag_name|
		|attrs| {
			# While building the node tree, calculate the size of Str it will render to
			with_tag = 2 * (3 + tag_name.count_utf8_bytes())
			total_size = attrs.fold(
				with_tag,
				|acc, HtmlAttributes.Attribute.Attribute(name, val)|
					acc + name.count_utf8_bytes() + val.count_utf8_bytes() + 4,
			)

			VoidElement(tag_name, total_size, attrs)
		}

	# internal helper
	node_size : Node -> U64
	node_size = |node|
		match node {
			Text(content) | Raw(content) =>
				content.count_utf8_bytes()

			Element(_, size, _, _) =>
				size

			VoidElement(_, size, _) =>
				size
			}

	## Render a complete HTML document, including the `<!DOCTYPE html>` prefix.
	##
	## The output has no whitespace inserted between nodes.
	render_document : Node -> Str
	render_document = |node| {
		buffer = Str.reserve("<!DOCTYPE html>", node_size(node))

		render_help(buffer, node)
	}

	## Render an HTML fragment without a doctype prefix.
	render_fragment : Node -> Str
	render_fragment = |node| {
		buffer = Str.reserve("", node_size(node))

		render_help(buffer, node)
	}

	# internal helper
	render_help : Str, Node -> Str
	render_help = |buffer, node|
		match node {
			Text(content) =>
				buffer.concat(escape_text(content))

			Raw(content) =>
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

			VoidElement(tag_name, _, attrs) =>
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
		"${buffer} ${key}=\"${escape_attribute(val)}\""

	# internal helper
	escape_text : Str -> Str
	escape_text = |content| {
		with_ampersands = Str.join_with(content.split_on("&"), "&amp;")
		with_less_thans = Str.join_with(with_ampersands.split_on("<"), "&lt;")
		Str.join_with(with_less_thans.split_on(">"), "&gt;")
	}

	# internal helper
	escape_attribute : Str -> Str
	escape_attribute = |value| {
		with_text_escaped = escape_text(value)
		with_quotes = Str.join_with(with_text_escaped.split_on("\""), "&quot;")
		Str.join_with(with_quotes.split_on("'"), "&#39;")
	}

	# Main root
	html : ElementBuilder
	html = element("html")

	# Document metadata
	base : VoidBuilder
	base = void_element("base")

	head : ElementBuilder
	head = element("head")

	link : VoidBuilder
	link = void_element("link")

	meta : VoidBuilder
	meta = void_element("meta")

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

	hr : VoidBuilder
	hr = void_element("hr")

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

	br : VoidBuilder
	br = void_element("br")

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

	wbr : VoidBuilder
	wbr = void_element("wbr")

	# Image and multimedia
	area : VoidBuilder
	area = void_element("area")

	audio : ElementBuilder
	audio = element("audio")

	img : VoidBuilder
	img = void_element("img")

	map : ElementBuilder
	map = element("map")

	track : VoidBuilder
	track = void_element("track")

	video : ElementBuilder
	video = element("video")

	# Embedded content
	embed : VoidBuilder
	embed = void_element("embed")

	iframe : ElementBuilder
	iframe = element("iframe")

	object : ElementBuilder
	object = element("object")

	picture : ElementBuilder
	picture = element("picture")

	portal : ElementBuilder
	portal = element("portal")

	source : VoidBuilder
	source = void_element("source")

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

	col : VoidBuilder
	col = void_element("col")

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

	input : VoidBuilder
	input = void_element("input")

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

## Html.render_document emits a doctype and escapes text and attribute values.
expect {
	rendered = Html.render_document(
		Html.div(
			[HtmlAttributes.title("A \"quote\" & <tag>")],
			[Html.text("Hello & <world>")],
		),
	)
	rendered == "<!DOCTYPE html><div title=\"A &quot;quote&quot; &amp; &lt;tag&gt;\">Hello &amp; &lt;world&gt;</div>"
}

## Html.render_fragment renders void elements without a doctype or closing tag.
expect {
	rendered = Html.render_fragment(Html.meta([HtmlAttributes.charset("utf-8")]))
	rendered == "<meta charset=\"utf-8\">"
}

## Html.raw explicitly preserves trusted markup while neighboring text is escaped.
expect {
	rendered = Html.render_fragment(
		Html.div([], [Html.text("<safe>"), Html.raw("<strong>trusted</strong>")]),
	)
	rendered == "<div>&lt;safe&gt;<strong>trusted</strong></div>"
}

## Every HTML void element renders without children or a closing tag.
expect {
	rendered = Html.render_fragment(
		Html.div(
			[],
			[
				Html.base([]),
				Html.link([]),
				Html.meta([]),
				Html.hr([]),
				Html.br([]),
				Html.wbr([]),
				Html.area([]),
				Html.img([]),
				Html.track([]),
				Html.embed([]),
				Html.source([]),
				Html.col([]),
				Html.input([]),
			],
		),
	)
	rendered == "<div><base><link><meta><hr><br><wbr><area><img><track><embed><source><col><input></div>"
}
