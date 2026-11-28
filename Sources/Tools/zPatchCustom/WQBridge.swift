import Foundation

// Sử dụng @convention(c) và ObjCBool để khớp chính xác với typedef trong C
private let wqGrantBridge: @convention(c) (UnsafePointer<CChar>) -> ObjCBool = { path in
    let p = String(cString: path)
    let r = wq.grantAccess(path: p, requireWrite: false, allowFsgetpathFallback: true)
    return ObjCBool(r.0)
}

private let installWQOnce: Void = {
    wq_set_grant_callback(wqGrantBridge)
}()

func installWQGrantCallbackIfNeeded() {
    _ = installWQOnce
}