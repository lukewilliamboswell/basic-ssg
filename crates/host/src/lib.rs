use core::ffi::c_void;
use roc_std::{RocList, RocResult, RocStr};
use std::path::PathBuf;
use std::{alloc::Layout, mem::MaybeUninit};

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
pub unsafe extern "C" fn roc_dealloc(_c_ptr: *mut c_void, _alignment: u32) {
    // NOOP as a workaround for a lurking double free issue
    // libc::free(c_ptr)
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

extern "C" {
    #[link_name = "roc__mainForHost_1_exposed_generic"]
    pub fn roc_main(output: *mut u8, roc_args: *mut roc_app::Args);

    #[link_name = "roc__mainForHost_1_exposed_size"]
    pub fn roc_main_size() -> i64;

    #[link_name = "roc__mainForHost_0_caller"]
    fn call_Fx(flags: *const u8, closure_data: *const u8, output: *mut RocResult<(), i32>);

    #[allow(dead_code)]
    #[link_name = "roc__mainForHost_0_size"]
    fn size_Fx() -> i64;

    #[allow(dead_code)]
    #[link_name = "roc__mainForHost_0_result_size"]
    fn size_Fx_result() -> i64;
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    init();
    let size = unsafe { roc_main_size() } as usize;
    let layout = Layout::array::<u8>(size).unwrap();

    let args: Vec<String> = std::env::args().collect();
    if args.len() != 3 {
        eprintln!("Missing directory arguments, usage example: roc app.roc -- path/to/input/dir path/to/output/dir");
        return 1;
    }

    let mut roc_args = roc_app::Args {
        inputDir: args[1].as_str().into(),
        outputDir: args[2].as_str().into(),
    };

    unsafe {
        let buffer = std::alloc::alloc(layout);

        roc_main(buffer, &mut roc_args);

        let out = call_the_closure(buffer);

        std::alloc::dealloc(buffer, layout);

        out
    }
}

/// # Safety
///
/// TODO
pub unsafe fn call_the_closure(closure_data_ptr: *const u8) -> i32 {
    // Main always returns an i32. just allocate for that.
    let mut out: RocResult<(), i32> = RocResult::ok(());

    call_Fx(
        // This flags pointer will never get dereferenced
        MaybeUninit::uninit().as_ptr(),
        closure_data_ptr,
        &mut out,
    );

    match out.into() {
        Ok(()) => 0,
        Err(exit_code) => exit_code,
    }
}

// Protect our functions from the vicious GC.
// This is specifically a problem with static compilation and musl.
// TODO: remove all of this when we switch to effect interpreter.
pub fn init() {
    let funcs: &[*const extern "C" fn()] = &[
        roc_fx_applicationError as _,
        roc_fx_parseMarkdown as _,
        roc_fx_findFiles as _,
        roc_fx_writeFile as _,
    ];
    #[allow(forgetting_references)]
    std::mem::forget(std::hint::black_box(funcs));
    if cfg!(unix) {
        let unix_funcs: &[*const extern "C" fn()] =
            &[roc_getppid as _, roc_mmap as _, roc_shm_open as _];
        #[allow(forgetting_references)]
        std::mem::forget(std::hint::black_box(unix_funcs));
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_applicationError(message: RocStr) {
    print!("\x1b[31mError completing tasks:\x1b[0m ");
    println!("{}", message.as_str());
    std::process::exit(1);
}

#[no_mangle]
pub extern "C" fn roc_fx_findFiles(
    dir_path: RocStr,
) -> RocResult<RocList<roc_app::UrlPath>, RocStr> {
    match ssg::find_files(PathBuf::from(dir_path.as_str().to_string())) {
        Ok(vec_files) => RocResult::ok(vec_files[..].into()),
        Err(msg) => RocResult::err(msg.as_str().into()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_parseMarkdown(file_path: RocStr) -> RocResult<RocStr, RocStr> {
    match ssg::parse_markdown(PathBuf::from(file_path.as_str().to_string())) {
        Ok(content) => RocResult::ok(content.as_str().into()),
        Err(msg) => RocResult::err(msg.as_str().into()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_writeFile(
    output_dir_str: RocStr,
    output_rel_path_str: RocStr,
    content: RocStr,
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
