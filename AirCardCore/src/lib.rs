pub mod grappa;
pub mod ffi_util;
pub mod exploit;

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

pub use exploit::{run, write_dir, inject_folder, find_container, device_respring, run_syslog_stream};
use std::os::raw::{c_char, c_int};

#[no_mangle]
pub extern "C" fn al_log_init(_level: c_int) -> c_int { 0 }

#[no_mangle]
pub extern "C" fn al_set_target_host(_host: *const c_char) -> c_int { 0 }

#[no_mangle]
pub extern "C" fn al_exploit_write_dir(
    _path: *const c_char,
    _data: *const u8,
    _data_len: usize,
) -> c_int { 0 }

#[no_mangle]
pub extern "C" fn al_string_free(_s: *mut c_char) {}