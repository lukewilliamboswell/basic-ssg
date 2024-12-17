app [main] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.17.0/lZFLstMUCUvd5bjnnpYromZJXkQUrdhbva4xdBInicE.tar.br",
}

import cli.Cmd
import cli.Stdout
import cli.Env
import cli.Arg
import cli.Arg.Opt
import cli.Arg.Cli

## Builds the basic-ssg [platform](https://www.roc-lang.org/platforms).
##
## run with: roc ./build.roc --release
##
main : Task {} _
main =
    cli_parser =
        { Arg.Cli.combine <-
            release: Arg.Opt.flag { short: "r", long: "release", help: "DEBUG build native target only, or RELEASE build for all supported targets." },
            bundle: Arg.Opt.flag { short: "b", long: "bundle", help: "Bundle platform files into a package for distribution" },
            maybe_roc: Arg.Opt.maybeStr { short: "p", long: "roc", help: "Path to the roc executable. Can be just `roc` or a full path." },
        }
        |> Arg.Cli.finish {
            name: "basic-ssg-builder",
            version: "",
            authors: ["Luke Boswell <https://github.com/lukewilliamboswell>"],
            description: "Generates all files needed by Roc to use this basic-ssg platform.",
        }
        |> Arg.Cli.assertValid

    when Arg.Cli.parseOrDisplayMessage cli_parser (Arg.list! {}) is
        Ok args -> run args
        Err err_msg -> Task.err (Exit 1 err_msg)

run : { release : Bool, bundle : Bool, maybe_roc : Result Str err } -> Task {} _
run = \{ release, bundle, maybe_roc } ->

    roc = maybe_roc |> Result.withDefault "roc"

    # target is MacosArm64, LinuxX64,...
    info! "Getting the native target ..."
    native_target =
        Env.platform
        |> Task.await! get_native_target

    build_tasks =
        if release then
            [
                build MacosArm64 RELEASE,
                build MacosX64 RELEASE,
                build LinuxArm64 RELEASE,
                build LinuxX64 RELEASE,
                build WindowsArm64 RELEASE,
                build WindowsX64 RELEASE,
            ]
        else
            [
                build native_target DEBUG,
            ]

    _ = Task.sequence! build_tasks

    bundle_task =
        if bundle then
            info! "Bundling platform binaries ..."
            roc
            |> Cmd.exec ["build", "--bundle", ".tar.br", "platform/main.roc"]
            |> Task.mapErr! ErrBundlingPlatform
        else
            Task.ok {}

    bundle_task!

    info! "Successfully completed building platform binaries."

RocTarget : [
    MacosArm64,
    MacosX64,
    LinuxArm64,
    LinuxX64,
    WindowsArm64,
    WindowsX64,
]

roc_target : RocTarget -> Str
roc_target = \target ->
    when target is
        MacosArm64 -> "macos-arm64"
        MacosX64 -> "macos-x64"
        LinuxArm64 -> "linux-arm64"
        LinuxX64 -> "linux-x64"
        WindowsArm64 -> "windows-arm64"
        WindowsX64 -> "windows-x64"

from_lib_path : RocTarget -> Str
from_lib_path = \target ->
    when target is
        MacosArm64 | MacosX64 | LinuxArm64 | LinuxX64 -> "libhost.a"
        WindowsArm64 | WindowsX64 -> "host.lib"

to_lib_path : RocTarget -> Str
to_lib_path = \target ->
    when target is
        MacosArm64 | MacosX64 | LinuxArm64 | LinuxX64 -> "$(roc_target target).a"
        WindowsArm64 | WindowsX64 -> "$(roc_target target).lib"

rustc_target : RocTarget -> Str
rustc_target = \target ->
    when target is
        MacosArm64 -> "aarch64-apple-darwin"
        MacosX64 -> "x86_64-apple-darwin"
        LinuxArm64 -> "aarch64-unknown-linux-gnu"
        LinuxX64 -> "x86_64-unknown-linux-gnu"
        WindowsArm64 -> "aarch64-pc-windows-msvc"
        WindowsX64 -> "x86_64-pc-windows-msvc"

info : Str -> Task {} _
info = \msg ->
    Stdout.line! "\u(001b)[34mINFO:\u(001b)[0m $(msg)"

get_native_target : _ -> Task RocTarget _
get_native_target = \{ os, arch } ->
    when (os, arch) is
        (MACOS, AARCH64) -> Task.ok MacosArm64
        (MACOS, X64) -> Task.ok MacosX64
        (LINUX, AARCH64) -> Task.ok LinuxArm64
        (LINUX, X64) -> Task.ok LinuxX64
        _ -> Task.err (UnsupportedNative os arch)

build : RocTarget, [DEBUG, RELEASE] -> Task {} _
build = \target, release_mode ->

    target_str = rustc_target target

    (release_mode_str, cargo_build_args) =
        when release_mode is
            RELEASE -> ("release", ["build", "--release", "--target=$(target_str)"])
            DEBUG -> ("debug", ["build", "--target=$(target_str)"])

    info! "Building legacy binary for $(target_str) ..."

    "cargo"
    |> Cmd.exec cargo_build_args
    |> Task.mapErr! \err -> ErrBuildingLegacyBinary target_str err

    from = "target/$(target_str)/$(release_mode_str)/$(from_lib_path target)"
    to = "platform/$(to_lib_path target)"

    info! "Moving legacy binary from $(from) to $(to) ..."

    "cp"
    |> Cmd.exec [from, to]
    |> Task.mapErr! \err -> ErrMovingLegacyBinary target_str err
