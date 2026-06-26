//! Roc platform host implementation for basic-ssg, using Roc's direct-symbol
//! host ABI. All Roc data types come from the generated `roc_platform_abi.rs`.

#![allow(improper_ctypes_definitions)]

use core::mem::ManuallyDrop;
use std::ffi::{c_char, c_void, CStr};
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::Command as ProcessCommand;
use std::sync::atomic::{AtomicBool, Ordering};

mod roc_platform_abi;
mod roc_syntax;
mod ssg;

use crate::roc_platform_abi::*;

// RustGlue assigns numbered names (TryTypeN, IOErrTypeN, ...) to anonymous Roc
// records and result types, and the numbers shift whenever a module is added. To
// stay robust against that renumbering we alias against the *semantic* names the
// generator also emits (keyed by module + function name).
// NOTE on result types: `roc glue` emits a stable, semantic name for every
// hosted result type (e.g. `StdoutHostLineResult`, `SSGHostFindFilesResult`),
// keyed by module + function. We use those generated names directly below.
//
// Stdio/Cmd hosted fns use a `Str` error at the boundary: a `Try(_, IOErr)`
// hosted result compiles to a 40-byte struct the current compiler misreads,
// while `Try(_, Str)` (32-byte) is read correctly. The Roc wrappers rebuild the
// structured `IOErr` error from the message.

extern "C" {
    fn roc_main(args: RocList<RocStr>) -> i32;
}

static DEBUG_OR_EXPECT_CALLED: AtomicBool = AtomicBool::new(false);
static mut ROC_HOST: *mut RocHost = core::ptr::null_mut();

fn set_roc_host(roc_host: *mut RocHost) {
    unsafe {
        ROC_HOST = roc_host;
    }
}

fn roc_host_ptr() -> *mut RocHost {
    unsafe {
        if ROC_HOST.is_null() {
            eprintln!("roc host error: RocHost not initialized");
            std::process::exit(1);
        }
        ROC_HOST
    }
}

fn roc_host() -> &'static RocHost {
    unsafe { &*roc_host_ptr() }
}

// ============================================================================
// Stderr effects (Str error at the boundary)
// ============================================================================

fn try_stderr_unit_ok() -> StderrHostLineResult {
    StderrHostLineResult {
        payload: StderrHostLineResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: StderrHostLineResultTag::Ok,
    }
}

fn try_stderr_unit_err(message: RocStr) -> StderrHostLineResult {
    StderrHostLineResult {
        payload: StderrHostLineResultPayload {
            err: ManuallyDrop::new(message),
        },
        tag: StderrHostLineResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_stderr_line(message: RocStr) -> StderrHostLineResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        writeln!(stderr, "{}", message.as_str())
    };
    message.decref(roc_host);

    match result {
        Ok(()) => try_stderr_unit_ok(),
        Err(error) => try_stderr_unit_err(RocStr::from_str(&error.to_string(), roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stderr_write(message: RocStr) -> StderrHostLineResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        write!(stderr, "{}", message.as_str()).and_then(|()| stderr.flush())
    };
    message.decref(roc_host);

    match result {
        Ok(()) => try_stderr_unit_ok(),
        Err(error) => try_stderr_unit_err(RocStr::from_str(&error.to_string(), roc_host)),
    }
}

// ============================================================================
// SSG effects
//
// All three return plain `Str` errors (no IOErr). The generated result types are
// `SSGHost<Fn>Result` with a `{ payload, tag }` shape; `find_files` returns a
// `RocList` of the generated `AnonStruct3` record `{ path, relpath, url }`.
// ============================================================================

fn try_find_files_ok(list: RocList<SSGHostFindFilesOk>) -> SSGHostFindFilesResult {
    SSGHostFindFilesResult {
        payload: SSGHostFindFilesResultPayload {
            ok: ManuallyDrop::new(list),
        },
        tag: SSGHostFindFilesResultTag::Ok,
    }
}

fn try_find_files_err(message: RocStr) -> SSGHostFindFilesResult {
    SSGHostFindFilesResult {
        payload: SSGHostFindFilesResultPayload {
            err: ManuallyDrop::new(message),
        },
        tag: SSGHostFindFilesResultTag::Err,
    }
}

fn try_parse_markdown_ok(html: RocStr) -> SSGHostParseMarkdownResult {
    SSGHostParseMarkdownResult {
        payload: SSGHostParseMarkdownResultPayload {
            ok: ManuallyDrop::new(html),
        },
        tag: SSGHostParseMarkdownResultTag::Ok,
    }
}

fn try_parse_markdown_err(message: RocStr) -> SSGHostParseMarkdownResult {
    SSGHostParseMarkdownResult {
        payload: SSGHostParseMarkdownResultPayload {
            err: ManuallyDrop::new(message),
        },
        tag: SSGHostParseMarkdownResultTag::Err,
    }
}

fn try_write_file_ok() -> SSGHostWriteFileResult {
    SSGHostWriteFileResult {
        payload: SSGHostWriteFileResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: SSGHostWriteFileResultTag::Ok,
    }
}

fn try_write_file_err(message: RocStr) -> SSGHostWriteFileResult {
    SSGHostWriteFileResult {
        payload: SSGHostWriteFileResultPayload {
            err: ManuallyDrop::new(message),
        },
        tag: SSGHostWriteFileResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_ssg_find_files(dir: RocStr) -> SSGHostFindFilesResult {
    let roc_host = roc_host();
    let dir_path = PathBuf::from(dir.as_str());
    dir.decref(roc_host);

    match ssg::find_files(&dir_path) {
        Ok(found) => {
            if found.is_empty() {
                return try_find_files_ok(RocList::empty());
            }
            let list = RocList::<SSGHostFindFilesOk>::allocate(found.len(), roc_host);
            for (index, file) in found.iter().enumerate() {
                unsafe {
                    list.elements.add(index).write(SSGHostFindFilesOk {
                        path: RocStr::from_str(&file.path, roc_host),
                        relpath: RocStr::from_str(&file.relpath, roc_host),
                        url: RocStr::from_str(&file.url, roc_host),
                    });
                }
            }
            try_find_files_ok(list)
        }
        Err(message) => try_find_files_err(RocStr::from_str(&message, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_ssg_parse_markdown(path: RocStr) -> SSGHostParseMarkdownResult {
    let roc_host = roc_host();
    let input_path = PathBuf::from(path.as_str());
    path.decref(roc_host);

    match ssg::parse_markdown(&input_path) {
        Ok(html) => try_parse_markdown_ok(RocStr::from_str(&html, roc_host)),
        Err(message) => try_parse_markdown_err(RocStr::from_str(&message, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_ssg_write_file(
    output_dir: RocStr,
    relpath: RocStr,
    content: RocStr,
) -> SSGHostWriteFileResult {
    let roc_host = roc_host();
    let output_dir_path = PathBuf::from(output_dir.as_str());
    let rel_path = PathBuf::from(relpath.as_str());
    let result = ssg::write_file(&output_dir_path, &rel_path, content.as_str());
    output_dir.decref(roc_host);
    relpath.decref(roc_host);
    content.decref(roc_host);

    match result {
        Ok(()) => try_write_file_ok(),
        Err(message) => try_write_file_err(RocStr::from_str(&message, roc_host)),
    }
}

// ============================================================================
// Stdout effects
// ============================================================================

fn try_stdout_unit_ok() -> StdoutHostLineResult {
    StdoutHostLineResult {
        payload: StdoutHostLineResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: StdoutHostLineResultTag::Ok,
    }
}

fn try_stdout_unit_err(message: RocStr) -> StdoutHostLineResult {
    StdoutHostLineResult {
        payload: StdoutHostLineResultPayload {
            err: ManuallyDrop::new(message),
        },
        tag: StdoutHostLineResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_stdout_line(message: RocStr) -> StdoutHostLineResult {
    let roc_host = roc_host();
    let result = {
        let mut stdout = io::stdout().lock();
        writeln!(stdout, "{}", message.as_str())
    };
    message.decref(roc_host);

    match result {
        Ok(()) => try_stdout_unit_ok(),
        Err(error) => try_stdout_unit_err(RocStr::from_str(&error.to_string(), roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stdout_write(message: RocStr) -> StdoutHostLineResult {
    let roc_host = roc_host();
    let result = {
        let mut stdout = io::stdout().lock();
        write!(stdout, "{}", message.as_str()).and_then(|()| stdout.flush())
    };
    message.decref(roc_host);

    match result {
        Ok(()) => try_stdout_unit_ok(),
        Err(error) => try_stdout_unit_err(RocStr::from_str(&error.to_string(), roc_host)),
    }
}

// ============================================================================
// Cmd effects
// ============================================================================

fn try_cmd_status_ok(code: i32) -> CmdHostStatusResult {
    CmdHostStatusResult {
        payload: CmdHostStatusResultPayload {
            ok: ManuallyDrop::new(code),
        },
        tag: CmdHostStatusResultTag::Ok,
    }
}

fn try_cmd_status_err(message: RocStr) -> CmdHostStatusResult {
    CmdHostStatusResult {
        payload: CmdHostStatusResultPayload {
            err: ManuallyDrop::new(message),
        },
        tag: CmdHostStatusResultTag::Err,
    }
}

// Build a std::process::Command from the Roc `Command` record fields. `envs` is a
// flat list `[key0, value0, key1, value1, ...]`.
fn build_process_command(
    program: &RocStr,
    args: &RocList<RocStr>,
    envs: &RocList<RocStr>,
    clear_envs: bool,
) -> ProcessCommand {
    let mut command = ProcessCommand::new(program.as_str());
    for arg in args.as_slice() {
        command.arg(arg.as_str());
    }
    if clear_envs {
        command.env_clear();
    }
    let env_slice = envs.as_slice();
    let mut index = 0;
    while index + 1 < env_slice.len() {
        command.env(env_slice[index].as_str(), env_slice[index + 1].as_str());
        index += 2;
    }
    command
}

#[no_mangle]
pub extern "C" fn hosted_cmd_status(cmd: CmdHostStatusArgs) -> CmdHostStatusResult {
    let roc_host = roc_host();
    let mut command = build_process_command(&cmd.program, &cmd.args, &cmd.envs, cmd.clear_envs);
    let result = command.status();
    cmd.program.decref(roc_host);
    cmd.args.decref(roc_host);
    cmd.envs.decref(roc_host);

    match result {
        Ok(status) => try_cmd_status_ok(status.code().unwrap_or(-1)),
        Err(error) => try_cmd_status_err(RocStr::from_str(&error.to_string(), roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_cmd_output(cmd: CmdHostOutputArgs) -> CmdHostOutput {
    let roc_host = roc_host();
    let mut command = build_process_command(&cmd.program, &cmd.args, &cmd.envs, cmd.clear_envs);
    let result = command.output();
    cmd.program.decref(roc_host);
    cmd.args.decref(roc_host);
    cmd.envs.decref(roc_host);

    match result {
        Ok(output) => CmdHostOutput {
            stderr: RocListWith::<u8, false>::from_slice(&output.stderr, roc_host),
            stdout: RocListWith::<u8, false>::from_slice(&output.stdout, roc_host),
            exit_code: output.status.code().unwrap_or(-1),
        },
        Err(error) => CmdHostOutput {
            stderr: RocListWith::<u8, false>::from_slice(error.to_string().as_bytes(), roc_host),
            stdout: RocListWith::<u8, false>::from_slice(&[], roc_host),
            exit_code: -1,
        },
    }
}

// ============================================================================
// Env effects
// ============================================================================

#[no_mangle]
pub extern "C" fn hosted_env_var(name: RocStr) -> EnvVarResult {
    let roc_host = roc_host();
    let value = std::env::var_os(name.as_str());
    name.decref(roc_host);

    match value {
        Some(value) => EnvVarResult {
            payload: EnvVarResultPayload {
                ok: ManuallyDrop::new(RocStr::from_str(&value.to_string_lossy(), roc_host)),
            },
            tag: EnvVarResultTag::Ok,
        },
        None => EnvVarResult {
            payload: EnvVarResultPayload {
                err: ManuallyDrop::new(core::ptr::null_mut()),
            },
            tag: EnvVarResultTag::Err,
        },
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_dict() -> RocList<EnvHostDict> {
    let roc_host = roc_host();
    let vars: Vec<(String, String)> = std::env::vars_os()
        .map(|(k, v)| {
            (
                k.to_string_lossy().into_owned(),
                v.to_string_lossy().into_owned(),
            )
        })
        .collect();

    if vars.is_empty() {
        return RocList::empty();
    }
    let list = RocList::<EnvHostDict>::allocate(vars.len(), roc_host);
    for (index, (key, value)) in vars.iter().enumerate() {
        unsafe {
            list.elements.add(index).write(EnvHostDict {
                _0: RocStr::from_str(key, roc_host),
                _1: RocStr::from_str(value, roc_host),
            });
        }
    }
    list
}

#[no_mangle]
pub extern "C" fn hosted_env_arch_os() -> EnvHostArchOs {
    let roc_host = roc_host();
    EnvHostArchOs {
        arch: RocStr::from_str(std::env::consts::ARCH, roc_host),
        os: RocStr::from_str(std::env::consts::OS, roc_host),
    }
}

// ============================================================================
// Locale effects
//
// Determined from the standard locale environment variables (no extra crate),
// which works on Linux and macOS; returns a BCP-47-ish tag like `en-US`.
// ============================================================================

fn locale_first() -> Option<String> {
    for key in ["LC_ALL", "LC_MESSAGES", "LANG", "LANGUAGE"] {
        if let Some(value) = std::env::var_os(key) {
            let raw = value.to_string_lossy();
            let tag = raw.split('.').next().unwrap_or("").replace('_', "-");
            if !tag.is_empty() && tag != "C" && tag != "POSIX" {
                return Some(tag);
            }
        }
    }
    None
}

#[no_mangle]
pub extern "C" fn hosted_locale_get() -> LocaleGetResult {
    let roc_host = roc_host();
    match locale_first() {
        Some(tag) => LocaleGetResult {
            payload: LocaleGetResultPayload {
                ok: ManuallyDrop::new(RocStr::from_str(&tag, roc_host)),
            },
            tag: LocaleGetResultTag::Ok,
        },
        None => LocaleGetResult {
            payload: LocaleGetResultPayload {
                err: ManuallyDrop::new(core::ptr::null_mut()),
            },
            tag: LocaleGetResultTag::Err,
        },
    }
}

#[no_mangle]
pub extern "C" fn hosted_locale_all() -> RocList<RocStr> {
    let roc_host = roc_host();
    let all: Vec<String> = locale_first().into_iter().collect();
    if all.is_empty() {
        return RocList::empty();
    }
    let list = RocList::<RocStr>::allocate(all.len(), roc_host);
    for (index, tag) in all.iter().enumerate() {
        unsafe {
            list.elements
                .add(index)
                .write(RocStr::from_str(tag, roc_host));
        }
    }
    list
}

// ============================================================================
// Utc effects
// ============================================================================

#[no_mangle]
pub extern "C" fn hosted_utc_now() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0)
}

// ============================================================================
// Roc runtime symbols (allocator + handlers), entrypoint
// ============================================================================

#[no_mangle]
pub extern "C" fn roc_alloc(length: usize, alignment: usize) -> *mut c_void {
    DefaultAllocators::roc_alloc(roc_host_ptr(), length, alignment)
}

#[no_mangle]
pub extern "C" fn roc_dealloc(ptr: *mut c_void, alignment: usize) {
    DefaultAllocators::roc_dealloc(roc_host_ptr(), ptr, alignment);
}

#[no_mangle]
pub extern "C" fn roc_realloc(
    ptr: *mut c_void,
    new_length: usize,
    alignment: usize,
) -> *mut c_void {
    DefaultAllocators::roc_realloc(roc_host_ptr(), ptr, new_length, alignment)
}

#[no_mangle]
pub extern "C" fn roc_dbg(bytes: *const u8, len: usize) {
    DEBUG_OR_EXPECT_CALLED.store(true, Ordering::Release);
    DefaultHandlers::roc_dbg(roc_host_ptr(), bytes, len);
}

#[no_mangle]
pub extern "C" fn roc_expect_failed(bytes: *const u8, len: usize) {
    DEBUG_OR_EXPECT_CALLED.store(true, Ordering::Release);
    DefaultHandlers::roc_expect_failed(roc_host_ptr(), bytes, len);
}

#[no_mangle]
pub extern "C" fn roc_crashed(bytes: *const u8, len: usize) {
    DefaultHandlers::roc_crashed(roc_host_ptr(), bytes, len);
}

fn build_args_list(argc: i32, argv: *const *const c_char, roc_host: &RocHost) -> RocList<RocStr> {
    if argc <= 0 || argv.is_null() {
        return RocList::empty();
    }

    let list = RocList::<RocStr>::allocate(argc as usize, roc_host);
    for index in 0..argc as isize {
        unsafe {
            let arg_ptr = *argv.offset(index);
            if arg_ptr.is_null() {
                break;
            }
            let arg = CStr::from_ptr(arg_ptr).to_string_lossy();
            list.elements
                .offset(index)
                .write(RocStr::from_str(&arg, roc_host));
        }
    }
    list
}

#[cfg(not(test))]
#[no_mangle]
pub extern "C" fn main(argc: i32, argv: *const *const c_char) -> i32 {
    rust_main(argc, argv)
}

pub fn rust_main(argc: i32, argv: *const *const c_char) -> i32 {
    let mut roc_host = make_roc_host(core::ptr::null_mut());
    set_roc_host(&mut roc_host);

    let args_list = build_args_list(argc, argv, &roc_host);
    let mut exit_code = unsafe { roc_main(args_list) };

    if DEBUG_OR_EXPECT_CALLED.load(Ordering::Acquire) && exit_code == 0 {
        exit_code = 1;
    }

    set_roc_host(core::ptr::null_mut());
    exit_code
}

// Convert a RocStr path argument into a PathBuf, decref'ing the RocStr.
#[allow(dead_code)]
fn path_from_roc_str(path: RocStr, roc_host: &RocHost) -> PathBuf {
    let p = PathBuf::from(path.as_str());
    path.decref(roc_host);
    p
}
