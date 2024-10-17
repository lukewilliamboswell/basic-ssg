app [main] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.15.0/SlwdbJ-3GR7uBWQo6zlmYWNYOxnvo8r6YABXD-45UOw.tar.br",
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
    cliParser =
        { Arg.Cli.combine <-
            release: Arg.Opt.flag { short: "r", long: "release", help: "DEBUG build native target only, or RELEASE build for all supported targets." },
            bundle: Arg.Opt.flag { short: "b", long: "bundle", help: "Bundle platform files into a package for distribution" },
            maybeRoc: Arg.Opt.maybeStr { short: "p", long: "roc", help: "Path to the roc executable. Can be just `roc` or a full path." },
        }
        |> Arg.Cli.finish {
            name: "basic-ssg-builder",
            version: "",
            authors: ["Luke Boswell <https://github.com/lukewilliamboswell>"],
            description: "Generates all files needed by Roc to use this basic-ssg platform.",
        }
        |> Arg.Cli.assertValid

    when Arg.Cli.parseOrDisplayMessage cliParser (Arg.list! {}) is
        Ok args -> run args
        Err errMsg -> Task.err (Exit 1 errMsg)

run : { release : Bool, bundle : Bool, maybeRoc : Result Str err } -> Task {} _
run = \{ release, bundle, maybeRoc } ->

    roc = maybeRoc |> Result.withDefault "roc"

    # target is MacosArm64, LinuxX64,...
    info! "Getting the native target ..."
    nativeTarget =
        Env.platform
            |> Task.await! getNativeTarget

    buildTasks =
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
                build nativeTarget DEBUG,
            ]

    _ = Task.sequence! buildTasks

    bundleTask =
        if bundle then
            info! "Bundling platform binaries ..."
            roc
                |> Cmd.exec ["build", "--bundle", ".tar.br", "platform/main.roc"]
                |> Task.mapErr! ErrBundlingPlatform
        else
            Task.ok {}

    bundleTask!

    info! "Successfully completed building platform binaries."

RocTarget : [
    MacosArm64,
    MacosX64,
    LinuxArm64,
    LinuxX64,
    WindowsArm64,
    WindowsX64,
]

rocTarget : RocTarget -> Str
rocTarget = \target ->
    when target is
        MacosArm64 -> "macos-arm64"
        MacosX64 -> "macos-x64"
        LinuxArm64 -> "linux-arm64"
        LinuxX64 -> "linux-x64"
        WindowsArm64 -> "windows-arm64"
        WindowsX64 -> "windows-x64"

fromLibPath : RocTarget -> Str
fromLibPath = \target ->
    when target is
        MacosArm64 | MacosX64 | LinuxArm64 | LinuxX64 -> "libhost.a"
        WindowsArm64 | WindowsX64 -> "host.lib"

toLibPath : RocTarget -> Str
toLibPath = \target ->
    when target is
        MacosArm64 | MacosX64 | LinuxArm64 | LinuxX64 -> "$(rocTarget target).a"
        WindowsArm64 | WindowsX64 -> "$(rocTarget target).lib"

rustcTarget : RocTarget -> Str
rustcTarget = \target ->
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

getNativeTarget : _ -> Task RocTarget _
getNativeTarget = \{ os, arch } ->
    when (os, arch) is
        (MACOS, AARCH64) -> Task.ok MacosArm64
        (MACOS, X64) -> Task.ok MacosX64
        (LINUX, AARCH64) -> Task.ok LinuxArm64
        (LINUX, X64) -> Task.ok LinuxX64
        _ -> Task.err (UnsupportedNative os arch)

build : RocTarget, [DEBUG, RELEASE] -> Task {} _
build = \target, releaseMode ->

    targetStr = rustcTarget target

    (releaseModeStr, cargoBuildArgs) =
        when releaseMode is
            RELEASE -> ("release", ["build", "--release", "--target=$(targetStr)"])
            DEBUG -> ("debug", ["build", "--target=$(targetStr)"])

    info! "Building legacy binary for $(targetStr) ..."

    "cargo"
        |> Cmd.exec cargoBuildArgs
        |> Task.mapErr! \err -> ErrBuildingLegacyBinary targetStr err

    from = "target/$(targetStr)/$(releaseModeStr)/$(fromLibPath target)"
    to = "platform/$(toLibPath target)"

    info! "Moving legacy binary from $(from) to $(to) ..."

    "cp"
        |> Cmd.exec [from, to]
        |> Task.mapErr! \err -> ErrMovingLegacyBinary targetStr err
