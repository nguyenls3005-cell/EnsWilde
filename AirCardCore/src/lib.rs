pub mod grappa;
pub mod ffi_util;
pub mod exploit;

use std::ffi::CString;
use std::os::raw::{c_char, c_int};
use std::sync::OnceLock;
use std::sync::Mutex;
use tokio::runtime::Runtime;

static RUNTIME: OnceLock<Runtime> = OnceLock::new();
static TARGET_HOST: Mutex<Option<String>> = Mutex::new(None);

pub fn get_runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(4)
            .enable_all()
            .build()
            .expect("Failed to create Tokio runtime")
    })
}

// ============================================================================
// C FFI EXPORTS (Gọi từ Swift)
// ============================================================================

#[no_mangle]
pub extern "C" fn al_log_init(level: c_int) -> c_int {
    // Tùy chọn: setup logging với mức `level` (0=trace, 1=debug, 2=info, ...)
    // Ở đây bỏ qua để tránh xung đột subscriber.
    let _ = level;
    0
}

#[no_mangle]
pub extern "C" fn al_set_target_host(host: *const c_char) -> c_int {
    if host.is_null() { return -1; }
    let c_str = unsafe { std::ffi::CStr::from_ptr(host) };
    if let Ok(s) = c_str.to_str() {
        if let Ok(mut lock) = TARGET_HOST.lock() {
            *lock = Some(s.to_string());
            // Đồng thời set global trong exploit để nó ưu tiên dùng host này
            exploit::set_target_host(Some(s.to_string()));
        }
        0
    } else {
        -2
    }
}

#[no_mangle]
pub extern "C" fn al_string_free(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

#[no_mangle]
pub extern "C" fn al_exploit_write_dir(
    pairing_path: *const c_char,
    source_dir: *const c_char,
    target_dir: *const c_char,
    out_error: *mut *mut c_char,
) -> c_int {
    if source_dir.is_null() || target_dir.is_null() {
        return -1;
    }

    let src = unsafe { std::ffi::CStr::from_ptr(source_dir) }.to_str().unwrap_or("").to_string();
    let dst = unsafe { std::ffi::CStr::from_ptr(target_dir) }.to_str().unwrap_or("").to_string();
    let pairing = if pairing_path.is_null() {
        "airlift_pairing.plist".to_string()
    } else {
        unsafe { std::ffi::CStr::from_ptr(pairing_path) }.to_str().unwrap_or("airlift_pairing.plist").to_string()
    };

    let logger = exploit::Logger { cb: None, ctx: std::ptr::null_mut() };
    
    let result = exploit::run_with_large_stack("al_exploit_write_dir", move || {
        exploit::run_sync_local(async move {
            exploit::exploit_write_dir(pairing, src, dst, &logger).await
        })
    });

    match result {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            if !out_error.is_null() {
                unsafe { *out_error = CString::new(e).unwrap_or_default().into_raw(); }
            }
            1
        }
        Err(_) => 1,
    }
}

// Bạn cũng nên export thêm các hàm khác nếu Swift có dùng (ví dụ: al_exploit_run, al_device_respring)
// Dưới đây là ví dụ map cho respring:
#[no_mangle]
pub extern "C" fn al_device_respring(
    pairing_path: *const c_char,
    out_error: *mut *mut c_char,
) -> c_int {
    let pairing = if pairing_path.is_null() {
        "airlift_pairing.plist".to_string()
    } else {
        unsafe { std::ffi::CStr::from_ptr(pairing_path) }.to_str().unwrap_or("airlift_pairing.plist").to_string()
    };

    let logger = exploit::Logger { cb: None, ctx: std::ptr::null_mut() };

    let result = exploit::run_with_large_stack("al_device_respring", move || {
        exploit::run_sync_local(async move {
            exploit::exploit_device_respring(pairing, &logger).await
        })
    });

    match result {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            if !out_error.is_null() {
                unsafe { *out_error = CString::new(e).unwrap_or_default().into_raw(); }
            }
            1
        }
        Err(_) => 1,
    }
}

// Tương tự cho các hàm khác nếu cần:
// al_exploit_run (dùng exploit::run)
// al_exploit_inject_folder (dùng exploit::inject_folder)
// al_find_app_container (dùng exploit::find_container)
// al_syslog_stream (dùng exploit::run_syslog_stream)