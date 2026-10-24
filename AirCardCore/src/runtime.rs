use std::future::Future;
use tokio::runtime::{Builder, Runtime};
use std::sync::OnceLock;

static RUNTIME: OnceLock<Runtime> = OnceLock::new();

pub fn get_runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("Failed to create Tokio runtime")
    })
}

pub fn run_sync<F, T>(future: F) -> T
where
    F: Future<Output = T>,
{
    get_runtime().block_on(future)
}