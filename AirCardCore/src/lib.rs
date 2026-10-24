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

// Hàm hỗ trợ chạy async trên background thread để không block Main Thread
fn run_on_background<F>(f: F) -> Result<(), String> 
where 
    F: std::future::Future<Output = Result<(), String>> + Send + 'static
{
    // Tạo một thread riêng biệt để chạy Tokio runtime
    let handle = std::thread::spawn(move || {
        // Tạo runtime mới hoàn toàn cho thread này để tránh xung đột
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(f)
    });

    match handle.join() {
        Ok(res) => res,
        Err(_) => Err("Rust thread panicked".to_string()),
    }
}

#[no_mangle]
pub extern "C" fn al_exploit_write_dir(
    pairing_path: *const c_char,
    source_dir: *const c_char,
    target_dir: *const c_char,
    log_cb: exploit::ALLogCallback,
    ctx: *mut c_void,
    out_error: *mut *mut c_char,
) -> c_int {
    let pairing = if pairing_path.is_null() { "airlift_pairing.plist".to_string() }
        else { unsafe { std::ffi::CStr::from_ptr(pairing_path) }.to_str().unwrap_or("").to_string() };
    let src = if source_dir.is_null() { "".to_string() }
        else { unsafe { std::ffi::CStr::from_ptr(source_dir) }.to_str().unwrap_or("").to_string() };
    let dst = if target_dir.is_null() { "".to_string() }
        else { unsafe { std::ffi::CStr::from_ptr(target_dir) }.to_str().unwrap_or("").to_string() };
    
    // Chuyển con trỏ thành số nguyên để gửi an toàn qua thread
    let ctx_usize = ctx as usize;
    // Ép kiểu callback (thực tế con trỏ hàm có thể gửi qua thread an toàn nếu ta tự đảm bảo)
    let cb = log_cb;

    let res = run_on_background(async move {
        let logger = exploit::Logger { cb, ctx: ctx_usize as *mut c_void };
        exploit::exploit_write_dir(pairing, src, dst, &logger).await
    });

    match res {
        Ok(()) => 0,
        Err(e) => {
            if !out_error.is_null() {
                unsafe { *out_error = CString::new(e).unwrap_or_default().into_raw(); }
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
    let pairing = if pairing_path.is_null() { "airlift_pairing.plist".to_string() }
        else { unsafe { std::ffi::CStr::from_ptr(pairing_path) }.to_str().unwrap_or("").to_string() };
    
    let ctx_usize = ctx as usize;
    let cb = log_cb;

    let res = run_on_background(async move {
        let logger = exploit::Logger { cb, ctx: ctx_usize as *mut c_void };
        exploit::exploit_device_respring(pairing, &logger).await
    });

    match res {
        Ok(()) => 0,
        Err(e) => {
            if !out_error.is_null() {
                unsafe { *out_error = CString::new(e).unwrap_or_default().into_raw(); }
            }
            1
        }
    }
}