import SwiftUI

struct ConfigView: View {
    @ObservedObject var store: ToolStore
    @State private var footnoteText: String = ""
    @State private var supervised: Bool = false
    @State private var showSupervisionAlert = false
    
    var body: some View {
        List {
            Section(header: Text("tool_config_tweaks")) {
                Toggle(isOn: $store.configTweaksEnabled) {
                    Text("enable_tweak")
                }
            }
            
            Section(header: Text("lock_screen_footnote")) {
                HStack {
                    Image(systemName: "textformat")
                    TextField("custom_footnote_placeholder", text: $footnoteText)
                }
                
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "flashlight.off.fill")
                        Spacer()
                        Image(systemName: "camera.fill")
                    }
                    .padding()
                    Text("swipe_up_to_open").font(.caption).padding(.bottom)
                }
                .frame(height: 150)
                .background(Color.black.opacity(0.5))
                .cornerRadius(12)
            }
            
            Section(header: Text("supervision_title")) {
                Toggle(isOn: $supervised) {
                    Text("enable_supervision")
                }
                .onChange(of: supervised) { newValue in
                    if newValue {
                        showSupervisionAlert = true
                        supervised = false
                    }
                }
            }
            
            Section {
                Button(action: { /* Apply logic */ }) {
                    Label("apply_save_changes", systemImage: "square.and.arrow.down")
                }
                Button(action: { /* Restore logic */ }) {
                    Label("restore_save_changes", systemImage: "arrow.counterclockwise").foregroundColor(.red)
                }
            }
        }
        .navigationTitle("tool_config_tweaks")
        .alert("supervision_warning_title", isPresented: $showSupervisionAlert) {
            Button("alert_cancel", role: .cancel) { }
            Button("i_understand", role: .destructive) { supervised = true }
        } message: {
            Text("supervision_warning_message")
        }
    }
}