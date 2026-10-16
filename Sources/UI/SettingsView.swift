import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @AppStorage("PairingFile") private var pairingFile: String?
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @State private var showPairingFileImporter = false
    var heartbeatRunning: Bool = false
    var ddiMounted: Bool = false

    private let tintOptions: [(name: String, hex: String)] = [
        ("Pink", "#f4b8e4"),
        ("Mauve", "#ca9ee6"),
        ("Red", "#e78284"),
        ("Green", "#a6d189"),
        ("Blue", "#8caaee"),
    ]

    @State private var copiedPath: String?

    var body: some View {
        Form {
            systemStatusSection
            languageSection
            colorSection
            tutorialSection
            appInfoSection
        }
        .headerProminence(.increased)
        .navigationTitle(L("nav_settings"))
        .onAppear {
            if languageManager.availableLanguages.isEmpty {
                Task {
                    await languageManager.fetchAvailableLanguages()
                }
            }
        }
    }

    // MARK: - System Status Section
    @ViewBuilder
    private var systemStatusSection: some View {
        Section(header: Text(L("system_status") + " (For Passcode, Wallet)")) {
            statusRow(
                title: L("status_pairing_file"),
                subtitle: pairingFile != nil ? L("status_pairing_loaded") : L("status_pairing_missing"),
                ok: pairingFile != nil
            )
        }
    }

    @ViewBuilder
    private func statusRow(title: String, subtitle: String, ok: Bool) -> some View {
        HStack {
            Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            Spacer()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Language Section
    @ViewBuilder
    private var languageSection: some View {
        Section(header: Text(L("settings_language"))) {
            NavigationLink(destination: LanguageSettingsView()) {
                Label(L("settings_language"), systemImage: "globe")
            }
        }
    }

    // MARK: - Tutorial Section
    @ViewBuilder
    private var tutorialSection: some View {
        Section(header: Text(L("settings_tutorial"))) {
            NavigationLink {
                TutorialView()
            } label: {
                Label(L("tutorial_guide"), systemImage: "book.fill")
            }

            Button {
                let version = (UIDevice.current.systemVersion as NSString).floatValue
                let passcodePath = version >= 26.0
                    ? "file://a/var/mobile/Library/Caches/TelephonyUI-10/"
                    : "file://a/var/mobile/Library/Caches/TelephonyUI-9/"
                UIPasteboard.general.string = passcodePath
                copiedPath = "passcode"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if copiedPath == "passcode" { copiedPath = nil }
                }
            } label: {
                HStack {
                    Label(L("tutorial_copy_passcode_path"), systemImage: "lock.rectangle")
                    Spacer()
                    if copiedPath == "passcode" {
                        Image(systemName: "checkmark").foregroundStyle(.green)
                    } else {
                        Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                UIPasteboard.general.string = "file://a/var/mobile/Library/Passes/Cards/"
                copiedPath = "wallet"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if copiedPath == "wallet" { copiedPath = nil }
                }
            } label: {
                HStack {
                    Label(L("tutorial_copy_wallet_path"), systemImage: "wallet.pass")
                    Spacer()
                    if copiedPath == "wallet" {
                        Image(systemName: "checkmark").foregroundStyle(.green)
                    } else {
                        Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Color Section
    @ViewBuilder
    private var colorSection: some View {
        Section(header: Text(L("settings_accent_color"))) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(tintOptions, id: \.hex) { option in
                        colorOptionView(option: option)
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
    }

    @ViewBuilder
    private func colorOptionView(option: (name: String, hex: String)) -> some View {
        let color = Color(hex: option.hex)
        let isSelected = userTintColorHex.lowercased() == option.hex.lowercased()
        VStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 36, height: 36)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .opacity(isSelected ? 1 : 0)
                )
            Text(option.name)
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .frame(width: 60)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? color.opacity(0.15) : Color.clear)
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                userTintColorHex = option.hex
                let uiColor = UIColor(Color(hex: option.hex))
                UITabBar.appearance().tintColor = uiColor
                UINavigationBar.appearance().tintColor = uiColor
                for scene in UIApplication.shared.connectedScenes {
                    guard let windowScene = scene as? UIWindowScene else { continue }
                    for window in windowScene.windows { window.tintColor = uiColor }
                }
            }
        }
    }

    // MARK: - App Info Section
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    @ViewBuilder
    private var appInfoSection: some View {
        Section(header: Text(L("settings_app_info"))) {
            HStack {
                Label("EnsWilde", systemImage: "sparkles")
                Spacer()
                Text("v\(appVersion)").font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Label("iOS", systemImage: "iphone")
                Spacer()
                Text(UIDevice.current.systemVersion).font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Label("Device", systemImage: "apps.iphone")
                Spacer()
                Text(settingsDeviceModelName()).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func settingsDeviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        return UIDevice.current.name.isEmpty ? identifier : "\(UIDevice.current.name) (\(identifier))"
    }
}