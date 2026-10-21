import SwiftUI

struct ConfigView: View {
    @ObservedObject var toolStore: ToolStore
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @AppStorage("ConfigFootnoteText") private var footnoteText: String = ""
    @AppStorage("ConfigSupervised") private var supervised: Bool = false
    @State private var showSavedAlert = false

    var body: some View {
        Form {
            Section(header: Text("Config Tweaks")) {
                Toggle("Enable Tweak", isOn: $toolStore.configTweaksEnabled)
            }
            Section(header: Text("Lock Screen Footnote")) {
                TextField("Footnote text", text: $footnoteText).autocorrectionDisabled()
            }
            Section(header: Text("Supervision")) {
                Toggle("Enable Supervision", isOn: $supervised)
            }
            Section {
                Button {
                    showApplyTab = true
                    showSavedAlert = true
                } label: {
                    HStack { Image(systemName: "square.and.arrow.down"); Text("Apply Save Changes").font(.headline) }.frame(maxWidth: .infinity)
                }
                Button(role: .destructive) {
                    toolStore.configTweaksEnabled = false
                    footnoteText = ""
                    supervised = false
                } label: {
                    HStack { Image(systemName: "arrow.counterclockwise"); Text("Restore Save Changes").font(.headline) }.frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Config Tweaks")
    }
}