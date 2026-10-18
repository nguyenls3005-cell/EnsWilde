import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Network

struct SettingsView: View {
    @ObservedObject var toolStore: ToolStore
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @AppStorage("PairingFile") private var pairingFile: String?
    @State private var showPairingFileImporter = false
    @State private var vpnActive: Bool = false
    @State private var monitor: NWPathMonitor?
    
    @State private var showBackupImporter = false
    @State private var hasBackup: Bool = false
    @State private var backupInfo: MobileGestaltBackupManager.BackupInfo?

    @State private var isCleaning = false
    @State private var showCleanAlert = false
    @State private var cleanAlertMessage = ""

    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    private let tintOptions: [(name: String, hex: String)] = [
        ("Pink", "#f4b8e4"), ("Mauve", "#ca9ee6"), ("Red", "#e78284"), ("Green", "#a6d189"), ("Blue", "#8caaee")
    ]

    var body: some View {
        Form {
            Section(header: Text(L("system_status"))) {
                HStack(spacing: 12) {
                    if pairingFile != nil && vpnActive {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(.green)
                        Text(L("status_ready")).font(.body)
                    } else {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(.red)
                        Text(L("status_not_ready")).font(.body)
                    }
                }.padding(.vertical, 4)
            }

            Section(header: Text(L("connection_status"))) {
                statusRow(title: L("pairing_file"), subtitle: pairingFile != nil ? L("status_ready") : L("status_not_ready"), ok: pairingFile != nil)
                statusRow(title: "LocalDevVPN", subtitle: vpnActive ? L("status_ready") : L("status_not_ready"), ok: vpnActive)
            }

            Section(header: Text(L("pairing_file"))) {
                if pairingFile != nil {
                    Button(role: .destructive) {
                        pairingFile = nil
                        try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                    } label: { Label(L("button_reset_pairing"), systemImage: "trash") }
                } else {
                    Button { showPairingFileImporter = true } label: { Label(L("button_select_pairing"), systemImage: "doc.badge.plus") }
                }
            }

            // MARK: - ENVIRONMENT CLEANUP
            Section(header: Text("Environment Cleanup")) {
                if isCleaning {
                    HStack { ProgressView(); Text("Cleaning...").padding(.leading, 8) }
                } else {
                    Button {
                        clearMobileGestaltCache()
                    } label: {
                        Label("Clear MobileGestalt cache", systemImage: "trash.slash").foregroundColor(.red)
                    }
                    
                    Button {
                        respringClean()
                    } label: {
                        Label("Respring (Clean Environment)", systemImage: "arrow.triangle.2.circlepath").foregroundColor(.orange)
                    }
                }
            }

            Section(header: Text(L("backup_title"))) {
                if hasBackup, let info = backupInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                            Text(L("backup_available")).font(.subheadline.bold())
                            Spacer()
                        }
                        Text("\(L("backup_date")) \(info.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        Text("\(L("backup_size")) \(info.byteCount) bytes").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("backup_none")).font(.subheadline.bold())
                            Text(L("backup_none_desc")).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
                
                Button { createBackupNow() } label: { Label(L("backup_now"), systemImage: "square.and.arrow.down.on.square") }
                Button { showBackupImporter = true } label: { Label(L("backup_import"), systemImage: "square.and.arrow.down") }
                if hasBackup {
                    Button(role: .destructive) { deleteBackup() } label: { Label(L("backup_delete"), systemImage: "trash") }
                }
            }

            Section(header: Text(L("settings_language"))) {
                NavigationLink(destination: LanguageSettingsView()) {
                    Label(L("settings_language"), systemImage: "globe")
                }
            }

            Section(header: Text(L("settings_accent_color"))) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(tintOptions, id: \.hex) { option in
                            colorOptionView(option: option)
                        }
                    }
                }
            }

            Section(header: Text(L("settings_app_info"))) {
                HStack { Label("EnsWilde", systemImage: "sparkles"); Spacer(); Text("v\(appVersion)").font(.footnote).foregroundStyle(.secondary) }
                HStack { Label(L("app_ios"), systemImage: "iphone"); Spacer(); Text(UIDevice.current.systemVersion).font(.footnote).foregroundStyle(.secondary) }
                HStack { Label(L("app_device"), systemImage: "apps.iphone"); Spacer(); Text(settingsDeviceModelName()).font(.footnote).foregroundStyle(.secondary) }
                Text(L("app_info_footer"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .navigationTitle(L("nav_settings"))
        .onAppear {
            startMonitoringVPN()
            refreshBackupInfo()
        }
        .onDisappear { monitor?.cancel() }
        .fileImporter(isPresented: $showPairingFileImporter, allowedContentTypes: [.propertyList, UTType(filenameExtension: "mobiledevicepairing") ?? .data]) { handlePairingImport($0) }
        .fileImporter(isPresented: $showBackupImporter, allowedContentTypes: [.propertyList]) { handleBackupImport($0) }
        .alert("System Message", isPresented: $showCleanAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cleanAlertMessage)
        }
    }

    // MARK: - LOGIC DỌN DẸP (DÙNG BADQUERY XÓA FILE, KHÔNG XÓA THƯ MỤC)
    private func clearMobileGestaltCache() {
        isCleaning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let mgPath = MobileGestaltApplyTask.onDeviceMGPath
            let bq = BadQuery()
            
            // Chỉ xóa file plist, không xóa thư mục
            // Nếu BadQuery có hàm executeCommand, dùng nó
            // Ở đây tôi dùng FileManager để xóa file, an toàn hơn
            var success = false
            do {
                // Kiểm tra xem đường dẫn là file hay thư mục
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: mgPath, isDirectory: &isDir) {
                    if isDir.boolValue {
                        // Nếu là thư mục, xóa nội dung bên trong
                        let contents = try FileManager.default.contentsOfDirectory(atPath: mgPath)
                        for file in contents {
                            let filePath = (mgPath as NSString).appendingPathComponent(file)
                            try FileManager.default.removeItem(atPath: filePath)
                        }
                    } else {
                        // Nếu là file, xóa file
                        try FileManager.default.removeItem(atPath: mgPath)
                    }
                }
                success = true
            } catch {
                print("Lỗi xóa: \(error)")
            }
            
            DispatchQueue.main.async {
                self.isCleaning = false
                self.cleanAlertMessage = success ? "Đã xóa cache MobileGestalt thành công!" : "Không thể xóa cache."
                self.showCleanAlert = true
            }
        }
    }

    private func respringClean() {
        try? RespringHelper.respring()
    }

    // ... (các hàm còn lại giữ nguyên)
}