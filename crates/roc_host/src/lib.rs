use core::ffi::c_void;
use roc_std::{RocList, RocResult, RocStr};
use std::path::PathBuf;

/// # Safety
///
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_alloc(size: usize, _alignment: u32) -> *mut c_void {
    libc::malloc(size)
}

/// # Safety
///
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_realloc(
    c_ptr: *mut c_void,
    new_size: usize,
    _old_size: usize,
    _alignment: u32,
) -> *mut c_void {
    libc::realloc(c_ptr, new_size)
}

/// # Safety
///
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_dealloc(c_ptr: *mut c_void, _alignment: u32) {
    libc::free(c_ptr)
}

/// # Safety
///
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_panic(msg: *mut RocStr, tag_id: u32) {
    match tag_id {
        0 => {
            eprintln!("Roc standard library hit a panic: {}", &*msg);
        }
        1 => {
            eprintln!("Application hit a panic: {}", &*msg);
        }
        _ => unreachable!(),
    }
    std::process::exit(1);
}

/// # Safety
///
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_dbg(loc: *mut RocStr, msg: *mut RocStr, src: *mut RocStr) {
    eprintln!("[{}] {} = {}", &*loc, &*src, &*msg);
}

/// # Safety
///
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_memset(dst: *mut c_void, c: i32, n: usize) -> *mut c_void {
    libc::memset(dst, c, n)
}

/// # Safety
///
/// TODO
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn roc_getppid() -> libc::pid_t {
    libc::getppid()
}

/// # Safety
///
/// TODO
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn roc_mmap(
    addr: *mut libc::c_void,
    len: libc::size_t,
    prot: libc::c_int,
    flags: libc::c_int,
    fd: libc::c_int,
    offset: libc::off_t,
) -> *mut libc::c_void {
    libc::mmap(addr, len, prot, flags, fd, offset)
}

/// # Safety
///
/// TODO
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn roc_shm_open(
    name: *const libc::c_char,
    oflag: libc::c_int,
    mode: libc::mode_t,
) -> libc::c_int {
    libc::shm_open(name, oflag, mode as libc::c_uint)
}

// Protect our functions from the vicious GC.
// This is specifically a problem with static compilation and musl.
// TODO: remove all of this when we switch to effect interpreter.
pub fn init() {
    let funcs: &[*const extern "C" fn()] = &[
        roc_fx_parse_markdown as _,
        roc_fx_find_files as _,
        roc_fx_write_file as _,
        roc_fx_command_status as _,
        roc_fx_command_output as _,
        roc_fx_stdout_line as _,
        roc_fx_stdout_write as _,
        roc_fx_stderr_line as _,
        roc_fx_stderr_write as _,
        roc_fx_env_dict as _,
        roc_fx_env_var as _,
        roc_fx_current_arch_os as _,
        roc_fx_get_locale as _,
        roc_fx_get_locales as _,
        roc_fx_posix_time as _,
    ];

    #[allow(forgetting_references)]
    std::mem::forget(std::hint::black_box(funcs));

    #[cfg(unix)]
    {
        let unix_funcs: &[*const extern "C" fn()] =
            &[roc_getppid as _, roc_mmap as _, roc_shm_open as _];
        #[allow(forgetting_references)]
        std::mem::forget(std::hint::black_box(unix_funcs));
    }
}

fn call_roc(args: ssg::Args) -> i32 {
    extern "C" {
        #[link_name = "roc__main_for_host_1_exposed"]
        pub fn caller(roc_args: *const ssg::Args) -> i32;

        #[link_name = "roc__main_for_host_1_exposed_size"]
        pub fn size() -> i64;
    }

    unsafe {
        // call roc passing args
        let result = caller(&args);

        // roc now owns args and will cleanup, so we forget them here
        // to prevent rust from dropping.
        std::mem::forget(args);

        debug_assert_eq!(std::mem::size_of_val(&result) as i64, size());

        result
    }
}

pub fn rust_main(args: RocList<RocStr>) -> i32 {
    init();

    const USAGE: &str = "Usage: roc app.roc -- path/to/input/dir path/to/output/dir";

    if args.len() != 3 {
        eprintln!("Incorrect number of arguments.\n{}", USAGE);
        return 1;
    }

    let roc_args = ssg::Args {
        input_dir: args[1].clone(),
        output_dir: args[2].clone(),
    };

    let exit_code = call_roc(roc_args);

    exit_code
}

#[no_mangle]
pub extern "C" fn roc_fx_find_files(dir_path: &RocStr) -> RocResult<RocList<ssg::Files>, RocStr> {
    match ssg::find_files(PathBuf::from(dir_path.as_str().to_string())) {
        Ok(vec_files) => RocResult::ok(vec_files[..].into()),
        Err(msg) => RocResult::err(msg.as_str().into()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_parse_markdown(file_path: &RocStr) -> RocResult<RocStr, RocStr> {
    match ssg::parse_markdown(PathBuf::from(file_path.as_str().to_string())) {
        Ok(content) => RocResult::ok(content.as_str().into()),
        Err(msg) => RocResult::err(msg.as_str().into()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_write_file(
    output_dir_str: &RocStr,
    output_rel_path_str: &RocStr,
    content: &RocStr,
) -> RocResult<(), RocStr> {
    match ssg::write_file(
        PathBuf::from(output_dir_str.as_str().to_string()),
        PathBuf::from(output_rel_path_str.as_str().to_string()),
        content.as_str().to_string(),
    ) {
        Ok(()) => RocResult::ok(()),
        Err(msg) => RocResult::err(msg.as_str().into()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_command_status(
    roc_cmd: &roc_command::Command,
) -> RocResult<i32, roc_io_error::IOErr> {
    roc_command::command_status(roc_cmd)
}

#[no_mangle]
pub extern "C" fn roc_fx_command_output(
    roc_cmd: &roc_command::Command,
) -> roc_command::OutputFromHost {
    roc_command::command_output(roc_cmd)
}

#[no_mangle]
pub extern "C" fn roc_fx_stdout_line(line: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stdout_line(line)
}

#[no_mangle]
pub extern "C" fn roc_fx_stdout_write(text: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stdout_write(text)
}

#[no_mangle]
pub extern "C" fn roc_fx_stderr_line(line: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stderr_line(line)
}

#[no_mangle]
pub extern "C" fn roc_fx_stderr_write(text: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stderr_write(text)
}

#[no_mangle]
pub extern "C" fn roc_fx_env_dict() -> RocList<(RocStr, RocStr)> {
    roc_env::env_dict()
}

#[no_mangle]
pub extern "C" fn roc_fx_env_var(roc_str: &RocStr) -> RocResult<RocStr, ()> {
    roc_env::env_var(roc_str)
}

#[no_mangle]
pub extern "C" fn roc_fx_current_arch_os() -> roc_env::ReturnArchOS {
    roc_env::current_arch_os()
}

#[no_mangle]
pub extern "C" fn roc_fx_get_locale() -> RocResult<RocStr, ()> {
    roc_env::get_locale()
}

#[no_mangle]
pub extern "C" fn roc_fx_get_locales() -> RocList<RocStr> {
    roc_env::get_locales()
}

#[no_mangle]
pub extern "C" fn roc_fx_posix_time() -> roc_std::U128 {
    roc_env::posix_time()
}
