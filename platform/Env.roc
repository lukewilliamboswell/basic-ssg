import Host

Env := [].{

	## The CPU architecture the platform was built for.
	Arch : [X86, X64, Arm, Aarch64, Other(Str)]

	## The operating system the platform was built for.
	Os : [Linux, Macos, Windows, Other(Str)]

	## Reads the given environment variable.
	##
	## If the value is invalid Unicode, the invalid parts will be replaced with the
	## [Unicode replacement character](https://unicode.org/glossary/#replacement_character).
	##
	## Returns `Err(VarNotFound(name))` if the variable is not set.
	var! : Str => Try(Str, [VarNotFound(Str), ..])
	var! = |name|
		match Host.env_var!(name) {
			Ok(value) => Ok(value)
			Err(VarNotFound(var_name)) => Err(VarNotFound(var_name))
		}

	## Reads all the process's environment variables into a `Dict`.
	##
	## If any key or value contains invalid Unicode, the
	## [Unicode replacement character](https://unicode.org/glossary/#replacement_character)
	## is used in place of the invalid parts.
	dict! : () => Dict(Str, Str)
	dict! = || Dict.from_list(Host.env_dict!())

	## Returns the current architecture and operating system.
	##
	## Note these values are constants from when the platform was built.
	platform! : () => { arch : Arch, os : Os }
	platform! = || {
		from_host = Host.env_arch_os!()

		arch = match from_host.arch {
			"x86" => X86
			"x86_64" => X64
			"arm" => Arm
			"aarch64" => Aarch64
			_ => Other(from_host.arch)
		}

		os = match from_host.os {
			"linux" => Linux
			"macos" => Macos
			"windows" => Windows
			_ => Other(from_host.os)
		}

		{ arch, os }
	}
}
