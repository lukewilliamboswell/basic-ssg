import IOErr exposing [IOErr]
import Host

Stderr := [].{

	## Write the given string to standard error, followed by a newline.
	line! : Str => Try({}, [StderrErr(IOErr), ..])
	line! = |str|
		match Host.stderr_line!(str) {
			Ok({}) => Ok({})
			Err(StderrErr(err)) => Err(StderrErr(err))
		}

	## Write the given string to standard error (no trailing newline).
	write! : Str => Try({}, [StderrErr(IOErr), ..])
	write! = |str|
		match Host.stderr_write!(str) {
			Ok({}) => Ok({})
			Err(StderrErr(err)) => Err(StderrErr(err))
		}
}
