import SwiftUI

struct ConfigView: View {
    @ObservedObject var toolStore: ToolStore
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @AppStorage("ConfigFootnoteText") private var footnoteText: String = ""
    @AppStorage("ConfigSupervised") private var supervised: Bool = false
    @AppStorage("ConfigOrgName") private var orgName: String = ""

    @State private var isApplying = false
    @State private var saveTask: Task<Void, Never>?
    @State private var showSavedAlert = false
    @State private var showRestoredAlert = false

    var body: some View {
        Form {
            Section(header: Text(L("config_tweaks_title"))) {
                Toggle(L("config_enable_tweak"), isOn: $toolStore.configTweaksEnabled)
            }

            Section(header: Text(L("config_lock_screen_footnote"))) {
                TextField(L("config_footnote_placeholder"), text: $footnoteText)
                    .autocorrectionDisabled()

                if !footnoteText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("config_preview")).font(.caption).foregroundStyle(.secondary)
                        Text(footnoteText)
                            .font(.body)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                    }
                }
            }

            Section(header: Text(L("config_supervision_title"))) {
                Toggle(L("config_enable_supervision"), isOn: $supervised)

                if supervised {
                    TextField(L("config_org_placeholder"), text: $orgName)
                        .autocorrectionDisabled()

                    if !orgName.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("config_preview")).font(.caption).foregroundStyle(.secondary)
                            Text(orgName)
                                .font(.body)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                        }
                    }
                }
            }

            Section {
                Button {
                    applyConfig()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text(L("config_apply_save")).font(.headline)
                    }.frame(maxWidth: .infinity)
                }
                .disabled(isApplying)

                Button(role: .destructive) {
                    footnoteText = ""
                    supervised = false
                    orgName = ""
                    GLOBAL_LOG.step("Đã đặt lại Config Tweaks.")
                    showRestoredAlert = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text(L("config_restore_save")).font(.headline)
                    }.frame(maxWidth: .infinity)
                }
                .disabled(isApplying)
            }
        }
        .navigationTitle(L("config_tweaks_title"))
        .alert(L("saved_title"), isPresented: $showSavedAlert) {
            Button(L("alert_ok")) {}
        } message: {
            Text(L("config_saved_message"))
        }
        .alert(L("config_restored_title"), isPresented: $showRestoredAlert) {
            Button(L("alert_ok")) {}
        } message: {
            Text(L("config_restored_message"))
        }
        .onDisappear {
            saveTask?.cancel()
            isApplying = false
        }
    }

    private func applyConfig() {
        guard !isApplying else { return }
        isApplying = true
        GLOBAL_LOG.step("Đang áp dụng Config Tweaks...")

        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }

            GLOBAL_LOG.step("Đang ghi dữ liệu vào hệ thống...")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }

            showApplyTab = true
            isApplying = false
            GLOBAL_LOG.success("Lưu Config thành công!")
            showSavedAlert = true
        }
    }
}
