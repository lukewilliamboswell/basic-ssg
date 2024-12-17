module [
    var!,
    decode!,
    dict!,
    platform!,
]

import EnvDecoding
import Host

## Reads the given environment variable.
##
## If the value is invalid Unicode, the invalid parts will be replaced with the
## [Unicode replacement character](https://unicode.org/glossary/#replacement_character) ('�').
var! : Str => Result Str [VarNotFound]
var! = \name ->
    Host.env_var! name
    |> Result.mapErr \{} -> VarNotFound

## Reads the given environment variable and attempts to decode it.
##
## The type being decoded into will be determined by type inference. For example,
## if this ends up being used like a `Task U16 _` then the environment variable
## will be decoded as a string representation of a `U16`. Trying to decode into
## any other type will fail with a `DecodeErr`.
##
## Supported types include;
## - Strings,
## - Numbers, as long as they contain only numeric digits, up to one `.`, and an optional `-` at the front for negative numbers, and
## - Comma-separated lists (of either strings or numbers), as long as there are no spaces after the commas.
##
## For example, consider we want to decode the environment variable `NUM_THINGS`;
##
## ```
## # Reads "NUM_THINGS" and decodes into a U16
## getU16Var : Str -> Task U16 [VarNotFound, DecodeErr DecodeError] [Read [Env]]
## getU16Var = \var -> Env.decode! var
## ```
##
## If `NUM_THINGS=123` then `getU16Var` succeeds with the value of `123u16`.
## However if `NUM_THINGS=123456789`, then `getU16Var` will
## fail with [DecodeErr](https://www.roc-lang.org/builtins/Decode#DecodeError)
## because `123456789` is too large to fit in a [U16](https://www.roc-lang.org/builtins/Num#U16).
##
decode! : Str => Result val [VarNotFound, DecodeErr DecodeError] where val implements Decoding
decode! = \name ->
    when Host.env_var! name is
        Err {} -> Err VarNotFound
        Ok varStr ->
            Str.toUtf8 varStr
            |> Decode.fromBytes (EnvDecoding.format {})
            |> Result.mapErr (\_ -> DecodeErr TooShort)

## Reads all the process's environment variables into a [Dict].
##
## If any key or value contains invalid Unicode, the [Unicode replacement character](https://unicode.org/glossary/#replacement_character)
## will be used in place of any parts of keys or values that are invalid Unicode.
dict! : {} => Dict Str Str
dict! = \{} ->
    Host.env_dict! {}
    |> Dict.fromList

ARCH : [X86, X64, ARM, AARCH64, OTHER Str]
OS : [LINUX, MACOS, WINDOWS, OTHER Str]

## Returns the current Achitecture and Operating System.
##
## `ARCH : [X86, X64, ARM, AARCH64, OTHER Str]`
## `OS : [LINUX, MACOS, WINDOWS, OTHER Str]`
##
## Note these values are constants from when the platform is built.
##
platform! : {} => { arch : ARCH, os : OS }
platform! = \{} ->

    fromRust = Host.current_arch_os! {}

    arch =
        when fromRust.arch is
            "x86" -> X86
            "x86_64" -> X64
            "arm" -> ARM
            "aarch64" -> AARCH64
            _ -> OTHER fromRust.arch

    os =
        when fromRust.os is
            "linux" -> LINUX
            "macos" -> MACOS
            "windows" -> WINDOWS
            _ -> OTHER fromRust.os

    { arch, os }
