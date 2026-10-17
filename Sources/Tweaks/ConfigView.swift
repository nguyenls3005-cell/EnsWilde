import SwiftUI

struct ConfigView: View {
    @ObservedObject var store: ToolStore
    @State private var footnoteText: String = ""
    @State private var supervised: Bool = false
    @State private var showSupervisionAlert = false
    
    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("tool_config_tweaks", comment: ""))) {
                Toggle(isOn: $store.configTweaksEnabled) {
                    Text(NSLocalizedString("enable_tweak", comment: ""))
                }
            }
            
            Section(header: Text(NSLocalizedString("lock_screen_footnote", comment: ""))) {
                HStack {
                    Image(systemName: "textformat")
                    TextField(NSLocalizedString("custom_footnote_placeholder", comment: ""), text: $footnoteText)
                }
                
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "flashlight.off.fill")
                        Spacer()
                        Image(systemName: "camera.fill")
                    }
                    .padding()
                    Text(NSLocalizedString("swipe_up_to_open", comment: "")).font(.caption).padding(.bottom)
                }
                .frame(height: 150)
                .background(Color.black.opacity(0.5))
                .cornerRadius(12)
            }
            
            Section(header: Text(NSLocalizedString("supervision_title", comment: ""))) {
                Toggle(isOn: $supervised) {
                    Text(NSLocalizedString("enable_supervision", comment: ""))
                }
                .onChange(of: supervised) { newValue in
                    if newValue {
                        showSupervisionAlert = true
                        supervised = false
                    }
                }
            }
            
            Section {
                Button(action: { /* Logic của bạn */ }) {
                    Label(NSLocalizedString("apply_save_changes", comment: ""), systemImage: "square.and.arrow.down")
                }
                Button(action: { /* Logic của bạn */ }) {
                    Label(NSLocalizedString("restore_save_changes", comment: ""), systemImage: "arrow.counterclockwise").foregroundColor(.red)
                }
            }
        }
        .navigationTitle(NSLocalizedString("tool_config_tweaks", comment: ""))
        .alert(NSLocalizedString("supervision_warning_title", comment: ""), isPresented: $showSupervisionAlert) {
            Button(NSLocalizedString("alert_cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("i_understand", comment: ""), role: .destructive) { supervised = true }
        } message: {
            Text(NSLocalizedString("supervision_warning_message", comment: ""))
        }
    }
}