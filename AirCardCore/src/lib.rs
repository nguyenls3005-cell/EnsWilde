pub mod grappa;
pub mod ffi_util;
pub mod exploit;

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::panic::{catch_unwind, AssertUnwindSafe};

#[no_mangle]
pub extern "C" fn al_log_init(_level: c_int) -> c_int { 0 }

#[no_mangle]
pub extern "C" fn al_set_target_host(host: *const c_char) -> c_int {
    if host.is_null() { return -1; }
    if let Ok(s) = unsafe { CStr::from_ptr(host) }.to_str() {
        exploit::set_target_host(Some(s.to_string()));
        0
    } else { -2 }
}

#[no_mangle]
pub extern "C" fn al_string_free(s: *mut c_char) {
    if !s.is_null() { unsafe { let _ = CString::from_raw(s); } }
}

#[no_mangle]
pub extern "C" fn al_exploit_write_dir(
    pairing_path: *const c_char,
    path: *const c_char,
    data: *const u8,
    data_len: usize,
    log_cb: exploit::ALLogCallback,
    ctx: *mut c_void,
    out_error: *mut *mut c_char,
) -> c_int {
    // Bọc catch_unwind để app không bao giờ bị văng nếu Rust panic
    let result = catch_unwind(AssertUnwindSafe(|| {
        let pairing = if pairing_path.is_null() { "airlift_pairing.plist".to_string() }
            else { unsafe { CStr::from_ptr(pairing_path) }.to_str().unwrap_or("").to_string() };
        
        let target_file = if path.is_null() { "".to_string() }
            else { unsafe { CStr::from_ptr(path) }.to_str().unwrap_or("").to_string() };
            
        let payload = if data.is_null() || data_len == 0 { &[] }
            else { unsafe { std::slice::from_raw_parts(data, data_len) } };

        // Tạo thư mục tạm chứa file cần ghi để gọi hàm exploit_write_dir của bạn
        let temp_dir = std::env::temp_dir().join("airlift_temp");
        let _ = std::fs::create_dir_all(&temp_dir);
        let file_name = std::path::Path::new(&target_file).file_name().unwrap_or_default().to_string_lossy().to_string();
        let temp_file = temp_dir.join(&file_name);
        let _ = std::fs::write(&temp_file, payload);

        // Lấy thư mục đích (target_dir) bằng cách bỏ tên file
        let target_dir = std::path::Path::new(&target_file).parent().unwrap_or(std::path::Path::new("")).to_string_lossy().to_string();

        let ctx_usize = ctx as usize;
        let logger = exploit::Logger { cb: log_cb, ctx: ctx_usize as *mut c_void };

        // Chạy trên 1 thread riêng để không block Main Thread
        let handle = std::thread::spawn(move || {
            let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
            rt.block_on(exploit::exploit_write_dir(pairing, temp_dir.to_string_lossy().to_string(), target_dir, &logger))
        });

        match handle.join() {
            Ok(res) => res,
            Err(_) => Err("Rust thread panicked".to_string()),
        }
    }));

    match result {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            if !out_error.is_null() { unsafe { *out_error = CString::new(e).unwrap_or_default().into_raw(); } }
            1
        }
        Err(_) => {
            if !out_error.is_null() { unsafe { *out_error = CString::new("Panic caught").unwrap().into_raw(); } }
            1
        }
    }
}

// Device respring
#[no_mangle]
pub extern "C" fn al_device_respring(
    pairing_path: *const c_char,
    log_cb: exploit::ALLogCallback,
    ctx: *mut c_void,
    out_error: *mut *mut c_char,
) -> c_int {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let pairing = if pairing_path.is_null() { "airlift_pairing.plist".to_string() }
            else { unsafe { CStr::from_ptr(pairing_path) }.to_str().unwrap_or("").to_string() };

        let ctx_usize = ctx as usize;
        let logger = exploit::Logger { cb: log_cb, ctx: ctx_usize as *mut c_void };

        let handle = std::thread::spawn(move || {
            let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
            rt.block_on(exploit::exploit_device_respring(pairing, &logger))
        });

        match handle.join() {
            Ok(res) => res,
            Err(_) => Err("Rust thread panicked".to_string()),
        }
    }));

    match result {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            if !out_error.is_null() { unsafe { *out_error = CString::new(e).unwrap_or_default().into_raw(); } }
            1
        }
        Err(_) => {
            if !out_error.is_null() { unsafe { *out_error = CString::new("Panic caught").unwrap().into_raw(); } }
            1
        }
    }
}