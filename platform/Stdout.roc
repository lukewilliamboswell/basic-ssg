import IOErr exposing [IOErr]
import Host

Stdout := [].{

	## Write the given string to standard output, followed by a newline.
	line! : Str => Try({}, [StdoutErr(IOErr), ..])
	line! = |str|
		match Host.stdout_line!(str) {
			Ok({}) => Ok({})
			Err(StdoutErr(err)) => Err(StdoutErr(err))
		}

	## Write the given string to standard output (no trailing newline).
	write! : Str => Try({}, [StdoutErr(IOErr), ..])
	write! = |str|
		match Host.stdout_write!(str) {
			Ok({}) => Ok({})
			Err(StdoutErr(err)) => Err(StdoutErr(err))
		}
}
