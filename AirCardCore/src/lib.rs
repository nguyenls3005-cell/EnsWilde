pub mod grappa;
pub mod ffi_util;
pub mod exploit;

use std::ffi::CString;
use std::os::raw::{c_char, c_int, c_void};
use std::panic::{catch_unwind, AssertUnwindSafe};

#[no_mangle]
pub extern "C" fn al_log_init(_level: c_int) -> c_int { 0 }

#[no_mangle]
pub extern "C" fn al_set_target_host(host: *const c_char) -> c_int {
    if host.is_null() { return -1; }
    if let Ok(s) = unsafe { std::ffi::CStr::from_ptr(host) }.to_str() {
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
    source_dir: *const c_char,
    target_dir: *const c_char,
    log_cb: exploit::ALLogCallback,
    ctx: *mut c_void,
    out_error: *mut *mut c_char,
) -> c_int {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let pairing = if pairing_path.is_null() { "airlift_pairing.plist".to_string() }
            else { unsafe { std::ffi::CStr::from_ptr(pairing_path) }.to_str().unwrap_or("").to_string() };
        let src = if source_dir.is_null() { "".to_string() }
            else { unsafe { std::ffi::CStr::from_ptr(source_dir) }.to_str().unwrap_or("").to_string() };
        let dst = if target_dir.is_null() { "".to_string() }
            else { unsafe { std::ffi::CStr::from_ptr(target_dir) }.to_str().unwrap_or("").to_string() };
        
        let ctx_usize = ctx as usize;
        let cb = log_cb;

        let handle = std::thread::spawn(move || {
            let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
            rt.block_on(async move {
                let logger = exploit::Logger { cb, ctx: ctx_usize as *mut c_void };
                exploit::exploit_write_dir(pairing, src, dst, &logger).await
            })
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

#[no_mangle]
pub extern "C" fn al_device_respring(
    pairing_path: *const c_char,
    log_cb: exploit::ALLogCallback,
    ctx: *mut c_void,
    out_error: *mut *mut c_char,
) -> c_int {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let pairing = if pairing_path.is_null() { "airlift_pairing.plist".to_string() }
            else { unsafe { std::ffi::CStr::from_ptr(pairing_path) }.to_str().unwrap_or("").to_string() };

        let ctx_usize = ctx as usize;
        let cb = log_cb;

        let handle = std::thread::spawn(move || {
            let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
            rt.block_on(async move {
                let logger = exploit::Logger { cb, ctx: ctx_usize as *mut c_void };
                exploit::exploit_device_respring(pairing, &logger).await
            })
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