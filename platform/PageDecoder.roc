## Compose pure or effectful decoders that derive typed data from a page source.
##
## A decoder receives the discovered page value together with its UTF-8 source.
## Record-builder syntax combines independent decoders into a decoder for a
## record: `{ page: PageDecoder.page!, data: ... }.PageDecoder`.
PageDecoder := [].{

	## The input shared by every decoder for a page.
	Input(page) : {
		page : page,
		source : Str,
	}

	## An effectful decoder that derives `value` from one page input.
	Decoder(page, value, err) : Input(page) => Try(value, err)

	## Decode the discovered page value.
	page! : Decoder(page, page, err)
	page! = |{ page, source: _ }| Ok(page)

	## Decode the unmodified UTF-8 source text.
	source! : Decoder(page, Str, err)
	source! = |{ page: _, source }| Ok(source)

	## Lift a pure source parser into a page decoder.
	from_source : (Str -> Try(value, err)) -> Decoder(page, value, err)
	from_source = |parse| |{ page: _, source }| parse(source)

	## Use a custom effectful decoder with access to both the page and its source.
	from_effect : (Input(page) => Try(value, err)) -> Decoder(page, value, err)
	from_effect = |decode!| |input| decode!(input)

	## Transform a decoded value.
	map : Decoder(page, a, err), (a -> b) -> Decoder(page, b, err)
	map = |decode!, transform| |input| decode!(input).map_ok(transform)

	## Combine two independent decoders. Decoders run from left to right, and the
	## second decoder is skipped if the first returns `Err`.
	##
	## This is the applicative operation used by Roc's record-builder syntax.
	map2 : Decoder(page, a, err), Decoder(page, b, err), (a, b -> c) -> Decoder(page, c, err)
	map2 = |decode_a!, decode_b!, combine| |input| {
		a = decode_a!(input)?
		b = decode_b!(input)?
		Ok(combine(a, b))
	}

	## Run a decoder with an already-loaded page input.
	run! : Decoder(page, value, err), Input(page) => Try(value, err)
	run! = |decode!, input| decode!(input)
}
