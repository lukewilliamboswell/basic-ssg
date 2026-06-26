import IOErr exposing [IOErr]

Stdout := [].{
    # Host functions use a `Str` error at the boundary. A `Try(_, IOErr)` hosted
    # result currently compiles to a 40-byte struct the compiler misreads (see
    # the migration notes / upstream issue); `Try(_, Str)` (32-byte) is read
    # correctly. The wrappers below rebuild the structured error in Roc.
    host_line! : Str => Try({}, Str)
    host_write! : Str => Try({}, Str)

    ## Write the given string to standard output, followed by a newline.
    line! : Str => Try({}, [StdoutErr(IOErr), ..])
    line! = |str|
        match Stdout.host_line!(str) {
            Ok({}) => Ok({})
            Err(msg) => Err(StdoutErr(Other(msg)))
        }

    ## Write the given string to standard output (no trailing newline).
    write! : Str => Try({}, [StdoutErr(IOErr), ..])
    write! = |str|
        match Stdout.host_write!(str) {
            Ok({}) => Ok({})
            Err(msg) => Err(StdoutErr(Other(msg)))
        }
}
