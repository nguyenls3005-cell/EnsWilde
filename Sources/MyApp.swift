import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

extension UIDocumentPickerViewController {
    @objc func fix_init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool) -> UIDocumentPickerViewController {
        return fix_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}

@main
struct MyApp: App {
    private static let antiTamperMessage: String = "Fuck you. Get out..."
    @State private var isSupportedOS: Bool = false

    init() {
        if Self.antiTamperMessage.isEmpty { return }

        let hexString = UserDefaults.standard.string(forKey: "EnsWilde.userTintColor") ?? "#ef9f76"
        let tintColor = UIColor(Color(hex: hexString))
        UIView.appearance(whenContainedInInstancesOf: [UIWindow.self]).tintColor = tintColor
        UITabBar.appearance().tintColor = tintColor
        UINavigationBar.appearance().tintColor = tintColor

        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            let osCheck = isOSVersionSupported()
            if osCheck.supported {
                MainViewWithNavigation()
            } else {
                UnsupportedVersionView(currentVersion: osCheck.versionString)
            }
        }
    }
    
    private func isOSVersionSupported() -> (supported: Bool, versionString: String) {
        let osVersion = UIDevice.current.systemVersion
        let build = getBuildNumber()
        
        // Mã Build cho phép: Beta 1, 2, PB1, 3, 4, PB4
        let allowedBuilds = ["24A5355q", "24A5370", "24A5380h", "24A5390f"]
        
        if allowedBuilds.contains(build) {
            return (true, osVersion)
        } else {
            return (false, osVersion)
        }
    }
    
    private func getBuildNumber() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}

struct UnsupportedVersionView: View {
    var currentVersion: String
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.orange)
                    .padding(.bottom, 10)
                
                Text("iOS Version Not Supported")
                    .font(.title.bold())
                    .foregroundColor(.white)
                
                Text("This app only supports iOS versions 27.0 Developer Beta 1-4 / Public Beta 1-2")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("Your current iOS version:")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.top, 10)
                
                Text(currentVersion)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 15) {
                    Text("To use this app:")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.gray)
                        Text("Downgrade to iOS 27 Developer Beta 4 or earlier")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    HStack(spacing: 10) {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundColor(.gray)
                        Text("Contact the developer for support")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(15)
                .padding(.top, 20)
                .padding(.horizontal)
            }
            .padding()
        }
    }
}