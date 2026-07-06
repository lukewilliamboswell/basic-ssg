//! Roc platform host implementation for basic-ssg, using Roc's direct-symbol
//! host ABI. All Roc data types come from the generated `roc_platform_abi.rs`.

#![allow(improper_ctypes_definitions)]

use core::mem::ManuallyDrop;
use std::ffi::{c_char, c_void, CStr};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
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
// hosted result type (e.g. `HostStdoutLineResult`, `HostSsgFindPagesResult`),
// keyed by module + function. We use those generated names directly below.
//
// Public Roc modules wrap the closed host errors in open app-facing error rows.

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
// Host error helpers
// ============================================================================

fn io_err_other(message: String, roc_host: &RocHost) -> IOErr {
    IOErr {
        payload: IOErrPayload {
            other: ManuallyDrop::new(RocStr::from_str(&message, roc_host)),
        },
        tag: IOErrTag::Other,
    }
}

fn io_err_from_std(error: std::io::Error, roc_host: &RocHost) -> IOErr {
    match error.kind() {
        std::io::ErrorKind::NotFound => IOErr {
            payload: IOErrPayload { not_found: [] },
            tag: IOErrTag::NotFound,
        },
        std::io::ErrorKind::PermissionDenied => IOErr {
            payload: IOErrPayload {
                permission_denied: [],
            },
            tag: IOErrTag::PermissionDenied,
        },
        std::io::ErrorKind::BrokenPipe => IOErr {
            payload: IOErrPayload { broken_pipe: [] },
            tag: IOErrTag::BrokenPipe,
        },
        std::io::ErrorKind::AlreadyExists => IOErr {
            payload: IOErrPayload { already_exists: [] },
            tag: IOErrTag::AlreadyExists,
        },
        std::io::ErrorKind::Interrupted => IOErr {
            payload: IOErrPayload { interrupted: [] },
            tag: IOErrTag::Interrupted,
        },
        std::io::ErrorKind::Unsupported => IOErr {
            payload: IOErrPayload { unsupported: [] },
            tag: IOErrTag::Unsupported,
        },
        _ => io_err_other(error.to_string(), roc_host),
    }
}

// ============================================================================
// Stderr effects
// ============================================================================

fn try_stderr_unit_ok() -> HostStderrLineResult {
    HostStderrLineResult {
        payload: HostStderrLineResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: HostStderrLineResultTag::Ok,
    }
}

fn try_stderr_unit_err(error: IOErr) -> HostStderrLineResult {
    HostStderrLineResult {
        payload: HostStderrLineResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostStderrLineResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_stderr_line(message: RocStr) -> HostStderrLineResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        writeln!(stderr, "{}", message.as_str())
    };
    message.decref(roc_host);

    match result {
        Ok(()) => try_stderr_unit_ok(),
        Err(error) => try_stderr_unit_err(io_err_from_std(error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stderr_write(message: RocStr) -> HostStderrLineResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        write!(stderr, "{}", message.as_str()).and_then(|()| stderr.flush())
    };
    message.decref(roc_host);

    match result {
        Ok(()) => try_stderr_unit_ok(),
        Err(error) => try_stderr_unit_err(io_err_from_std(error, roc_host)),
    }
}

// ============================================================================
// SSG effects
//
// Public Roc APIs use `Path.Path`, but hosted functions receive `Path.Raw`
// (`UnixBytes(List(U8)) | WindowsU16s(List(U16))`) so the host can preserve OS
// path bytes at the boundary. Host SSG errors are closed tag unions; public SSG
// wrappers reopen them for app code.
// ============================================================================

fn try_find_pages_ok(list: RocList<HostSsgFindPagesOk>) -> HostSsgFindPagesResult {
    HostSsgFindPagesResult {
        payload: HostSsgFindPagesResultPayload {
            ok: ManuallyDrop::new(list),
        },
        tag: HostSsgFindPagesResultTag::Ok,
    }
}

fn try_find_pages_err(message: RocStr) -> HostSsgFindPagesResult {
    HostSsgFindPagesResult {
        payload: HostSsgFindPagesResultPayload {
            err: ManuallyDrop::new(message),
        },
        tag: HostSsgFindPagesResultTag::Err,
    }
}

fn try_parse_markdown_ok(html: RocStr) -> HostSsgParseMarkdownResult {
    HostSsgParseMarkdownResult {
        payload: HostSsgParseMarkdownResultPayload {
            ok: ManuallyDrop::new(html),
        },
        tag: HostSsgParseMarkdownResultTag::Ok,
    }
}

fn try_parse_markdown_err(message: RocStr) -> HostSsgParseMarkdownResult {
    HostSsgParseMarkdownResult {
        payload: HostSsgParseMarkdownResultPayload {
            err: ManuallyDrop::new(message),
        },
        tag: HostSsgParseMarkdownResultTag::Err,
    }
}

fn try_write_file_ok() -> HostSsgWriteFileResult {
    HostSsgWriteFileResult {
        payload: HostSsgWriteFileResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: HostSsgWriteFileResultTag::Ok,
    }
}

fn try_write_file_err(message: RocStr) -> HostSsgWriteFileResult {
    HostSsgWriteFileResult {
        payload: HostSsgWriteFileResultPayload {
            err: ManuallyDrop::new(message),
        },
        tag: HostSsgWriteFileResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_ssg_find_pages(dir: UnixBytesOrWindowsU16s) -> HostSsgFindPagesResult {
    let roc_host = roc_host();
    let dir_path = match pathbuf_from_roc_path(dir, roc_host) {
        Ok(path) => path,
        Err(message) => return try_find_pages_err(RocStr::from_str(&message, roc_host)),
    };

    match ssg::find_pages(&dir_path) {
        Ok(pages) => {
            if pages.is_empty() {
                return try_find_pages_ok(RocList::empty());
            }
            let list = RocList::<HostSsgFindPagesOk>::allocate(pages.len(), roc_host);
            for (index, page) in pages.iter().enumerate() {
                unsafe {
                    list.elements.add(index).write(HostSsgFindPagesOk {
                        output_path: roc_path_from_path(&page.output_path, roc_host),
                        source_path: roc_path_from_path(&page.source_path, roc_host),
                        url: RocStr::from_str(&page.url, roc_host),
                    });
                }
            }
            try_find_pages_ok(list)
        }
        Err(message) => try_find_pages_err(RocStr::from_str(&message, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_ssg_parse_markdown(
    path: UnixBytesOrWindowsU16s,
) -> HostSsgParseMarkdownResult {
    let roc_host = roc_host();
    let input_path = match pathbuf_from_roc_path(path, roc_host) {
        Ok(path) => path,
        Err(message) => return try_parse_markdown_err(RocStr::from_str(&message, roc_host)),
    };

    match ssg::parse_markdown(&input_path) {
        Ok(html) => try_parse_markdown_ok(RocStr::from_str(&html, roc_host)),
        Err(message) => try_parse_markdown_err(RocStr::from_str(&message, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_ssg_write_file(
    output_dir: UnixBytesOrWindowsU16s,
    output_path: UnixBytesOrWindowsU16s,
    content: RocStr,
) -> HostSsgWriteFileResult {
    let roc_host = roc_host();
    let output_dir_path = match pathbuf_from_roc_path(output_dir, roc_host) {
        Ok(path) => path,
        Err(message) => {
            decref_unix_bytes_or_windows_u16s(output_path, roc_host);
            content.decref(roc_host);
            return try_write_file_err(RocStr::from_str(&message, roc_host));
        }
    };
    let output_path = match pathbuf_from_roc_path(output_path, roc_host) {
        Ok(path) => path,
        Err(message) => {
            content.decref(roc_host);
            return try_write_file_err(RocStr::from_str(&message, roc_host));
        }
    };
    let result = ssg::write_file(&output_dir_path, &output_path, content.as_str());
    content.decref(roc_host);

    match result {
        Ok(()) => try_write_file_ok(),
        Err(message) => try_write_file_err(RocStr::from_str(&message, roc_host)),
    }
}

#[cfg(unix)]
fn pathbuf_from_roc_path(
    path: UnixBytesOrWindowsU16s,
    roc_host: &RocHost,
) -> Result<PathBuf, String> {
    use std::ffi::OsString;
    use std::os::unix::ffi::OsStringExt;

    match path.tag {
        UnixBytesOrWindowsU16sTag::UnixBytes => unsafe {
            let bytes = ManuallyDrop::into_inner(path.payload.unix_bytes);
            let path = PathBuf::from(OsString::from_vec(bytes.as_slice().to_vec()));
            bytes.decref(roc_host);
            Ok(path)
        },
        UnixBytesOrWindowsU16sTag::WindowsU16s => unsafe {
            let u16s = ManuallyDrop::into_inner(path.payload.windows_u16s);
            u16s.decref(roc_host);
            Err("expected UnixBytes path on this platform, got WindowsU16s".to_owned())
        },
    }
}

#[cfg(windows)]
fn pathbuf_from_roc_path(
    path: UnixBytesOrWindowsU16s,
    roc_host: &RocHost,
) -> Result<PathBuf, String> {
    use std::ffi::OsString;
    use std::os::windows::ffi::OsStringExt;

    match path.tag {
        UnixBytesOrWindowsU16sTag::UnixBytes => unsafe {
            let bytes = ManuallyDrop::into_inner(path.payload.unix_bytes);
            bytes.decref(roc_host);
            Err("expected WindowsU16s path on this platform, got UnixBytes".to_owned())
        },
        UnixBytesOrWindowsU16sTag::WindowsU16s => unsafe {
            let u16s = ManuallyDrop::into_inner(path.payload.windows_u16s);
            let path = PathBuf::from(OsString::from_wide(u16s.as_slice()));
            u16s.decref(roc_host);
            Ok(path)
        },
    }
}

#[cfg(not(any(unix, windows)))]
fn pathbuf_from_roc_path(
    path: UnixBytesOrWindowsU16s,
    roc_host: &RocHost,
) -> Result<PathBuf, String> {
    decref_unix_bytes_or_windows_u16s(path, roc_host);
    Err("filesystem paths are unsupported on this platform".to_owned())
}

#[cfg(unix)]
fn roc_path_from_path(path: &Path, roc_host: &RocHost) -> UnixBytesOrWindowsU16s {
    use std::os::unix::ffi::OsStrExt;

    UnixBytesOrWindowsU16s {
        payload: UnixBytesOrWindowsU16sPayload {
            unix_bytes: ManuallyDrop::new(RocListWith::<u8, false>::from_slice(
                path.as_os_str().as_bytes(),
                roc_host,
            )),
        },
        tag: UnixBytesOrWindowsU16sTag::UnixBytes,
    }
}

#[cfg(windows)]
fn roc_path_from_path(path: &Path, roc_host: &RocHost) -> UnixBytesOrWindowsU16s {
    use std::os::windows::ffi::OsStrExt;

    let units: Vec<u16> = path.as_os_str().encode_wide().collect();
    UnixBytesOrWindowsU16s {
        payload: UnixBytesOrWindowsU16sPayload {
            windows_u16s: ManuallyDrop::new(RocListWith::<u16, false>::from_slice(
                &units, roc_host,
            )),
        },
        tag: UnixBytesOrWindowsU16sTag::WindowsU16s,
    }
}

#[cfg(not(any(unix, windows)))]
fn roc_path_from_path(path: &Path, roc_host: &RocHost) -> UnixBytesOrWindowsU16s {
    UnixBytesOrWindowsU16s {
        payload: UnixBytesOrWindowsU16sPayload {
            unix_bytes: ManuallyDrop::new(RocListWith::<u8, false>::from_slice(
                path.to_string_lossy().as_bytes(),
                roc_host,
            )),
        },
        tag: UnixBytesOrWindowsU16sTag::UnixBytes,
    }
}

// ============================================================================
// Stdout effects
// ============================================================================

fn try_stdout_unit_ok() -> HostStdoutLineResult {
    HostStdoutLineResult {
        payload: HostStdoutLineResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: HostStdoutLineResultTag::Ok,
    }
}

fn try_stdout_unit_err(error: IOErr) -> HostStdoutLineResult {
    HostStdoutLineResult {
        payload: HostStdoutLineResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostStdoutLineResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_stdout_line(message: RocStr) -> HostStdoutLineResult {
    let roc_host = roc_host();
    let result = {
        let mut stdout = io::stdout().lock();
        writeln!(stdout, "{}", message.as_str())
    };
    message.decref(roc_host);

    match result {
        Ok(()) => try_stdout_unit_ok(),
        Err(error) => try_stdout_unit_err(io_err_from_std(error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stdout_write(message: RocStr) -> HostStdoutLineResult {
    let roc_host = roc_host();
    let result = {
        let mut stdout = io::stdout().lock();
        write!(stdout, "{}", message.as_str()).and_then(|()| stdout.flush())
    };
    message.decref(roc_host);

    match result {
        Ok(()) => try_stdout_unit_ok(),
        Err(error) => try_stdout_unit_err(io_err_from_std(error, roc_host)),
    }
}

// ============================================================================
// Cmd effects
// ============================================================================

fn try_cmd_status_ok(code: i32) -> HostCmdStatusResult {
    HostCmdStatusResult {
        payload: HostCmdStatusResultPayload {
            ok: ManuallyDrop::new(code),
        },
        tag: HostCmdStatusResultTag::Ok,
    }
}

fn try_cmd_status_err(error: IOErr) -> HostCmdStatusResult {
    HostCmdStatusResult {
        payload: HostCmdStatusResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostCmdStatusResultTag::Err,
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
pub extern "C" fn hosted_cmd_status(cmd: HostCmdStatusArgs) -> HostCmdStatusResult {
    let roc_host = roc_host();
    let mut command = build_process_command(&cmd.program, &cmd.args, &cmd.envs, cmd.clear_envs);
    let result = command.status();
    cmd.program.decref(roc_host);
    cmd.args.decref(roc_host);
    cmd.envs.decref(roc_host);

    match result {
        Ok(status) => try_cmd_status_ok(status.code().unwrap_or(-1)),
        Err(error) => try_cmd_status_err(io_err_from_std(error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_cmd_output(cmd: HostCmdOutputArgs) -> HostCmdOutput {
    let roc_host = roc_host();
    let mut command = build_process_command(&cmd.program, &cmd.args, &cmd.envs, cmd.clear_envs);
    let result = command.output();
    cmd.program.decref(roc_host);
    cmd.args.decref(roc_host);
    cmd.envs.decref(roc_host);

    match result {
        Ok(output) => HostCmdOutput {
            stderr: RocListWith::<u8, false>::from_slice(&output.stderr, roc_host),
            stdout: RocListWith::<u8, false>::from_slice(&output.stdout, roc_host),
            exit_code: output.status.code().unwrap_or(-1),
        },
        Err(error) => HostCmdOutput {
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
pub extern "C" fn hosted_env_var(name: RocStr) -> HostEnvVarResult {
    let roc_host = roc_host();
    let name_str = name.as_str().to_owned();
    let value = std::env::var_os(name.as_str());
    name.decref(roc_host);

    match value {
        Some(value) => HostEnvVarResult {
            payload: HostEnvVarResultPayload {
                ok: ManuallyDrop::new(RocStr::from_str(&value.to_string_lossy(), roc_host)),
            },
            tag: HostEnvVarResultTag::Ok,
        },
        None => HostEnvVarResult {
            payload: HostEnvVarResultPayload {
                err: ManuallyDrop::new(RocStr::from_str(&name_str, roc_host)),
            },
            tag: HostEnvVarResultTag::Err,
        },
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_dict() -> RocList<HostEnvDict> {
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
    let list = RocList::<HostEnvDict>::allocate(vars.len(), roc_host);
    for (index, (key, value)) in vars.iter().enumerate() {
        unsafe {
            list.elements.add(index).write(HostEnvDict {
                _0: RocStr::from_str(key, roc_host),
                _1: RocStr::from_str(value, roc_host),
            });
        }
    }
    list
}

#[no_mangle]
pub extern "C" fn hosted_env_arch_os() -> HostEnvArchOs {
    let roc_host = roc_host();
    HostEnvArchOs {
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
pub extern "C" fn hosted_locale_get() -> HostLocaleGetResult {
    let roc_host = roc_host();
    match locale_first() {
        Some(tag) => HostLocaleGetResult {
            payload: HostLocaleGetResultPayload {
                ok: ManuallyDrop::new(RocStr::from_str(&tag, roc_host)),
            },
            tag: HostLocaleGetResultTag::Ok,
        },
        None => HostLocaleGetResult {
            payload: HostLocaleGetResultPayload {
                err: ManuallyDrop::new(core::ptr::null_mut()),
            },
            tag: HostLocaleGetResultTag::Err,
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
