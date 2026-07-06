import Host

Locale := [].{

	## Returns the most preferred locale for the system or application, or
	## `Err(NotAvailable)` if the locale could not be obtained.
	##
	## The returned `Str` is a BCP 47 language tag, like `en-US` or `fr-CA`.
	get! : () => Try(Str, [NotAvailable, ..])
	get! = ||
		match Host.locale_get!() {
			Ok(locale) => Ok(locale)
			Err(NotAvailable) => Err(NotAvailable)
		}

	## Returns the preferred locales for the system or application.
	##
	## The returned `Str` values are BCP 47 language tags, like `en-US` or `fr-CA`.
	all! : () => List(Str)
	all! = || Host.locale_all!()
}
