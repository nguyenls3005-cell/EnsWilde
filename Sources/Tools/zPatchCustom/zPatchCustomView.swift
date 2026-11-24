import SwiftUI
import UniformTypeIdentifiers

struct zPatchCustomView: View {
    @StateObject private var patchStore = zPatchStore()
    @State private var draftEnabled: Bool = false

    @State private var showAddSheet = false
    @State private var newBundleID: String = ""
    @State private var newRelativeDest: String = ""
    @State private var newSourcePath: String = ""
    @State private var showFileImporter = false

    @State private var showSavedPopup = false
    @State private var popupMessage = "Đã lưu thay đổi. Vui lòng qua tab Apply để áp dụng."
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var editingPatch: zPatchItem? = nil

    var body: some View {
        Form {
            Section(header: Text(L("tool_zpatch_custom"))) {
                Toggle(L("enable_tweak"), isOn: $draftEnabled)

                Button {
                    patchStore.saveChange(enableTweak: draftEnabled)
                    popupMessage = "Đã lưu thay đổi. Hãy qua tab Apply để áp dụng."
                    showSavedPopup = true
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Change")
                            .fontWeight(.semibold)
                    }
                }
            }

            Section(header: Text(L("section_patch_list"))) {
                Button("Add New Patch") {
                    resetForm()
                    showAddSheet = true
                }

                if !patchStore.patches.isEmpty {
                    ForEach(patchStore.patches) { patch in
                        patchRow(patch)
                    }
                }
            }

            Section(header: Text(L("section_info"))) {
                Text("Nhập Bundle ID và đường dẫn file đích (tự dò container qua fsHandlers hoặc /var/mobile/Containers/Data/Application/), chọn file nguồn, bấm Save Patch để backup lần đầu, bấm Save Change rồi qua tab Apply.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .headerProminence(.increased)
        .navigationTitle(L("tool_zpatch_custom"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            draftEnabled = patchStore.isTweakEnabled
        }
        .sheet(isPresented: $showAddSheet) {
            addPatchSheet
        }
        .alert("Thông báo", isPresented: $showSavedPopup) {
            Button("OK") {}
        } message: {
            Text(popupMessage)
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func patchRow(_ patch: zPatchItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { patch.isEnabled },
                    set: { _ in patchStore.togglePatch(patch) }
                ))
                .labelsHidden()

                VStack(alignment: .leading, spacing: 2) {
                    Text(patch.bundleID.isEmpty ? "Unknown Bundle" : patch.bundleID)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    Text("File nguồn: \(patch.sourcePath.split(separator: "/").last.map(String.init) ?? "Chưa chọn")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("→ \(patch.fullDestinationPath)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if patch.pendingRevert {
                        Text("Trạng thái: Chờ Revert ở tab Apply")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                    } else if patch.hasInitialBackup && patch.backupPath != nil {
                        Text("Backup lần đầu: Đã lưu")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    }
                }

                Spacer()
            }

            HStack(spacing: 12) {
                Spacer()
                Button {
                    patchStore.requestRevert(patch)
                    popupMessage = "Đã đánh dấu Revert cho \(patch.bundleID). Hãy qua tab Apply để khôi phục patch cũ."
                    showSavedPopup = true
                } label: {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                editPatch(patch)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                patchStore.requestRevert(patch)
                popupMessage = "Đã chọn Revert. Hãy qua tab Apply để áp dụng."
                showSavedPopup = true
            } label: {
                Label("Revert", systemImage: "arrow.uturn.backward")
            }

            Button(role: .destructive) {
                patchStore.removePatch(patch)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var addPatchSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Đích (Tự động ghép /var/mobile/Containers/Data/Application/)")) {
                    TextField("Bundle ID (vd: com.lemon.lvoverseas)", text: $newBundleID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("File đích (vd: Library/Cookies/Cookies.binarycookies)", text: $newRelativeDest)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !newBundleID.isEmpty || !newRelativeDest.isEmpty {
                        let preview = zPatchItem(
                            bundleID: newBundleID,
                            relativeDestPath: newRelativeDest,
                            sourcePath: newSourcePath
                        ).fullDestinationPath
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section(header: Text("File cần thay đổi")) {
                    Button {
                        showFileImporter = true
                    } label: {
                        HStack {
                            Text(newSourcePath.isEmpty ? "Chọn file nguồn" : (newSourcePath.split(separator: "/").last.map(String.init) ?? "Đã chọn"))
                                .foregroundStyle(newSourcePath.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "doc.badge.plus")
                        }
                    }
                }

                Section(header: Text(L("section_actions"))) {
                    Button(editingPatch != nil ? "Update Patch" : "Save Patch") {
                        savePatch()
                    }
                    .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty || newRelativeDest.trimmingCharacters(in: .whitespaces).isEmpty || newSourcePath.isEmpty)
                }
            }
            .navigationTitle(editingPatch != nil ? "Edit Patch" : "Add Patch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddSheet = false
                        resetForm()
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item, .data, .content],
                allowsMultipleSelection: false,
                onCompletion: handleFileImport
            )
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let patchDir = docsURL.appendingPathComponent("zPatchCustomFiles", isDirectory: true)
            let destURL = patchDir.appendingPathComponent(url.lastPathComponent)

            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try FileManager.default.createDirectory(at: patchDir, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: url, to: destURL)
                newSourcePath = destURL.path
            } catch {
                errorMessage = "Không thể import file: \(error.localizedDescription)"
                showErrorAlert = true
            }

        case .failure(let error):
            errorMessage = "Lỗi chọn file: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func savePatch() {
        let cleanBundle = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRel = newRelativeDest.trimmingCharacters(in: .whitespacesAndNewlines)

        if var editing = editingPatch {
            editing.bundleID = cleanBundle
            editing.relativeDestPath = cleanRel
            editing.sourcePath = newSourcePath
            patchStore.updatePatch(editing)
        } else {
            patchStore.saveNewPatch(
                bundleID: cleanBundle,
                relativeDestPath: cleanRel,
                sourcePath: newSourcePath
            )
        }
        showAddSheet = false
        resetForm()
    }

    private func editPatch(_ patch: zPatchItem) {
        editingPatch = patch
        newBundleID = patch.bundleID
        newRelativeDest = patch.relativeDestPath
        newSourcePath = patch.sourcePath
        showAddSheet = true
    }

    private func resetForm() {
        newBundleID = ""
        newRelativeDest = ""
        newSourcePath = ""
        editingPatch = nil
    }
}
