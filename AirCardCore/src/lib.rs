pub mod grappa;
pub mod ffi_util;
pub mod exploit;

// Re-export các hàm C-FFI để Swift có thể gọi được
pub use exploit::{run, write_dir, inject_folder, find_container, device_respring, run_syslog_stream};
