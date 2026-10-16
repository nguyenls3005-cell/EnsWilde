import SwiftUI

struct DisableSoundView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @AppStorage("DisableDisclosureSoundEnabled") private var enabled: Bool = false
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @State private var showSavedAlert = false

    var body: some View {
        Form {
            Section(header: Text(L("tool_disable_sound"))) {
                Toggle(L("enable_tweak"), isOn: $enabled)
            }

            Section {
                Button {
                    showApplyTab = true
                    showSavedAlert = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save Changes")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .disabled(!enabled)
            }
        }
        .headerProminence(.increased)
        .navigationTitle(L("tool_disable_sound"))
        .navigationBarTitleDisplayMode(.inline)
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK") {}
        } message: {
            Text("Tab Apply đã được mở. Chuyển sang tab Apply để áp dụng.")
        }
    }
}