import Foundation
import UIKit
import SwiftUI

// MARK: - FileManager instance
let fm = FileManager.default

// MARK: - FSURL paths
enum FSPaths {
    static let appContainers = "/var/mobile/Containers/Data/Application"
    static let appBundles = "/var/containers/Bundle/Application"
}

enum FSURL {
    static let appContainers = URL(fileURLWithPath: FSPaths.appContainers)
    static var sysGroup = URL(fileURLWithPath: "/var/containers/Shared/SystemGroup")
    static var configProfiles = FSURL.sysGroup.appendingPathComponent("systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles")
    static var internalDaemons = URL(fileURLWithPath: "/var/mobile/Containers/Data/InternalDaemon")
    static var appPlugins = URL(fileURLWithPath: "/var/mobile/Containers/Data/PluginKitPlugin")
    static var appGroup = URL(fileURLWithPath: "/var/mobile/Containers/Shared/AppGroup")
    static var systemData = URL(fileURLWithPath: "/var/containers/Data/System")
}

// MARK: - AppMsg
enum AppMsg {
    static let opFailed = "Operation failed. Check console logs for details."
    static let applied = "Changes applied. You may need to respring for them to take effect."
}

// MARK: - Haptic
final class Haptic {
    static let shared = Haptic()
    private init() {}

    enum HapticType {
        case soft, light, medium, heavy, rigid, success, warning, error
    }

    func play(_ type: HapticType) {
        switch type {
        case .soft:    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .light:   UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:  UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:   UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .rigid:   UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:   UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

// MARK: - HeaderLabel
struct HeaderLabel: View {
    let text: String
    let symbol: String

    init(_ text: String, symbol: String) {
        self.text = text
        self.symbol = symbol
    }

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.bold())
    }
}

// MARK: - PlainToggle
struct PlainToggle: View {
    let label: String
    let infoType: InfoType
    let infoTitle: String
    let infoMessage: String
    @Binding var isOn: Bool

    enum InfoType {
        case warning, info
    }

    init(_ label: String,
         infoType: InfoType = .info,
         infoTitle: String = "",
         infoMessage: String = "",
         isOn: Binding<Bool>) {
        self.label = label
        self.infoType = infoType
        self.infoTitle = infoTitle
        self.infoMessage = infoMessage
        self._isOn = isOn
    }

    @State private var showInfo = false

    var body: some View {
        HStack {
            Toggle(label, isOn: $isOn)

            if !infoMessage.isEmpty {
                Button {
                    showInfo = true
                } label: {
                    Image(systemName: infoType == .warning ? "exclamationmark.triangle" : "info.circle")
                        .foregroundStyle(infoType == .warning ? .orange : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .alert(infoTitle, isPresented: $showInfo) {
            Button("OK") {}
        } message: {
            Text(infoMessage)
        }
    }
}

// MARK: - FileManager extension
extension FileManager {
    func createDirIfNeeded(at url: URL) throws {
        if !self.fileExists(atPath: url.path) {
            try? self.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

// MARK: - String as Error
extension String: @retroactive Error {}
