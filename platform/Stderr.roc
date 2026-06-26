import IOErr exposing [IOErr]

Stderr := [].{
    # See Stdout.roc for why the host boundary uses a `Str` error.
    host_line! : Str => Try({}, Str)
    host_write! : Str => Try({}, Str)

    ## Write the given string to standard error, followed by a newline.
    line! : Str => Try({}, [StderrErr(IOErr), ..])
    line! = |str|
        match Stderr.host_line!(str) {
            Ok({}) => Ok({})
            Err(msg) => Err(StderrErr(Other(msg)))
        }

    ## Write the given string to standard error (no trailing newline).
    write! : Str => Try({}, [StderrErr(IOErr), ..])
    write! = |str|
        match Stderr.host_write!(str) {
            Ok({}) => Ok({})
            Err(msg) => Err(StderrErr(Other(msg)))
        }
}
