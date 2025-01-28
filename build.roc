app [main!] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.19.0/Hj-J_zxz7V9YurCSTFcFdu6cQJie4guzsPMUi5kBYUk.tar.br",
    weaver: "https://github.com/smores56/weaver/releases/download/0.6.0/4GmRnyE7EFjzv6dDpebJoWWwXV285OMt4ntHIc6qvmY.tar.br",
}

import cli.Cmd
import cli.Stdout
import cli.Env
import cli.Arg
import weaver.Cli
import weaver.Opt

## Builds the basic-ssg [platform](https://www.roc-lang.org/platforms).
##
## run with: roc ./build.roc --release
##
main! = |args|
    cli_parser =
        { Cli.weave <-
            release: Opt.flag({ short: "r", long: "release", help: "DEBUG build native target only, or RELEASE build for all supported targets." }),
            bundle: Opt.flag({ short: "b", long: "bundle", help: "Bundle platform files into a package for distribution" }),
            roc: Opt.str({ short: "p", long: "roc", help: "Path to the roc executable. Can be just `roc` or a full path.", default: Value("roc") }),
        }
        |> Cli.finish(
            {
                name: "basic-ssg-builder",
                version: "",
                authors: ["Luke Boswell <https://github.com/lukewilliamboswell>"],
                description: "Generates all files needed by Roc to use this basic-ssg platform.",
            },
        )
        |> Cli.assert_valid

    { release, bundle, roc } =
        Cli.parse_or_display_message(cli_parser, args, Arg.to_os_raw) ? |message| Err(Exit(1, message))

    # target is MacosArm64, LinuxX64,...
    info!("Getting the native target ...")?

    native_target = get_native_target!(Env.platform!({}))?

    targets_to_build =
        if release then
            [
                (MacosArm64, RELEASE),
                (MacosX64, RELEASE),
                (LinuxArm64, RELEASE),
                (LinuxX64, RELEASE),
                (WindowsArm64, RELEASE),
                (WindowsX64, RELEASE),
            ]
        else
            [
                (native_target, DEBUG),
            ]

    List.for_each_try!(
        targets_to_build,
        |(target, opt_level)|
            build!(target, opt_level),
    )?

    if bundle then
        info!("Bundling platform binaries ...")?
        Cmd.exec!(roc, ["build", "--bundle", ".tar.br", "platform/main.roc"]) ? ErrBundlingPlatform
        {}
    else
        {}

    info!("Successfully completed building platform binaries.")

RocTarget : [
    MacosArm64,
    MacosX64,
    LinuxArm64,
    LinuxX64,
    WindowsArm64,
    WindowsX64,
]

roc_target : RocTarget -> Str
roc_target = |target|
    when target is
        MacosArm64 -> "macos-arm64"
        MacosX64 -> "macos-x64"
        LinuxArm64 -> "linux-arm64"
        LinuxX64 -> "linux-x64"
        WindowsArm64 -> "windows-arm64"
        WindowsX64 -> "windows-x64"

from_lib_path : RocTarget -> Str
from_lib_path = |target|
    when target is
        MacosArm64 | MacosX64 | LinuxArm64 | LinuxX64 -> "libhost.a"
        WindowsArm64 | WindowsX64 -> "host.lib"

to_lib_path : RocTarget -> Str
to_lib_path = |target|
    when target is
        MacosArm64 | MacosX64 | LinuxArm64 | LinuxX64 -> "${roc_target(target)}.a"
        WindowsArm64 | WindowsX64 -> "${roc_target(target)}.lib"

rustc_target : RocTarget -> Str
rustc_target = |target|
    when target is
        MacosArm64 -> "aarch64-apple-darwin"
        MacosX64 -> "x86_64-apple-darwin"
        LinuxArm64 -> "aarch64-unknown-linux-gnu"
        LinuxX64 -> "x86_64-unknown-linux-gnu"
        WindowsArm64 -> "aarch64-pc-windows-msvc"
        WindowsX64 -> "x86_64-pc-windows-msvc"

info! : Str => Result {} _
info! = |msg|
    Stdout.line!("\u(001b)[34mINFO:\u(001b)[0m ${msg}")

get_native_target! : _ => Result _ _
get_native_target! = |{ os, arch }|
    when (os, arch) is
        (MACOS, AARCH64) -> Ok(MacosArm64)
        (MACOS, X64) -> Ok(MacosX64)
        (LINUX, AARCH64) -> Ok(LinuxArm64)
        (LINUX, X64) -> Ok(LinuxX64)
        _ -> Err(UnsupportedNative(os, arch))

build! : RocTarget, [DEBUG, RELEASE] => Result {} _
build! = |target, release_mode|

    target_str = rustc_target(target)

    (release_mode_str, cargo_build_args) =
        when release_mode is
            RELEASE -> ("release", ["build", "--release", "--target=${target_str}"])
            DEBUG -> ("debug", ["build", "--target=${target_str}"])

    info!("Building legacy binary for ${target_str} ...")?

    Cmd.exec!("cargo", cargo_build_args) ? |err| ErrBuildingLegacyBinary(target_str, err)

    from = "target/${target_str}/${release_mode_str}/${from_lib_path(target)}"
    to = "platform/${to_lib_path(target)}"

    info!("Moving legacy binary from ${from} to ${to} ...")?

    Cmd.exec!("cp", [from, to]) ? |err| ErrMovingLegacyBinary(target_str, err)

    Ok({})
