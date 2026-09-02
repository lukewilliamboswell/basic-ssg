import Html

## A resolved semantic AsciiDoc document. Inline raw HTML is trusted content:
## sanitize untrusted AsciiDoc before serving it.
AsciiDoc := [].{
	Inline :: [
		Text(Str),
		RawHtml(Str),
		Strong(Str),
		Emphasis(Str),
		Monospace(Str),
		Mark(Str),
		Superscript(Str),
		Subscript(Str),
		Link({ target : Str, text : Str }),
		CrossReference({ target : Str, text : Str }),
		Anchor({ id : Str, text : Str }),
		Image({ target : Str, alt : Str }),
		LineBreak,
		Footnote({ id : Str, text : Str }),
		Button(Str),
		Keyboard(List(Str)),
		Menu(List(Str)),
		UnsupportedInline({ kind : Str, html : Str }),
	]

	Block : {
		kind : Str,
		id : Str,
		roles : List(Str),
		title : Str,
		level : U64,
		source : Str,
		inlines : List(Inline),
		html : Str,
	}

	Warning : { message : Str, line : U64, column : U64 }

	Document : {
		title : Str,
		id : Str,
		roles : List(Str),
		blocks : List(Block),
		warnings : List(Warning),
	}

	view : Document -> Html.Node
	view = |document| Html.fragment(document.blocks.map(view_block))

	render : Document -> Str
	render = |document| Html.render_fragment(view(document))

	view_block : Block -> Html.Node
	view_block = |block| Html.raw(block.html)

	view_inlines : List(Inline) -> Html.Node
	view_inlines = |inlines| Html.fragment(inlines.map(view_inline))
}

view_inline : AsciiDoc.Inline -> Html.Node
view_inline = |inline|
	match inline {
		Text(value) => Html.text(value)
		RawHtml(value) | Strong(value) | Emphasis(value) | Monospace(value) | Mark(value) | Superscript(value) | Subscript(value) | Button(value) => Html.raw(value)
		Link({ text, .. }) | CrossReference({ text, .. }) | Anchor({ text, .. }) | Image({ alt: text, .. }) | Footnote({ text, .. }) => Html.raw(text)
		LineBreak => Html.br([])
		Keyboard(keys) | Menu(keys) => Html.text(Str.join_with(keys, " "))
		UnsupportedInline({ html, .. }) => Html.raw(html)
	}
