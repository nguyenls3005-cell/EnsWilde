import Foundation

private func wqGrantBridge(_ path: UnsafePointer<CChar>?) -> Bool {
    guard let path else { return false }
    let p = String(cString: path)
    let r = wq.grantAccess(path: p, requireWrite: false, allowFsgetpathFallback: true)
    return r.0
}

private let installWQOnce: Void = {
    wq_set_grant_callback(wqGrantBridge)
}()

func installWQGrantCallbackIfNeeded() {
    _ = installWQOnce
}