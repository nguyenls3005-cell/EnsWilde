import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var store: ToolStore
    @State private var showingPairingFilePicker = false
    @State private var showingBackupFilePicker = false
    
    var body: some View {
        List {
            // MARK: - Connection Status
            Section(header: Text(NSLocalizedString("connection_status", comment: ""))) {
                HStack {
                    // Đã sửa lại dùng đúng biến isPairingFileValid trong log
                    Image(systemName: store.isPairingFileValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(store.isPairingFileValid ? .green : .red)
                    Text(NSLocalizedString("pairing_file", comment: ""))
                    Spacer()
                    Text(store.isPairingFileValid ? NSLocalizedString("status_ready", comment: "") : NSLocalizedString("status_not_ready", comment: ""))
                        .foregroundColor(store.isPairingFileValid ? .green : .red)
                }
                
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("LocalDevVPN") // Giữ nguyên tên app
                    Spacer()
                    Text(NSLocalizedString("status_ready", comment: "")).foregroundColor(.green)
                }
            }
            
            // MARK: - Pairing File
            Section(header: Text(NSLocalizedString("pairing_file", comment: ""))) {
                Button(action: { showingPairingFilePicker = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text(NSLocalizedString("button_reset_pairing", comment: ""))
                    }
                    .foregroundColor(.red)
                }
            }
            
            // MARK: - Backup
            Section(header: Text(NSLocalizedString("backup_title", comment: ""))) {
                if MobileGestaltBackupManager.shared.hasBackup {
                    HStack {
                        Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                        Text(NSLocalizedString("backup_available", comment: "")).font(.headline)
                    }
                    HStack {
                        Text(NSLocalizedString("backup_date", comment: ""))
                        Spacer()
                        Text(MobileGestaltBackupManager.shared.backupDate ?? "").foregroundColor(.secondary)
                    }
                    HStack {
                        Text(NSLocalizedString("backup_size", comment: ""))
                        Spacer()
                        Text(MobileGestaltBackupManager.shared.backupSize ?? "").foregroundColor(.secondary)
                    }
                    
                    Button(action: { MobileGestaltBackupManager.shared.createBackup() }) {
                        Label(NSLocalizedString("backup_now", comment: ""), systemImage: "square.and.arrow.down")
                    }
                    Button(action: { showingBackupFilePicker = true }) {
                        Label(NSLocalizedString("backup_import", comment: ""), systemImage: "square.and.arrow.down.on.square")
                    }
                    Button(action: { MobileGestaltBackupManager.shared.deleteBackup() }) {
                        Label(NSLocalizedString("backup_delete", comment: ""), systemImage: "trash").foregroundColor(.red)
                    }
                } else {
                    Text(NSLocalizedString("backup_none", comment: ""))
                    Text(NSLocalizedString("backup_none_desc", comment: "")).font(.caption).foregroundColor(.secondary)
                    Button(action: { MobileGestaltBackupManager.shared.createBackup() }) {
                        Label(NSLocalizedString("backup_now", comment: ""), systemImage: "square.and.arrow.down")
                    }
                }
            }
            
            // MARK: - Language
            Section(header: Text(NSLocalizedString("settings_language", comment: ""))) {
                NavigationLink(destination: LanguageSettingsView()) {
                    HStack {
                        Image(systemName: "globe")
                        Text(NSLocalizedString("settings_language", comment: ""))
                    }
                }
            }
            
            // MARK: - App Info
            Section(header: Text(NSLocalizedString("settings_app_info", comment: ""))) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("EnsWilde")
                    Spacer()
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Image(systemName: "iphone")
                    Text(NSLocalizedString("app_ios", comment: ""))
                    Spacer()
                    Text(UIDevice.current.systemVersion).foregroundColor(.secondary)
                }
                HStack {
                    Image(systemName: "iphone.gen3")
                    Text(NSLocalizedString("app_device", comment: ""))
                    Spacer()
                    Text(UIDevice.current.model).foregroundColor(.secondary)
                }
                Text(NSLocalizedString("app_info_footer", comment: "")).font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle(NSLocalizedString("nav_settings", comment: ""))
    }
}