//! Roc platform host implementation for basic-ssg, using Roc's direct-symbol
//! host ABI. All Roc data types come from the generated `roc_platform_abi.rs`.

#![allow(improper_ctypes_definitions)]

use core::mem::ManuallyDrop;
use std::ffi::{c_char, c_void, CStr};
use std::io::{self, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};

mod roc_platform_abi;
mod roc_syntax;
mod ssg;

use crate::roc_platform_abi::*;

// RustGlue assigns numbered names (TryTypeN, IOErrTypeN, ...) to anonymous Roc
// records and result types, and the numbers shift whenever a module is added. To
// stay robust against that renumbering we alias against the *semantic* names the
// generator also emits (keyed by module + function name).
type StderrUnitResult = StderrLineResult;
type StderrUnitResultPayload = StderrLineResultPayload;
type StderrUnitResultTag = StderrLineResultTag;
type StderrBytesResult = StderrWriteBytesResult;
type StderrBytesResultPayload = StderrWriteBytesResultPayload;
type StderrBytesResultTag = StderrWriteBytesResultTag;

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
// IOErr conversion (shared by the stdio effects)
// ============================================================================

macro_rules! define_common_io_err {
    ($from_io:ident, $other:ident, $ty:ident, $tag:ident, $payload:ident) => {
        fn $other(message: &str, roc_host: &RocHost) -> $ty {
            $ty {
                payload: $payload {
                    other: ManuallyDrop::new(RocStr::from_str(message, roc_host)),
                },
                tag: $tag::Other,
            }
        }

        #[allow(dead_code)]
        fn $from_io(error: &io::Error, roc_host: &RocHost) -> $ty {
            match error.kind() {
                io::ErrorKind::AlreadyExists => $ty {
                    payload: $payload { already_exists: [] },
                    tag: $tag::AlreadyExists,
                },
                io::ErrorKind::BrokenPipe => $ty {
                    payload: $payload { broken_pipe: [] },
                    tag: $tag::BrokenPipe,
                },
                io::ErrorKind::Interrupted => $ty {
                    payload: $payload { interrupted: [] },
                    tag: $tag::Interrupted,
                },
                io::ErrorKind::NotFound => $ty {
                    payload: $payload { not_found: [] },
                    tag: $tag::NotFound,
                },
                io::ErrorKind::OutOfMemory => $ty {
                    payload: $payload { out_of_memory: [] },
                    tag: $tag::OutOfMemory,
                },
                io::ErrorKind::PermissionDenied => $ty {
                    payload: $payload {
                        permission_denied: [],
                    },
                    tag: $tag::PermissionDenied,
                },
                io::ErrorKind::Unsupported => $ty {
                    payload: $payload { unsupported: [] },
                    tag: $tag::Unsupported,
                },
                _ => $other(&error.to_string(), roc_host),
            }
        }
    };
}

define_common_io_err!(
    stderr_io_err_from_io,
    stderr_io_err_other,
    StderrIOErr,
    StderrIOErrTag,
    StderrIOErrPayload
);

// ============================================================================
// Stderr effects
// ============================================================================

fn try_stderr_unit_ok() -> StderrUnitResult {
    StderrUnitResult {
        payload: StderrUnitResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: StderrUnitResultTag::Ok,
    }
}

fn try_stderr_unit_err(error: StderrIOErr) -> StderrUnitResult {
    StderrUnitResult {
        payload: StderrUnitResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: StderrUnitResultTag::Err,
    }
}

fn try_stderr_bytes_ok() -> StderrBytesResult {
    StderrBytesResult {
        payload: StderrBytesResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: StderrBytesResultTag::Ok,
    }
}

fn try_stderr_bytes_err(error: StderrIOErr) -> StderrBytesResult {
    StderrBytesResult {
        payload: StderrBytesResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: StderrBytesResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_stderr_line(message: RocStr) -> StderrUnitResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        writeln!(stderr, "{}", message.as_str())
    };
    message.decref(roc_host);

    match result {
        Ok(()) => try_stderr_unit_ok(),
        Err(error) => try_stderr_unit_err(stderr_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stderr_write(message: RocStr) -> StderrUnitResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        write!(stderr, "{}", message.as_str()).and_then(|()| stderr.flush())
    };
    message.decref(roc_host);

    match result {
        Ok(()) => try_stderr_unit_ok(),
        Err(error) => try_stderr_unit_err(stderr_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stderr_write_bytes(bytes: RocListWith<u8, false>) -> StderrBytesResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        stderr
            .write_all(bytes.as_slice())
            .and_then(|()| stderr.flush())
    };
    bytes.decref(roc_host);

    match result {
        Ok(()) => try_stderr_bytes_ok(),
        Err(error) => try_stderr_bytes_err(stderr_io_err_from_io(&error, roc_host)),
    }
}

// ============================================================================
// SSG effects
//
// All three return plain `Str` errors (no IOErr). The generated result types are
// `SSGHost<Fn>Result` with a `{ payload, tag }` shape; `find_files` returns a
// `RocList` of the generated `AnonStruct3` record `{ path, relpath, url }`.
// ============================================================================

type FindFilesResult = SSGHostFindFilesResult;
type FindFilesResultPayload = SSGHostFindFilesResultPayload;
type FindFilesResultTag = SSGHostFindFilesResultTag;
type FilesRecord = SSGHostFindFilesOk;
type ParseMarkdownResult = SSGHostParseMarkdownResult;
type ParseMarkdownResultPayload = SSGHostParseMarkdownResultPayload;
type ParseMarkdownResultTag = SSGHostParseMarkdownResultTag;
type WriteFileResult = SSGHostWriteFileResult;
type WriteFileResultPayload = SSGHostWriteFileResultPayload;
type WriteFileResultTag = SSGHostWriteFileResultTag;

fn try_find_files_ok(list: RocList<FilesRecord>) -> FindFilesResult {
    FindFilesResult {
        payload: FindFilesResultPayload {
            ok: ManuallyDrop::new(list),
        },
        tag: FindFilesResultTag::Ok,
    }
}

fn try_find_files_err(message: RocStr) -> FindFilesResult {
    FindFilesResult {
        payload: FindFilesResultPayload {
            err: ManuallyDrop::new(message),
        },
        tag: FindFilesResultTag::Err,
    }
}

fn try_parse_markdown_ok(html: RocStr) -> ParseMarkdownResult {
    ParseMarkdownResult {
        payload: ParseMarkdownResultPayload {
            ok: ManuallyDrop::new(html),
        },
        tag: ParseMarkdownResultTag::Ok,
    }
}

fn try_parse_markdown_err(message: RocStr) -> ParseMarkdownResult {
    ParseMarkdownResult {
        payload: ParseMarkdownResultPayload {
            err: ManuallyDrop::new(message),
        },
        tag: ParseMarkdownResultTag::Err,
    }
}

fn try_write_file_ok() -> WriteFileResult {
    WriteFileResult {
        payload: WriteFileResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: WriteFileResultTag::Ok,
    }
}

fn try_write_file_err(message: RocStr) -> WriteFileResult {
    WriteFileResult {
        payload: WriteFileResultPayload {
            err: ManuallyDrop::new(message),
        },
        tag: WriteFileResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_ssg_find_files(dir: RocStr) -> FindFilesResult {
    let roc_host = roc_host();
    let dir_path = PathBuf::from(dir.as_str());
    dir.decref(roc_host);

    match ssg::find_files(&dir_path) {
        Ok(found) => {
            if found.is_empty() {
                return try_find_files_ok(RocList::empty());
            }
            let list = RocList::<FilesRecord>::allocate(found.len(), roc_host);
            for (index, file) in found.iter().enumerate() {
                unsafe {
                    list.elements.add(index).write(FilesRecord {
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
pub extern "C" fn hosted_ssg_parse_markdown(path: RocStr) -> ParseMarkdownResult {
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
) -> WriteFileResult {
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
