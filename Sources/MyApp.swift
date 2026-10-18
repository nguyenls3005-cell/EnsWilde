import SwiftUI
import AirliftFFI

extension Notification.Name {
    static let airliftLog = Notification.Name("airlift.log")
}

@main
struct MyApp: App {
    @AppStorage("hasChosenMode") private var hasChosenMode: Bool = false
    
    init() {
        UserDefaults.standard.set(false, forKey: "ShowApplyTab")
        al_log_init({ _, msg in
            guard let msg = msg else { return }
            let line = String(cString: msg)
            NSLog("[Airlift] %@", line)
            NotificationCenter.default.post(name: .airliftLog, object: nil, userInfo: ["line": line])
        }, nil)
    }
    
    var body: some Scene {
        WindowGroup {
            if !hasChosenMode && isVersionBlocked() {
                VersionBlockedView()
            } else {
                MainViewWithNavigation()
            }
        }
    }
    // Giữ nguyên isVersionBlocked và getCleanBuildNumber như cũ...
}