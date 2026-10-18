import SwiftUI

struct MobileGestaltView: View {
    @ObservedObject var toolStore: ToolStore // Giữ nguyên nếu bạn cần dùng cho việc khác
    @StateObject private var store = GestaltStore.shared
    @State private var showResetAlert = false
    @State private var isLoading = true
    
    var body: some View {
        List {
            if isLoading {
                ProgressView("Đang tải MobileGestalt...")
            } else {
                // Ví dụ về các nút gạt (Bạn có thể thêm các nút khác tương tự)
                Section(header: Text("Hardware Features")) {
                    Toggle("Dynamic Island", isOn: store.mgKeyBinding([MGKey.island]))
                    Toggle("Always On Display", isOn: store.mgKeyBinding([MGKey.AOD, MGKey.AOTime]))
                    Toggle("Boot Chime", isOn: store.mgKeyBinding([MGKey.bootChime]))
                }
                
                Section(header: Text("iPadOS")) {
                    Toggle(isOn: store.mgTrollPadBinding()) {
                        VStack(alignment: .leading) {
                            Text("Enable iPadOS UI")
                            Text("⚠️ Có thể gây lỗi giao diện, treo máy. Đừng tắt 'Show Dock'.")
                                .font(.caption).foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle("MobileGestalt")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        applyTweaks()
                    } label: {
                        Label("Apply Tweaks", systemImage: "checkmark.circle")
                    }
                    
                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        Label("Reset Gestalt (Clear Cache)", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Xóa MobileGestalt Cache?", isPresented: $showResetAlert) {
            Button("Hủy", role: .cancel) {}
            Button("Xóa & Reset", role: .destructive) {
                clearCache()
            }
        } message: {
            Text("Sẽ xóa sạch cache. Bạn cần Respring để áp dụng.")
        }
        .onAppear {
            loadGestalt()
        }
    }
    
    private func loadGestalt() {
        let mgURL = MGURL.fsGestaltURL
        if !FileManager.default.isWritableFile(atPath: mgURL.path) {
            let res = BadQuery().grantAccess(atPath: mgURL.deletingLastPathComponent().path, toFileName: mgURL.lastPathComponent)
            if !res.0 {
                print("Không thể lấy quyền đọc/ghi.")
            }
        }
        
        if let dict = NSMutableDictionary(contentsOf: mgURL) {
            store.mgCurrentDict = dict
        }
        isLoading = false
    }
    
    private func applyTweaks() {
        Task {
            do {
                try await MobileGestaltApplyTask.applyGestalt(store: store)
                // Hiện thông báo thành công
                print("Apply thành công!")
            } catch {
                print("Lỗi Apply: \(error.localizedDescription)")
            }
        }
    }
    
    private func clearCache() {
        do {
            // Xóa file gốc và file backup
            try? FileManager.default.removeItem(at: MGURL.fsGestaltURL)
            try? FileManager.default.removeItem(at: MGURL.savedGestaltURL)
            // Reset dictionary trong bộ nhớ
            store.mgCurrentDict = NSMutableDictionary()
            
            print("Đã xóa sạch MobileGestalt. Hãy Respring!")
        }
    }
}