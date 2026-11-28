import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct zPatchCustomView: View {
    @ObservedObject private var patchStore = zPatchStore.shared
    var onNavigateToApply: (() -> Void)? = nil

    @State private var draftEnabled: Bool = false
    @State private var isBusy: Bool = false
    @State private var actionTask: Task<Void, Never>?

    @State private var showAddSheet = false
    @State private var showAppPicker = false
    @State private var showEnsPicker = false

    @State private var selectedAppName: String = ""
    @State private var selectedAppIcon: UIImage? = nil

    @State private var newBundleID: String = ""
    @State private var newRelativeDest: String = ""
    @State private var newSourcePath: String = ""
    @State private var showDocumentPicker = false

    @State private var showSavedPopup = false
    @State private var popupMessage = "Đã lưu thay đổi. Bạn có thể tự chuyển sang tab Apply để áp dụng."
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var editingPatch: zPatchItem? = nil

    var body: some View {
        Form {
            Section(header: Text("zPatch Custom")) {
                Toggle(L("enable_tweak"), isOn: Binding(
                    get: { draftEnabled },
                    set: { newValue in
                        draftEnabled = newValue
                        patchStore.setTweakEnabledImmediate(newValue)
                    }
                ))

                UniversalLogView()
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)

                HStack(spacing: 10) {
                    Button {
                        applySaveChange()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save Change")
                                .font(.subheadline.weight(.semibold))
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .disabled(isBusy)

                    Spacer()

                    Button {
                        showEnsPicker = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import .ens")
                                .font(.caption.weight(.semibold))
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                }
            }

            Section(header: Text(L("section_patch_list"))) {
                Button("Add New Patch") {
                    resetForm()
                    showAddSheet = true
                }
                .disabled(isBusy)

                if !patchStore.patches.isEmpty {
                    ForEach(patchStore.patches) { patch in
                        patchRow(patch)
                    }
                }
            }

            Section(header: Text(L("section_info"))) {
                Text("Bật/tắt Enable Tweak rồi bấm Save Change để lưu. Import .ens sẽ áp dụng ngay; hoặc tự chuyển qua tab Apply để áp dụng danh sách.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .headerProminence(.increased)
        .navigationTitle("zPatch Custom")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            patchStore.ensureLoaded()
            draftEnabled = patchStore.isTweakEnabled
        }
        .onDisappear {
            actionTask?.cancel()
            isBusy = false
        }
        .sheet(isPresented: $showAddSheet) {
            addPatchSheet
        }
        .sheet(isPresented: $showEnsPicker) {
            zPatchDocumentPicker(
                onPick: { url in
                    handleImportedEns(url)
                },
                onError: { msg in
                    GLOBAL_LOG.error("Import .ens lỗi: \(msg)")
                    errorMessage = msg
                    showErrorAlert = true
                }
            )
        }
        .alert("Thông báo", isPresented: $showSavedPopup) {
            Button("OK", role: .cancel) {
                showSavedPopup = false
            }
        } message: {
            Text(popupMessage)
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func applySaveChange() {
        guard !isBusy else { return }
        isBusy = true
        let enabledSnapshot = draftEnabled
        GLOBAL_LOG.step("Đang lưu thay đổi zPatch Custom...")

        actionTask?.cancel()
        actionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }

            patchStore.saveChange(enableTweak: enabledSnapshot)
            UserDefaults.standard.set(true, forKey: "ShowApplyTab")
            let msg = enabledSnapshot
                ? "Đã bật và lưu thay đổi. Bạn có thể tự chuyển sang tab Apply để áp dụng."
                : "Đã tắt và lưu thay đổi. Bạn có thể tự chuyển sang tab Apply để áp dụng."

            isBusy = false
            popupMessage = msg
            GLOBAL_LOG.success(msg)
            showSavedPopup = true
        }
    }

    private func handleImportedEns(_ url: URL) {
        guard !isBusy else { return }
        isBusy = true
        GLOBAL_LOG.step("Đang import gói .ens: \(url.lastPathComponent)...")

        actionTask?.cancel()
        actionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }

            switch patchStore.importEnsAndApplyNow(from: url) {
            case .success(let bundle):
                draftEnabled = patchStore.isTweakEnabled
                let msg = "Đã import & chạy ngay .ens cho \(bundle.appName) (\(bundle.bundleID))."
                isBusy = false
                popupMessage = msg
                GLOBAL_LOG.success(msg)
                showSavedPopup = true
            case .failure(let err):
                let errMsg = "Import .ens lỗi: \(err.localizedDescription)"
                isBusy = false
                errorMessage = errMsg
                GLOBAL_LOG.error(errMsg)
                showErrorAlert = true
            }
        }
    }

    private func requestRevertPatch(_ patch: zPatchItem) {
        guard !isBusy else { return }
        isBusy = true
        GLOBAL_LOG.step("Đang đánh dấu Revert cho \(patch.bundleID)...")

        actionTask?.cancel()
        actionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }

            patchStore.requestRevert(patch)
            let msg = "Đã chọn Revert cho \(patch.bundleID). Bạn có thể tự chuyển qua tab Apply để khôi phục về patch cũ."
            isBusy = false
            popupMessage = msg
            GLOBAL_LOG.success(msg)
            showSavedPopup = true
        }
    }

    private func patchRow(_ patch: zPatchItem) -> some View {
        let meta = resolvedMeta(for: patch.bundleID)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { patch.isEnabled },
                    set: { _ in patchStore.togglePatch(patch) }
                ))
                .labelsHidden()
                .fixedSize()
                .disabled(isBusy)

                zPatchAppIconBadge(icon: meta.icon)

                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(patch.bundleID.isEmpty ? "Unknown Bundle" : patch.bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("File nguồn: \(patch.sourcePath.isEmpty ? "Chưa chọn" : (patch.sourcePath.split(separator: "/").last.map(String.init) ?? "Đã chọn"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("→ \(patch.fastPreviewPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if patch.pendingRevert {
                        Text("Trạng thái: Đã chọn Revert -- qua tab Apply để khôi phục")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else if patch.hasInitialBackup && patch.backupPath != nil {
                        Text("Backup lần đầu: Đã lưu")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    editPatch(patch)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                    .font(.caption.weight(.medium))
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)

                Button {
                    triggerExport(for: patch, appName: meta.name, icon: meta.icon)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export .ens")
                    }
                    .font(.caption.weight(.medium))
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)

                Button {
                    requestRevertPatch(patch)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Revert")
                    }
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isBusy)

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    patchStore.removePatch(patch)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .disabled(isBusy)
            }
        }
        .padding(.vertical, 6)
    }

    private func triggerExport(for patch: zPatchItem, appName: String, icon: UIImage?) {
        GLOBAL_LOG.step("Đang xuất file .ens cho \(patch.bundleID)...")
        Task.detached(priority: .userInitiated) {
            let result = zPatchStore.shared.exportEnsFile(for: patch, appName: appName, icon: icon)
            await MainActor.run {
                switch result {
                case .success(let url):
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        let msg = "Không tìm thấy file .ens vừa xuất."
                        GLOBAL_LOG.error(msg)
                        errorMessage = msg
                        showErrorAlert = true
                        return
                    }
                    GLOBAL_LOG.success("Đã xuất file .ens: \(url.lastPathComponent)")
                    presentActivityVC(for: url)
                case .failure(let err):
                    GLOBAL_LOG.error("Xuất .ens lỗi: \(err.localizedDescription)")
                    errorMessage = err.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }

    private func presentActivityVC(for fileURL: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let topVC = topMostViewController() else {
                errorMessage = "Không mở được bảng chia sẻ."
                showErrorAlert = true
                return
            }
            let ac = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            if let pop = ac.popoverPresentationController {
                pop.sourceView = topVC.view
                pop.sourceRect = CGRect(
                    x: topVC.view.bounds.midX,
                    y: topVC.view.bounds.midY,
                    width: 0,
                    height: 0
                )
                pop.permittedArrowDirections = []
            }
            topVC.present(ac, animated: true)
        }
    }

    private func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let root = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
            ?? scenes.flatMap(\.windows).first?.rootViewController
        var cur = root
        while let presented = cur?.presentedViewController {
            cur = presented
        }
        return cur
    }

    private var addPatchSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Đích (Tự động ghép /var/mobile/Containers/Data/Application/)")) {
                    HStack(spacing: 10) {
                        zPatchAppIconBadge(icon: selectedAppIcon)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedAppName.isEmpty
                                 ? (newBundleID.split(separator: ".").last.map(String.init) ?? "Chưa chọn app")
                                 : selectedAppName)
                                .font(.subheadline.weight(.semibold))
                            Text(newBundleID.isEmpty ? "Nhập hoặc chọn Bundle ID" : newBundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Bundle ID (vd: com.lemon.lvoverseas)", text: $newBundleID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button {
                            showAppPicker = true
                        } label: {
                            Text("Chọn từ danh sách")
                                .font(.caption.weight(.semibold))
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(.bordered)
                    }

                    TextField("File đích (vd: Library/Cookies/Cookies.binarycookies)", text: $newRelativeDest)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !newBundleID.isEmpty || !newRelativeDest.isEmpty {
                        let preview = zPatchItem(
                            bundleID: newBundleID,
                            relativeDestPath: newRelativeDest,
                            sourcePath: newSourcePath
                        ).fastPreviewPath
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section(header: Text("File cần thay đổi")) {
                    Button {
                        showDocumentPicker = true
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
            .sheet(isPresented: $showAppPicker) {
                AppPickerScannerView(selectedBundleID: $newBundleID) { picked in
                    selectedAppName = picked.name
                    selectedAppIcon = picked.icon
                    patchStore.registerAppMeta(bundleID: picked.bundleID, appName: picked.name, icon: picked.icon)
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                zPatchDocumentPicker(
                    onPick: { url in
                        importSourceURL(url)
                    },
                    onError: { msg in
                        errorMessage = msg
                        showErrorAlert = true
                    }
                )
            }
        }
    }

    private func resolvedMeta(for bundleID: String) -> (name: String, icon: UIImage?) {
        let clean = zPatchItem.normalizedBundleID(bundleID)
        let name = patchStore.cachedAppName(for: clean)
            ?? (clean.isEmpty ? "Unknown Bundle" : (clean.split(separator: ".").last.map(String.init) ?? clean))
        let icon = patchStore.cachedAppIcon(for: clean)
        return (name: name, icon: icon)
    }

    private func importSourceURL(_ url: URL) {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let patchDir = docsURL.appendingPathComponent("zPatchCustomFiles", isDirectory: true)
        let safeName = url.lastPathComponent.isEmpty ? "imported_file.bin" : url.lastPathComponent
        let destURL = patchDir.appendingPathComponent(safeName)

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
            let data = try Data(contentsOf: url)
            try data.write(to: destURL, options: .atomic)
            newSourcePath = destURL.path
            GLOBAL_LOG.step("Đã chọn file nguồn: \(safeName)")
        } catch {
            GLOBAL_LOG.error("Không thể import file: \(error.localizedDescription)")
            errorMessage = "Không thể import file: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func savePatch() {
        let cleanBundle = zPatchItem.normalizedBundleID(newBundleID)
        let cleanRel = newRelativeDest.trimmingCharacters(in: .whitespacesAndNewlines)
        let srcPath = newSourcePath

        guard !cleanBundle.isEmpty, !cleanRel.isEmpty, !srcPath.isEmpty else { return }

        let nameToSave = selectedAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (cleanBundle.split(separator: ".").last.map(String.init) ?? cleanBundle)
            : selectedAppName
        patchStore.registerAppMeta(bundleID: cleanBundle, appName: nameToSave, icon: selectedAppIcon)

        let editingSnapshot = editingPatch
        showAddSheet = false
        resetForm()

        DispatchQueue.main.async {
            if var editing = editingSnapshot {
                editing.bundleID = cleanBundle
                editing.relativeDestPath = cleanRel
                editing.sourcePath = srcPath
                editing.cachedDestinationPath = editing.fastPreviewPath
                patchStore.updatePatch(editing)
                GLOBAL_LOG.success("Đã cập nhật patch cho \(cleanBundle)")
            } else {
                var item = zPatchItem(
                    bundleID: cleanBundle,
                    relativeDestPath: cleanRel,
                    sourcePath: srcPath,
                    hasInitialBackup: false,
                    isEnabled: true,
                    pendingRevert: false
                )
                item.cachedDestinationPath = item.fastPreviewPath
                patchStore.patches.append(item)
                patchStore.savePatches()
                GLOBAL_LOG.success("Đã thêm patch cho \(cleanBundle)")
            }
        }
    }

    private func editPatch(_ patch: zPatchItem) {
        let meta = resolvedMeta(for: patch.bundleID)
        editingPatch = patch
        newBundleID = patch.bundleID
        selectedAppName = meta.name
        selectedAppIcon = meta.icon
        newRelativeDest = patch.relativeDestPath
        newSourcePath = patch.sourcePath
        showAddSheet = true
    }

    private func resetForm() {
        newBundleID = ""
        selectedAppName = ""
        selectedAppIcon = nil
        newRelativeDest = ""
        newSourcePath = ""
        editingPatch = nil
    }
}

private struct zPatchAppIconBadge: View {
    let icon: UIImage?

    var body: some View {
        Group {
            if let icon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: 38, height: 38)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct zPatchDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onError: onError)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .data], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void
        var onError: (String) -> Void

        init(onPick: @escaping (URL) -> Void, onError: @escaping (String) -> Void) {
            self.onPick = onPick
            self.onError = onError
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onError("Không có file nào được chọn.")
                return
            }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
