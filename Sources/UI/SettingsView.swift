import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var store: ToolStore
    @State private var showingPairingFilePicker = false
    @State private var showingBackupFilePicker = false
    
    var body: some View {
        List {
            // MARK: - System Status
            Section(header: Text("section_status")) {
                HStack {
                    Image(systemName: store.isPairingFileValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(store.isPairingFileValid ? .green : .red)
                    Text("system_status")
                    Spacer()
                    Text(store.isPairingFileValid ? "status_ready" : "status_not_ready")
                        .foregroundColor(store.isPairingFileValid ? .green : .red)
                }
            }
            
            // MARK: - Connection Status
            Section(header: Text("connection_status")) {
                HStack {
                    Image(systemName: store.isPairingFileValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(store.isPairingFileValid ? .green : .red)
                    Text("pairing_file")
                    Spacer()
                    Text(store.isPairingFileValid ? "status_ready" : "status_not_ready")
                        .foregroundColor(store.isPairingFileValid ? .green : .red)
                }
                
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("LocalDevVPN")
                    Spacer()
                    Text("status_ready").foregroundColor(.green)
                }
            }
            
            // MARK: - Pairing File
            Section(header: Text("pairing_file")) {
                Button(action: { showingPairingFilePicker = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("button_reset_pairing")
                    }
                    .foregroundColor(.red)
                }
            }
            
            // MARK: - MobileGestalt Backup
            Section(header: Text("backup_title")) {
                if MobileGestaltBackupManager.shared.hasBackup {
                    HStack {
                        Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                        Text("backup_available").font(.headline)
                    }
                    HStack {
                        Text("backup_date")
                        Spacer()
                        Text(MobileGestaltBackupManager.shared.backupDate ?? "").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("backup_size")
                        Spacer()
                        Text(MobileGestaltBackupManager.shared.backupSize ?? "").foregroundColor(.secondary)
                    }
                    
                    Button(action: { MobileGestaltBackupManager.shared.createBackup() }) {
                        Label("backup_now", systemImage: "square.and.arrow.down")
                    }
                    Button(action: { showingBackupFilePicker = true }) {
                        Label("backup_import", systemImage: "square.and.arrow.down.on.square")
                    }
                    Button(action: { MobileGestaltBackupManager.shared.deleteBackup() }) {
                        Label("backup_delete", systemImage: "trash").foregroundColor(.red)
                    }
                } else {
                    Text("backup_none")
                    Text("backup_none_desc").font(.caption).foregroundColor(.secondary)
                    Button(action: { MobileGestaltBackupManager.shared.createBackup() }) {
                        Label("backup_now", systemImage: "square.and.arrow.down")
                    }
                }
            }
            
            // MARK: - Language & Accent Color
            Section(header: Text("settings_language")) {
                NavigationLink(destination: LanguageSettingsView()) {
                    HStack {
                        Image(systemName: "globe")
                        Text("settings_language")
                    }
                }
            }
            
            // MARK: - App Info
            Section(header: Text("settings_app_info")) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("EnsWilde")
                    Spacer()
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Image(systemName: "iphone")
                    Text("app_ios")
                    Spacer()
                    Text(UIDevice.current.systemVersion).foregroundColor(.secondary)
                }
                HStack {
                    Image(systemName: "iphone.gen3")
                    Text("app_device")
                    Spacer()
                    Text(UIDevice.current.model).foregroundColor(.secondary)
                }
                Text("app_info_footer").font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle("nav_settings")
    }
}