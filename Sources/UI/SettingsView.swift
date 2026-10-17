import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @AppStorage("PairingFile") private var pairingFile: String?
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @State private var showPairingFileImporter = false
    @State private var vpnActive: Bool = false
    @State private var showVPNAlert = false
    @State private var pairingImportError: String?
    @State private var showPairingErrorAlert = false
    @State private var pairingImportSuccess: String?
    @State private var showPairingSuccessAlert = false

    // Backup
    @State private var showBackupImporter = false
    @State private var showBackupAlert = false
    @State private var backupAlertMessage = ""
    @State private var hasBackup: Bool = false
    @State private var backupInfo: MobileGestaltBackupManager.BackupInfo?

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
            // Khung System Status
            Section(header: Text("System Status")) {
                HStack(spacing: 12) {
                    if pairingFile != nil && vpnActive {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.green)
                        Text("Ready")
                            .font(.body)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.red)
                        Text("Not Ready")
                            .font(.body)
                    }
                }
                .padding(.vertical, 4)
            }

            // Chi tiết
            Section(header: Text("Connection Status")) {
                statusRow(
                    title: "Pairing File",
                    subtitle: pairingFile != nil ? "Ready" : "Not Ready",
                    ok: pairingFile != nil
                )
                statusRow(
                    title: "LocalDevVPN",
                    subtitle: vpnActive ? "Ready" : "Not Ready",
                    ok: vpnActive
                )
            }

            // Pairing
            Section(header: Text("Pairing File")) {
                if pairingFile != nil {
                    Button(role: .destructive) {
                        pairingFile = nil
                        let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
                        try? FileManager.default.removeItem(at: pairingPath)
                    } label: {
                        Label("Reset Pairing", systemImage: "trash")
                    }
                } else {
                    Button {
                        showPairingFileImporter = true
                    } label: {
                        Label("Import Pairing", systemImage: "doc.badge.plus")
                    }
                }

                Button {
                    refreshVPNStatus(showAlert: true)
                } label: {
                    HStack {
                        Label("Check LocalDevVPN", systemImage: "wifi")
                        Spacer()
                        if vpnActive {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
            }

            // Backup
            Section(header: Text("MobileGestalt Backup")) {
                if hasBackup, let info = backupInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                            Text("Backup có sẵn").font(.subheadline.bold())
                            Spacer()
                        }
                        Text("\(info.byteCount) bytes").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Chưa có backup").font(.subheadline.bold())
                    }
                }
                Button { createBackupNow() } label: { Label("Backup ngay", systemImage: "square.and.arrow.down.on.square") }
                Button { showBackupImporter = true } label: { Label("Import backup", systemImage: "square.and.arrow.down") }
                if hasBackup {
                    Button(role: .destructive) { deleteBackup() } label: { Label("Xoá backup", systemImage: "trash") }
                }
            }

            // Maintenance
            Section(header: Text("Maintenance")) {
                Button(role: .destructive) {
                    let mgPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
                    do {
                        let access = bq.grantAccess(atPath: mgPath)
                        if access.0 {
                            try FileManager.default.removeItem(atPath: mgPath)
                            Alertinator.shared.alert(title: "Success", body: "MobileGestalt cache cleared.")
                        } else {
                            Alertinator.shared.alert(title: "Error", body: "Failed to grant access.")
                        }
                    } catch {
                        Alertinator.shared.alert(title: "Error", body: "Failed to clear cache: \(error.localizedDescription)")
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reset MobileGestalt Cache")
                        Text("Reset cache").font(.caption).foregroundStyle(.secondary)
                    }
                }
                
                Button { try? RespringHelper.respring() } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Respring")
                        Text("Clean all environment").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            // Color
            Section(header: Text(L("settings_accent_color"))) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(tintOptions, id: \.hex) { option in
                            colorOptionView(option: option)
                        }
                    }
                }
            }

            // App Info
            Section(header: Text(L("settings_app_info"))) {
                HStack {
                    Label("EnsWilde", systemImage: "sparkles")
                    Spacer()
                    Text("v\(appVersion)").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(L("nav_settings"))
        .onAppear {
            refreshVPNStatus()
            refreshBackupInfo()
        }
        .fileImporter(
            isPresented: $showPairingFileImporter,
            allowedContentTypes: [.propertyList, UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data) ?? .data, UTType(filenameExtension: "plist", conformingTo: .data) ?? .data]
        ) { handlePairingImport($0) }
        .fileImporter(isPresented: $showBackupImporter, allowedContentTypes: [.propertyList]) { handleBackupImport($0) }
    }

    @ViewBuilder
    private func statusRow(title: String, subtitle: String, ok: Bool) -> some View {
        HStack {
            Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
            Spacer()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(ok ? .green : .red)
        }
    }

    private func refreshBackupInfo() {
        hasBackup = MobileGestaltBackupManager.shared.hasBackup
        backupInfo = MobileGestaltBackupManager.shared.info
    }

    private func createBackupNow() {
        do {
            let onDevicePath = MobileGestaltApplyTask.onDeviceMGPath
            let data = try Data(contentsOf: URL(fileURLWithPath: onDevicePath))
            let info = try MobileGestaltBackupManager.shared.ensureBackup(from: data)
            refreshBackupInfo()
            backupAlertMessage = "Đã tạo backup."
            showBackupAlert = true
        } catch { showBackupAlert = true }
    }

    private func handleBackupImport(_ result: Result<URL, Error>) {
        if case .success(let url) = result {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                try? MobileGestaltBackupManager.shared.importBackup(from: data)
                refreshBackupInfo()
            }
        }
    }

    private func deleteBackup() {
        try? MobileGestaltBackupManager.shared.clearBackup()
        refreshBackupInfo()
    }

    private func handlePairingImport(_ result: Result<URL, Error>) {
        if case .success(let url) = result {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                try? data.write(to: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                pairingFile = url.lastPathComponent
            }
        }
    }

    private func refreshVPNStatus(showAlert: Bool = false) {
        NetworkStatus.checkVPNStatus { active in
            self.vpnActive = active
        }
    }

    @ViewBuilder
    private func colorOptionView(option: (name: String, hex: String)) -> some View {
        let color = Color(hex: option.hex)
        let isSelected = userTintColorHex.lowercased() == option.hex.lowercased()
        Circle()
            .fill(color)
            .frame(width: 36, height: 36)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            .onTapGesture {
                userTintColorHex = option.hex
            }
    }

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
}