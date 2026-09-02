//! Roc platform host implementation for basic-ssg, using Roc's direct-symbol
//! host ABI. All Roc data types come from the generated `roc_platform_abi.rs`.

#![allow(improper_ctypes_definitions)]

use core::mem::ManuallyDrop;
#[cfg(unix)]
use std::ffi::CStr;
use std::ffi::{c_char, c_void};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::Command as ProcessCommand;
use std::sync::atomic::{AtomicBool, AtomicPtr, Ordering};

mod asciidoc;
mod roc_platform_abi;
mod roc_syntax;
mod ssg;

use crate::roc_platform_abi::*;

// Use only the generated semantic type names at this boundary. Public Roc
// modules wrap the closed host errors in open app-facing error rows.

extern "C" {
    fn roc_main(args: RocList<OsStr>) -> i32;
}

static DEBUG_OR_EXPECT_CALLED: AtomicBool = AtomicBool::new(false);
static ROC_HOST: AtomicPtr<RocHost> = AtomicPtr::new(core::ptr::null_mut());

fn set_roc_host(roc_host: *mut RocHost) {
    ROC_HOST.store(roc_host, Ordering::Release);
}

fn roc_host_ptr() -> *mut RocHost {
    let roc_host = ROC_HOST.load(Ordering::Acquire);
    if roc_host.is_null() {
        eprintln!("roc host error: RocHost not initialized");
        std::process::exit(1);
    }
    roc_host
}

fn roc_host() -> &'static RocHost {
    unsafe { &*roc_host_ptr() }
}

// ============================================================================
// Host error helpers
// ============================================================================

fn io_err_other(message: String, roc_host: &RocHost) -> HostIOErr {
    HostIOErr {
        payload: HostIOErrPayload {
            other: ManuallyDrop::new(RocStr::from_str(&message, roc_host)),
        },
        tag: HostIOErrTag::Other,
    }
}

fn io_err_from_std(error: std::io::Error, roc_host: &RocHost) -> HostIOErr {
    match error.kind() {
        std::io::ErrorKind::NotFound => HostIOErr {
            payload: HostIOErrPayload { not_found: [] },
            tag: HostIOErrTag::NotFound,
        },
        std::io::ErrorKind::PermissionDenied => HostIOErr {
            payload: HostIOErrPayload {
                permission_denied: [],
            },
            tag: HostIOErrTag::PermissionDenied,
        },
        std::io::ErrorKind::BrokenPipe => HostIOErr {
            payload: HostIOErrPayload { broken_pipe: [] },
            tag: HostIOErrTag::BrokenPipe,
        },
        std::io::ErrorKind::AlreadyExists => HostIOErr {
            payload: HostIOErrPayload { already_exists: [] },
            tag: HostIOErrTag::AlreadyExists,
        },
        std::io::ErrorKind::Interrupted => HostIOErr {
            payload: HostIOErrPayload { interrupted: [] },
            tag: HostIOErrTag::Interrupted,
        },
        std::io::ErrorKind::Unsupported => HostIOErr {
            payload: HostIOErrPayload { unsupported: [] },
            tag: HostIOErrTag::Unsupported,
        },
        _ => io_err_other(error.to_string(), roc_host),
    }
}

fn public_io_err_other(message: String, roc_host: &RocHost) -> IOErr {
    IOErr {
        payload: IOErrPayload {
            other: ManuallyDrop::new(RocStr::from_str(&message, roc_host)),
        },
        tag: IOErrTag::Other,
    }
}

fn public_io_err_from_std(error: std::io::Error, roc_host: &RocHost) -> IOErr {
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
        _ => public_io_err_other(error.to_string(), roc_host),
    }
}

// ============================================================================
// Stderr effects
// ============================================================================

fn try_stderr_unit_ok() -> HostStderrLineResult {
    HostStderrLineResult {
        payload: HostStderrLineResultPayload { ok: [] },
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
    unsafe {
        message.decref(roc_host);
    }

    match result {
        Ok(()) => try_stderr_unit_ok(),
        Err(error) => try_stderr_unit_err(public_io_err_from_std(error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stderr_write(message: RocStr) -> HostStderrLineResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        write!(stderr, "{}", message.as_str()).and_then(|()| stderr.flush())
    };
    unsafe {
        message.decref(roc_host);
    }

    match result {
        Ok(()) => try_stderr_unit_ok(),
        Err(error) => try_stderr_unit_err(public_io_err_from_std(error, roc_host)),
    }
}

// ============================================================================
// SSG effects
//
// Public Roc APIs use `Path.Path`, but hosted functions receive `Path.Raw`
// (`Utf8(Str) | UnixBytes(List(U8)) | WindowsU16s(List(U16))`) so portable text
// and native path units are preserved at the boundary. Host SSG errors are
// closed tag unions; public SSG wrappers reopen them for app code.
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

fn try_render_markdown_ok(html: RocStr) -> HostSsgRenderMarkdownResult {
    HostSsgRenderMarkdownResult {
        payload: HostSsgRenderMarkdownResultPayload {
            ok: ManuallyDrop::new(html),
        },
        tag: HostSsgRenderMarkdownResultTag::Ok,
    }
}

fn try_render_markdown_err(message: RocStr) -> HostSsgRenderMarkdownResult {
    HostSsgRenderMarkdownResult {
        payload: HostSsgRenderMarkdownResultPayload {
            err: ManuallyDrop::new(message),
        },
        tag: HostSsgRenderMarkdownResultTag::Err,
    }
}

fn try_parse_asciidoc_ok(document: HostSsgParseAsciidocOk) -> HostSsgParseAsciidocResult {
    HostSsgParseAsciidocResult {
        payload: HostSsgParseAsciidocResultPayload {
            ok: ManuallyDrop::new(document),
        },
        tag: HostSsgParseAsciidocResultTag::Ok,
    }
}

fn try_parse_asciidoc_err(message: RocStr) -> HostSsgParseAsciidocResult {
    HostSsgParseAsciidocResult {
        payload: HostSsgParseAsciidocResultPayload {
            err: ManuallyDrop::new(message),
        },
        tag: HostSsgParseAsciidocResultTag::Err,
    }
}

fn roc_strings(values: &[String], roc_host: &RocHost) -> RocList<RocStr> {
    if values.is_empty() {
        return RocList::empty();
    }
    let list = unsafe { RocList::<RocStr>::allocate(values.len(), roc_host) };
    for (index, value) in values.iter().enumerate() {
        unsafe {
            list.elements
                .add(index)
                .write(RocStr::from_str(value, roc_host));
        }
    }
    list
}

fn roc_raw_inline(value: &str, roc_host: &RocHost) -> AsciiDocInline {
    AsciiDocInline {
        payload: AsciiDocInlinePayload {
            raw_html: ManuallyDrop::new(RocStr::from_str(value, roc_host)),
        },
        tag: AsciiDocInlineTag::RawHtml,
    }
}

fn roc_asciidoc_document(
    document: asciidoc::Document,
    roc_host: &RocHost,
) -> HostSsgParseAsciidocOk {
    let blocks = if document.blocks.is_empty() {
        RocList::empty()
    } else {
        let list = unsafe {
            RocList::<HostSsgParseAsciidocOkBlocks>::allocate(document.blocks.len(), roc_host)
        };
        for (index, block) in document.blocks.iter().enumerate() {
            let inlines = match &block.inline_html {
                Some(html) => unsafe {
                    RocList::<AsciiDocInline>::from_slice(
                        &[roc_raw_inline(html, roc_host)],
                        roc_host,
                    )
                },
                None => RocList::empty(),
            };
            unsafe {
                list.elements
                    .add(index)
                    .write(HostSsgParseAsciidocOkBlocks {
                        level: block.level,
                        html: RocStr::from_str(&block.html, roc_host),
                        id: RocStr::from_str(&block.id, roc_host),
                        inlines,
                        kind: RocStr::from_str(&block.kind, roc_host),
                        roles: roc_strings(&block.roles, roc_host),
                        source: RocStr::from_str(&block.source, roc_host),
                        title: RocStr::from_str(&block.title, roc_host),
                    });
            }
        }
        list
    };
    let warnings = if document.warnings.is_empty() {
        RocList::empty()
    } else {
        let list = unsafe {
            RocList::<HostSsgParseAsciidocOkWarnings>::allocate(document.warnings.len(), roc_host)
        };
        for (index, warning) in document.warnings.iter().enumerate() {
            unsafe {
                list.elements
                    .add(index)
                    .write(HostSsgParseAsciidocOkWarnings {
                        column: warning.column,
                        line: warning.line,
                        message: RocStr::from_str(&warning.message, roc_host),
                    });
            }
        }
        list
    };
    HostSsgParseAsciidocOk {
        blocks,
        id: RocStr::from_str(&document.id, roc_host),
        roles: roc_strings(&document.roles, roc_host),
        title: RocStr::from_str(&document.title, roc_host),
        warnings,
    }
}

fn try_read_source_ok(source: RocStr) -> HostSsgReadSourceResult {
    HostSsgReadSourceResult {
        payload: HostSsgReadSourceResultPayload {
            ok: ManuallyDrop::new(source),
        },
        tag: HostSsgReadSourceResultTag::Ok,
    }
}

fn try_read_source_err(message: RocStr) -> HostSsgReadSourceResult {
    HostSsgReadSourceResult {
        payload: HostSsgReadSourceResultPayload {
            err: ManuallyDrop::new(message),
        },
        tag: HostSsgReadSourceResultTag::Err,
    }
}

fn try_write_file_ok() -> HostSsgWriteFileResult {
    HostSsgWriteFileResult {
        payload: HostSsgWriteFileResultPayload { ok: [] },
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
pub extern "C" fn hosted_ssg_find_pages(
    dir: UnixBytesOrUtf8OrWindowsU16s,
    source_extension: RocStr,
) -> HostSsgFindPagesResult {
    let roc_host = roc_host();
    let dir_path = match pathbuf_from_roc_path(dir, roc_host) {
        Ok(path) => path,
        Err(message) => {
            unsafe {
                source_extension.decref(roc_host);
            }
            return try_find_pages_err(RocStr::from_str(&message, roc_host));
        }
    };
    let source_extension_text = source_extension.as_str().to_owned();
    unsafe {
        source_extension.decref(roc_host);
    }

    match ssg::find_pages(&dir_path, &source_extension_text) {
        Ok(pages) => {
            if pages.is_empty() {
                return try_find_pages_ok(RocList::empty());
            }
            let list = unsafe { RocList::<HostSsgFindPagesOk>::allocate(pages.len(), roc_host) };
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
pub extern "C" fn hosted_ssg_read_source(
    path: UnixBytesOrUtf8OrWindowsU16s,
) -> HostSsgReadSourceResult {
    let roc_host = roc_host();
    let input_path = match pathbuf_from_roc_path(path, roc_host) {
        Ok(path) => path,
        Err(message) => return try_read_source_err(RocStr::from_str(&message, roc_host)),
    };

    match ssg::read_source(&input_path) {
        Ok(source) => try_read_source_ok(RocStr::from_str(&source, roc_host)),
        Err(message) => try_read_source_err(RocStr::from_str(&message, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_ssg_parse_markdown(
    path: UnixBytesOrUtf8OrWindowsU16s,
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
pub extern "C" fn hosted_ssg_render_markdown(
    source_path: UnixBytesOrUtf8OrWindowsU16s,
    markdown: RocStr,
) -> HostSsgRenderMarkdownResult {
    let roc_host = roc_host();
    let source_path = match pathbuf_from_roc_path(source_path, roc_host) {
        Ok(path) => path,
        Err(message) => {
            unsafe {
                markdown.decref(roc_host);
            }
            return try_render_markdown_err(RocStr::from_str(&message, roc_host));
        }
    };

    let result = ssg::render_markdown(markdown.as_str(), &source_path);
    unsafe {
        markdown.decref(roc_host);
    }

    match result {
        Ok(html) => try_render_markdown_ok(RocStr::from_str(&html, roc_host)),
        Err(message) => try_render_markdown_err(RocStr::from_str(&message, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_ssg_parse_asciidoc(
    path: UnixBytesOrUtf8OrWindowsU16s,
) -> HostSsgParseAsciidocResult {
    let roc_host = roc_host();
    let input_path = match pathbuf_from_roc_path(path, roc_host) {
        Ok(path) => path,
        Err(message) => return try_parse_asciidoc_err(RocStr::from_str(&message, roc_host)),
    };
    match ssg::read_source(&input_path) {
        Ok(source) => {
            try_parse_asciidoc_ok(roc_asciidoc_document(asciidoc::parse(&source), roc_host))
        }
        Err(message) => try_parse_asciidoc_err(RocStr::from_str(&message, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_ssg_parse_asciidoc_source(
    source_path: UnixBytesOrUtf8OrWindowsU16s,
    source: RocStr,
) -> HostSsgParseAsciidocResult {
    let roc_host = roc_host();
    if let Err(message) = pathbuf_from_roc_path(source_path, roc_host) {
        unsafe {
            source.decref(roc_host);
        }
        return try_parse_asciidoc_err(RocStr::from_str(&message, roc_host));
    }
    let parsed = asciidoc::parse(source.as_str());
    unsafe {
        source.decref(roc_host);
    }
    try_parse_asciidoc_ok(roc_asciidoc_document(parsed, roc_host))
}

#[no_mangle]
pub extern "C" fn hosted_ssg_write_file(
    output_dir: UnixBytesOrUtf8OrWindowsU16s,
    output_path: UnixBytesOrUtf8OrWindowsU16s,
    content: RocStr,
) -> HostSsgWriteFileResult {
    let roc_host = roc_host();
    let output_dir_path = match pathbuf_from_roc_path(output_dir, roc_host) {
        Ok(path) => path,
        Err(message) => {
            unsafe {
                output_path.decref(roc_host);
            }
            unsafe {
                content.decref(roc_host);
            }
            return try_write_file_err(RocStr::from_str(&message, roc_host));
        }
    };
    let output_path = match pathbuf_from_roc_path(output_path, roc_host) {
        Ok(path) => path,
        Err(message) => {
            unsafe {
                content.decref(roc_host);
            }
            return try_write_file_err(RocStr::from_str(&message, roc_host));
        }
    };
    let result = ssg::write_file(&output_dir_path, &output_path, content.as_str());
    unsafe {
        content.decref(roc_host);
    }

    match result {
        Ok(()) => try_write_file_ok(),
        Err(message) => try_write_file_err(RocStr::from_str(&message, roc_host)),
    }
}

#[cfg(unix)]
fn pathbuf_from_roc_path(
    path: UnixBytesOrUtf8OrWindowsU16s,
    roc_host: &RocHost,
) -> Result<PathBuf, String> {
    use std::ffi::OsString;
    use std::os::unix::ffi::OsStringExt;

    match path.tag {
        UnixBytesOrUtf8OrWindowsU16sTag::UnixBytes => unsafe {
            let bytes = ManuallyDrop::into_inner(path.payload.unix_bytes);
            let path = PathBuf::from(OsString::from_vec(bytes.as_slice().to_vec()));
            bytes.decref(roc_host);
            Ok(path)
        },
        UnixBytesOrUtf8OrWindowsU16sTag::Utf8 => unsafe {
            let text = ManuallyDrop::into_inner(path.payload.utf8);
            let path = PathBuf::from(OsString::from_vec(text.as_str().as_bytes().to_vec()));
            text.decref(roc_host);
            Ok(path)
        },
        UnixBytesOrUtf8OrWindowsU16sTag::WindowsU16s => unsafe {
            let u16s = ManuallyDrop::into_inner(path.payload.windows_u16s);
            u16s.decref(roc_host);
            Err("expected UnixBytes path on this platform, got WindowsU16s".to_owned())
        },
    }
}

#[cfg(windows)]
fn pathbuf_from_roc_path(
    path: UnixBytesOrUtf8OrWindowsU16s,
    roc_host: &RocHost,
) -> Result<PathBuf, String> {
    use std::ffi::OsString;
    use std::os::windows::ffi::OsStringExt;

    match path.tag {
        UnixBytesOrUtf8OrWindowsU16sTag::UnixBytes => unsafe {
            let bytes = ManuallyDrop::into_inner(path.payload.unix_bytes);
            bytes.decref(roc_host);
            Err("expected WindowsU16s path on this platform, got UnixBytes".to_owned())
        },
        UnixBytesOrUtf8OrWindowsU16sTag::Utf8 => unsafe {
            let text = ManuallyDrop::into_inner(path.payload.utf8);
            let value = PathBuf::from(OsString::from(text.as_str()));
            text.decref(roc_host);
            Ok(value)
        },
        UnixBytesOrUtf8OrWindowsU16sTag::WindowsU16s => unsafe {
            let u16s = ManuallyDrop::into_inner(path.payload.windows_u16s);
            let path = PathBuf::from(OsString::from_wide(u16s.as_slice()));
            u16s.decref(roc_host);
            Ok(path)
        },
    }
}

#[cfg(not(any(unix, windows)))]
fn pathbuf_from_roc_path(
    path: UnixBytesOrUtf8OrWindowsU16s,
    roc_host: &RocHost,
) -> Result<PathBuf, String> {
    unsafe {
        path.decref(roc_host);
    }
    Err("filesystem paths are unsupported on this platform".to_owned())
}

#[cfg(unix)]
fn roc_path_from_path(path: &Path, roc_host: &RocHost) -> UnixBytesOrUtf8OrWindowsU16s {
    use std::os::unix::ffi::OsStrExt;

    UnixBytesOrUtf8OrWindowsU16s {
        payload: UnixBytesOrUtf8OrWindowsU16sPayload {
            unix_bytes: ManuallyDrop::new(unsafe {
                RocListWith::<u8, false>::from_slice(path.as_os_str().as_bytes(), roc_host)
            }),
        },
        tag: UnixBytesOrUtf8OrWindowsU16sTag::UnixBytes,
    }
}

#[cfg(windows)]
fn roc_path_from_path(path: &Path, roc_host: &RocHost) -> UnixBytesOrUtf8OrWindowsU16s {
    use std::os::windows::ffi::OsStrExt;

    let units: Vec<u16> = path.as_os_str().encode_wide().collect();
    UnixBytesOrUtf8OrWindowsU16s {
        payload: UnixBytesOrUtf8OrWindowsU16sPayload {
            windows_u16s: ManuallyDrop::new(unsafe {
                RocListWith::<u16, false>::from_slice(&units, roc_host)
            }),
        },
        tag: UnixBytesOrUtf8OrWindowsU16sTag::WindowsU16s,
    }
}

#[cfg(not(any(unix, windows)))]
fn roc_path_from_path(path: &Path, roc_host: &RocHost) -> UnixBytesOrUtf8OrWindowsU16s {
    UnixBytesOrUtf8OrWindowsU16s {
        payload: UnixBytesOrUtf8OrWindowsU16sPayload {
            unix_bytes: ManuallyDrop::new(unsafe {
                RocListWith::<u8, false>::from_slice(path.to_string_lossy().as_bytes(), roc_host)
            }),
        },
        tag: UnixBytesOrUtf8OrWindowsU16sTag::UnixBytes,
    }
}

// ============================================================================
// Stdout effects
// ============================================================================

fn try_stdout_unit_ok() -> HostStdoutLineResult {
    HostStdoutLineResult {
        payload: HostStdoutLineResultPayload { ok: [] },
        tag: HostStdoutLineResultTag::Ok,
    }
}

fn try_stdout_unit_err(error: HostIOErr) -> HostStdoutLineResult {
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
    unsafe {
        message.decref(roc_host);
    }

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
    unsafe {
        message.decref(roc_host);
    }

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
    unsafe {
        cmd.program.decref(roc_host);
    }
    unsafe {
        cmd.args.decref(roc_host);
    }
    unsafe {
        cmd.envs.decref(roc_host);
    }

    match result {
        Ok(status) => try_cmd_status_ok(status.code().unwrap_or(-1)),
        Err(error) => try_cmd_status_err(public_io_err_from_std(error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_cmd_output(cmd: HostCmdOutputArgs) -> HostCmdOutput {
    let roc_host = roc_host();
    let mut command = build_process_command(&cmd.program, &cmd.args, &cmd.envs, cmd.clear_envs);
    let result = command.output();
    unsafe {
        cmd.program.decref(roc_host);
    }
    unsafe {
        cmd.args.decref(roc_host);
    }
    unsafe {
        cmd.envs.decref(roc_host);
    }

    match result {
        Ok(output) => HostCmdOutput {
            stderr: unsafe { RocListWith::<u8, false>::from_slice(&output.stderr, roc_host) },
            stdout: unsafe { RocListWith::<u8, false>::from_slice(&output.stdout, roc_host) },
            exit_code: output.status.code().unwrap_or(-1),
        },
        Err(error) => HostCmdOutput {
            stderr: unsafe {
                RocListWith::<u8, false>::from_slice(error.to_string().as_bytes(), roc_host)
            },
            stdout: unsafe { RocListWith::<u8, false>::from_slice(&[], roc_host) },
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
    unsafe {
        name.decref(roc_host);
    }

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
    let list = unsafe { RocList::<HostEnvDict>::allocate(vars.len(), roc_host) };
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
            payload: HostLocaleGetResultPayload { err: [] },
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
    let list = unsafe { RocList::<RocStr>::allocate(all.len(), roc_host) };
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

fn try_utc_now_ok(nanos: u128) -> HostUtcNowResult {
    HostUtcNowResult {
        payload: HostUtcNowResultPayload {
            ok: ManuallyDrop::new(nanos),
        },
        tag: HostUtcNowResultTag::Ok,
    }
}

fn try_utc_now_err() -> HostUtcNowResult {
    HostUtcNowResult {
        payload: HostUtcNowResultPayload { err: [] },
        tag: HostUtcNowResultTag::Err,
    }
}

// TODO(https://github.com/roc-lang/roc/issues/10163): revert to a bare u128
// return once the compiler emits the clang/Rust u128 return convention on
// x86_64-windows; bare u128 returns are currently misread there.
#[no_mangle]
pub extern "C" fn hosted_utc_now() -> HostUtcNowResult {
    match std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH) {
        Ok(duration) => try_utc_now_ok(duration.as_nanos()),
        Err(_) => try_utc_now_err(),
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

#[cfg(unix)]
fn build_args_list(argc: i32, argv: *const *const c_char, roc_host: &RocHost) -> RocList<OsStr> {
    if argc <= 0 || argv.is_null() {
        return RocList::empty();
    }

    let list = unsafe { RocList::<OsStr>::allocate(argc as usize, roc_host) };
    for index in 0..argc as isize {
        unsafe {
            let arg_ptr = *argv.offset(index);
            if arg_ptr.is_null() {
                break;
            }
            let arg = CStr::from_ptr(arg_ptr).to_bytes();
            list.elements.offset(index).write(OsStr {
                payload: OsStrPayload {
                    unix_bytes: ManuallyDrop::new(RocListWith::<u8, false>::from_slice(
                        arg, roc_host,
                    )),
                },
                tag: OsStrTag::UnixBytes,
            });
        }
    }
    list
}

#[cfg(windows)]
fn build_args_list(_argc: i32, _argv: *const *const c_char, roc_host: &RocHost) -> RocList<OsStr> {
    use std::os::windows::ffi::OsStrExt;

    let args = std::env::args_os().collect::<Vec<_>>();
    let list = unsafe { RocList::<OsStr>::allocate(args.len(), roc_host) };
    for (index, arg) in args.iter().enumerate() {
        let units = arg.encode_wide().collect::<Vec<_>>();
        unsafe {
            list.elements.add(index).write(OsStr {
                payload: OsStrPayload {
                    windows_u16s: ManuallyDrop::new(RocListWith::<u16, false>::from_slice(
                        &units, roc_host,
                    )),
                },
                tag: OsStrTag::WindowsU16s,
            });
        }
    }
    list
}

#[cfg(not(any(unix, windows)))]
fn build_args_list(_argc: i32, _argv: *const *const c_char, _roc_host: &RocHost) -> RocList<OsStr> {
    RocList::empty()
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
