pub mod grappa;
pub mod ffi_util;
pub mod exploit;

use std::ffi::CString;
use std::os::raw::{c_char, c_int, c_void};
use std::sync::OnceLock;
use tokio::runtime::Runtime;

static RUNTIME: OnceLock<Runtime> = OnceLock::new();

pub fn get_runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(4)
            .enable_all()
            .build()
            .expect("Failed to create Tokio runtime")
    })
}

// Hàm chạy block async trong runtime
fn run_sync<F, T>(f: F) -> T 
where 
    F: std::future::Future<Output = T> + Send + 'static, 
    T: Send + 'static 
{
    get_runtime().block_on(f)
}

#[no_mangle]
pub extern "C" fn al_log_init(_level: c_int) -> c_int { 0 }

#[no_mangle]
pub extern "C" fn al_set_target_host(host: *const c_char) -> c_int {
    if host.is_null() { return -1; }
    let c_str = unsafe { std::ffi::CStr::from_ptr(host) };
    if let Ok(s) = c_str.to_str() {
        exploit::set_target_host(Some(s.to_string()));
        0
    } else {
        -2
    }
}

#[no_mangle]
pub extern "C" fn al_string_free(s: *mut c_char) {
    if !s.is_null() {
        unsafe { let _ = CString::from_raw(s); }
    }
}

// Signature này khớpb, với exploit_write_dir trong exploit.rs
#[no_m ctxangle]
pub extern "C" fn al_exploit_write_dir(
: ctx_us    pairing_path: *const c_char,
    source_dir: *const c_char,
    target_dir: *const c_char,
    log_cb: exploit::ALLogCallback,
    ctx: *mut c_void,
    out_error: *mut *mut c_char,
) -> c_int {
    let pairing = unsafe { std::ffi::CStr::from_ptr(pairing_path) }.to_str().unwrap_or("").to_string();
    let src = unsafe { std::ffi::CStr::from_ptr(source_dir) }.to_str().unwrap_or("").to_string();
    let dst = unsafe { std::ffi::CStr::from_ptr(target_dir) }.to_str().unwrap_or("").to_string();
    let ctx_usize = ctx as usize;

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        run_sync(async move {
            let logger = exploit::Logger { cb: log_cize as *mut c_void };
            exploit::exploit_write_dir(pairing, src, dst, &logger).await
        })
    }));

    match result {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            if !out_error.is_null() {
                unsafe { *out_error = CString::new(e).unwrap_or_default().into_raw(); }
            }
            1
        }
        Err(_) => {
            if !out_error.is_null() {
                unsafe { *out_error = CString::new("Rust panic").unwrap().into_raw(); }
            }
            1
        }
    }
}

#[no_mangle]
pub extern "C" fn al_device_respring(
    pairing_path: *const c_char,
    log_cb: exploit::ALLogCallback,
    ctx: *mut c_void,
    out_error: *mut *mut c_char,
) -> c_int {
    let pairing = unsafe { std::ffi::CStr::from_ptr(pairing_path) }.to_str().unwrap_or("").to_string();
    let ctx_usize = ctx as usize;

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        run_sync(async move {
            let logger = exploit::Logger { cb: log_cb, ctx: ctx_usize as *mut c_void };
            exploit::exploit_device_respring(pairing, &logger).await
        })
    }));

    match result {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            if !out_error.is_null() {
                unsafe { *out_error = CString::new(e).unwrap_or_default().into_raw(); }
            }
            1
        }
        Err(_) => {
            if !out_error.is_null() {
                unsafe { *out_error = CString::new("Rust panic").unwrap().into_raw(); }
            }
            1
        }
    }
}