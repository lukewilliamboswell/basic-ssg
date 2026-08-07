HtmlAttributes := [].{
	Attribute := [Attribute(Str, Str)]

	AttrBuilder : Str -> Attribute

	attribute : Str -> (Str -> Attribute)
	attribute = |attr_name|
		|attr_value| Attribute(attr_name, attr_value)

	accept : AttrBuilder
	accept = |v| Attribute("accept", v)

	accept_charset : AttrBuilder
	accept_charset = |v| Attribute("accept-charset", v)

	accesskey : AttrBuilder
	accesskey = |v| Attribute("accesskey", v)

	action : AttrBuilder
	action = |v| Attribute("action", v)

	align : AttrBuilder
	align = |v| Attribute("align", v)

	allow : AttrBuilder
	allow = |v| Attribute("allow", v)

	alt : AttrBuilder
	alt = |v| Attribute("alt", v)

	aria_label : AttrBuilder
	aria_label = |v| Attribute("aria-label", v)

	aria_labelled_by : AttrBuilder
	aria_labelled_by = |v| Attribute("aria-labelledby", v)

	aria_hidden : AttrBuilder
	aria_hidden = |v| Attribute("aria-hidden", v)

	async : AttrBuilder
	async = |v| Attribute("async", v)

	autocapitalize : AttrBuilder
	autocapitalize = |v| Attribute("autocapitalize", v)

	autocomplete : AttrBuilder
	autocomplete = |v| Attribute("autocomplete", v)

	autofocus : AttrBuilder
	autofocus = |v| Attribute("autofocus", v)

	autoplay : AttrBuilder
	autoplay = |v| Attribute("autoplay", v)

	background : AttrBuilder
	background = |v| Attribute("background", v)

	bgcolor : AttrBuilder
	bgcolor = |v| Attribute("bgcolor", v)

	border : AttrBuilder
	border = |v| Attribute("border", v)

	buffered : AttrBuilder
	buffered = |v| Attribute("buffered", v)

	capture : AttrBuilder
	capture = |v| Attribute("capture", v)

	challenge : AttrBuilder
	challenge = |v| Attribute("challenge", v)

	charset : AttrBuilder
	charset = |v| Attribute("charset", v)

	checked : AttrBuilder
	checked = |v| Attribute("checked", v)

	cite : AttrBuilder
	cite = |v| Attribute("cite", v)

	class : AttrBuilder
	class = |v| Attribute("class", v)

	code : AttrBuilder
	code = |v| Attribute("code", v)

	codebase : AttrBuilder
	codebase = |v| Attribute("codebase", v)

	color : AttrBuilder
	color = |v| Attribute("color", v)

	cols : AttrBuilder
	cols = |v| Attribute("cols", v)

	colspan : AttrBuilder
	colspan = |v| Attribute("colspan", v)

	content : AttrBuilder
	content = |v| Attribute("content", v)

	contenteditable : AttrBuilder
	contenteditable = |v| Attribute("contenteditable", v)

	contextmenu : AttrBuilder
	contextmenu = |v| Attribute("contextmenu", v)

	controls : AttrBuilder
	controls = |v| Attribute("controls", v)

	coords : AttrBuilder
	coords = |v| Attribute("coords", v)

	crossorigin : AttrBuilder
	crossorigin = |v| Attribute("crossorigin", v)

	csp : AttrBuilder
	csp = |v| Attribute("csp", v)

	data : AttrBuilder
	data = |v| Attribute("data", v)

	data_attr : Str, Str -> Attribute
	data_attr = |data_name, data_val| Attribute("data-${data_name}", data_val)

	datetime : AttrBuilder
	datetime = |v| Attribute("datetime", v)

	decoding : AttrBuilder
	decoding = |v| Attribute("decoding", v)

	default : AttrBuilder
	default = |v| Attribute("default", v)

	defer : AttrBuilder
	defer = |v| Attribute("defer", v)

	dir : AttrBuilder
	dir = |v| Attribute("dir", v)

	dirname : AttrBuilder
	dirname = |v| Attribute("dirname", v)

	disabled : AttrBuilder
	disabled = |v| Attribute("disabled", v)

	download : AttrBuilder
	download = |v| Attribute("download", v)

	draggable : AttrBuilder
	draggable = |v| Attribute("draggable", v)

	enctype : AttrBuilder
	enctype = |v| Attribute("enctype", v)

	enterkeyhint : AttrBuilder
	enterkeyhint = |v| Attribute("enterkeyhint", v)

	for_ : AttrBuilder
	for_ = |v| Attribute("for", v)

	form : AttrBuilder
	form = |v| Attribute("form", v)

	formaction : AttrBuilder
	formaction = |v| Attribute("formaction", v)

	formenctype : AttrBuilder
	formenctype = |v| Attribute("formenctype", v)

	formmethod : AttrBuilder
	formmethod = |v| Attribute("formmethod", v)

	formnovalidate : AttrBuilder
	formnovalidate = |v| Attribute("formnovalidate", v)

	formtarget : AttrBuilder
	formtarget = |v| Attribute("formtarget", v)

	headers : AttrBuilder
	headers = |v| Attribute("headers", v)

	height : AttrBuilder
	height = |v| Attribute("height", v)

	hidden : AttrBuilder
	hidden = |v| Attribute("hidden", v)

	high : AttrBuilder
	high = |v| Attribute("high", v)

	href : AttrBuilder
	href = |v| Attribute("href", v)

	hreflang : AttrBuilder
	hreflang = |v| Attribute("hreflang", v)

	http_equiv : AttrBuilder
	http_equiv = |v| Attribute("http-equiv", v)

	icon : AttrBuilder
	icon = |v| Attribute("icon", v)

	id : AttrBuilder
	id = |v| Attribute("id", v)

	importance : AttrBuilder
	importance = |v| Attribute("importance", v)

	integrity : AttrBuilder
	integrity = |v| Attribute("integrity", v)

	intrinsicsize : AttrBuilder
	intrinsicsize = |v| Attribute("intrinsicsize", v)

	inputmode : AttrBuilder
	inputmode = |v| Attribute("inputmode", v)

	ismap : AttrBuilder
	ismap = |v| Attribute("ismap", v)

	itemprop : AttrBuilder
	itemprop = |v| Attribute("itemprop", v)

	keytype : AttrBuilder
	keytype = |v| Attribute("keytype", v)

	kind : AttrBuilder
	kind = |v| Attribute("kind", v)

	label : AttrBuilder
	label = |v| Attribute("label", v)

	lang : AttrBuilder
	lang = |v| Attribute("lang", v)

	language : AttrBuilder
	language = |v| Attribute("language", v)

	loading : AttrBuilder
	loading = |v| Attribute("loading", v)

	list : AttrBuilder
	list = |v| Attribute("list", v)

	loop : AttrBuilder
	loop = |v| Attribute("loop", v)

	low : AttrBuilder
	low = |v| Attribute("low", v)

	manifest : AttrBuilder
	manifest = |v| Attribute("manifest", v)

	max : AttrBuilder
	max = |v| Attribute("max", v)

	maxlength : AttrBuilder
	maxlength = |v| Attribute("maxlength", v)

	minlength : AttrBuilder
	minlength = |v| Attribute("minlength", v)

	media : AttrBuilder
	media = |v| Attribute("media", v)

	method : AttrBuilder
	method = |v| Attribute("method", v)

	min : AttrBuilder
	min = |v| Attribute("min", v)

	multiple : AttrBuilder
	multiple = |v| Attribute("multiple", v)

	muted : AttrBuilder
	muted = |v| Attribute("muted", v)

	name : AttrBuilder
	name = |v| Attribute("name", v)

	novalidate : AttrBuilder
	novalidate = |v| Attribute("novalidate", v)

	open : AttrBuilder
	open = |v| Attribute("open", v)

	optimum : AttrBuilder
	optimum = |v| Attribute("optimum", v)

	pattern : AttrBuilder
	pattern = |v| Attribute("pattern", v)

	ping : AttrBuilder
	ping = |v| Attribute("ping", v)

	placeholder : AttrBuilder
	placeholder = |v| Attribute("placeholder", v)

	poster : AttrBuilder
	poster = |v| Attribute("poster", v)

	preload : AttrBuilder
	preload = |v| Attribute("preload", v)

	radiogroup : AttrBuilder
	radiogroup = |v| Attribute("radiogroup", v)

	readonly : AttrBuilder
	readonly = |v| Attribute("readonly", v)

	referrerpolicy : AttrBuilder
	referrerpolicy = |v| Attribute("referrerpolicy", v)

	rel : AttrBuilder
	rel = |v| Attribute("rel", v)

	required : AttrBuilder
	required = |v| Attribute("required", v)

	reversed : AttrBuilder
	reversed = |v| Attribute("reversed", v)

	role : AttrBuilder
	role = |v| Attribute("role", v)

	rows : AttrBuilder
	rows = |v| Attribute("rows", v)

	rowspan : AttrBuilder
	rowspan = |v| Attribute("rowspan", v)

	sandbox : AttrBuilder
	sandbox = |v| Attribute("sandbox", v)

	scope : AttrBuilder
	scope = |v| Attribute("scope", v)

	scoped : AttrBuilder
	scoped = |v| Attribute("scoped", v)

	selected : AttrBuilder
	selected = |v| Attribute("selected", v)

	shape : AttrBuilder
	shape = |v| Attribute("shape", v)

	size : AttrBuilder
	size = |v| Attribute("size", v)

	sizes : AttrBuilder
	sizes = |v| Attribute("sizes", v)

	slot : AttrBuilder
	slot = |v| Attribute("slot", v)

	span : AttrBuilder
	span = |v| Attribute("span", v)

	spellcheck : AttrBuilder
	spellcheck = |v| Attribute("spellcheck", v)

	src : AttrBuilder
	src = |v| Attribute("src", v)

	srcdoc : AttrBuilder
	srcdoc = |v| Attribute("srcdoc", v)

	srclang : AttrBuilder
	srclang = |v| Attribute("srclang", v)

	srcset : AttrBuilder
	srcset = |v| Attribute("srcset", v)

	start : AttrBuilder
	start = |v| Attribute("start", v)

	step : AttrBuilder
	step = |v| Attribute("step", v)

	style : AttrBuilder
	style = |v| Attribute("style", v)

	summary : AttrBuilder
	summary = |v| Attribute("summary", v)

	tabindex : AttrBuilder
	tabindex = |v| Attribute("tabindex", v)

	target : AttrBuilder
	target = |v| Attribute("target", v)

	title : AttrBuilder
	title = |v| Attribute("title", v)

	translate : AttrBuilder
	translate = |v| Attribute("translate", v)

	type : AttrBuilder
	type = |v| Attribute("type", v)

	usemap : AttrBuilder
	usemap = |v| Attribute("usemap", v)

	value : AttrBuilder
	value = |v| Attribute("value", v)

	width : AttrBuilder
	width = |v| Attribute("width", v)

	wrap : AttrBuilder
	wrap = |v| Attribute("wrap", v)
}
