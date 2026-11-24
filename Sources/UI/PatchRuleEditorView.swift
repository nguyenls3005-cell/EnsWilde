import SwiftUI

struct PatchRuleEditorView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    let originalRule: PatchRule?
    let onSave: (PatchRule) -> Void

    @State private var bundleID: String
    @State private var relativePath: String
    @State private var replacementFilename: String
    @State private var replacementData: Data
    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var validationMessageKey: String?

    init(rule: PatchRule?, onSave: @escaping (PatchRule) -> Void) {
        originalRule = rule
        self.onSave = onSave
        _bundleID = State(initialValue: rule?.bundleID ?? "")
        _relativePath = State(initialValue: rule?.relativePath ?? "")
        _replacementFilename = State(initialValue: rule?.replacementFilename ?? "")
        _replacementData = State(initialValue: rule?.replacementData ?? Data())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("com.example.app", text: $bundleID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    TextField("Library/path/file", text: $relativePath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    Text(language.text("patch.destination"))
                } footer: {
                    Text(language.text("patch.bundle_not_uuid_footer"))
                }

                Section(language.text("patch.replacement_file")) {
                    Button {
                        showFileImporter = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: replacementFilename.isEmpty ? "doc.badge.plus" : "doc.fill")
                                .foregroundStyle(AppTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(replacementFilename.isEmpty
                                     ? language.text("patch.choose_file")
                                     : replacementFilename)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(language.text(replacementFilename.isEmpty
                                     ? "patch.replacement_required"
                                     : "patch.change_replacement"))
                                    .font(.caption)
                                    .foregroundStyle(replacementFilename.isEmpty ? Color.orange : Color.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(isImporting)
                    if isImporting {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(language.text("patch.importing_replacement"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !replacementFilename.isEmpty {
                        LabeledContent(
                            language.text("patch.file_size"),
                            value: ByteCountFormatter.string(
                                fromByteCount: Int64(replacementData.count),
                                countStyle: .file
                            )
                        )
                    }
                }

                if let validationMessageKey {
                    Section {
                        Label(language.text(validationMessageKey), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(language.text(originalRule == nil ? "patch.add_rule" : "patch.edit_rule"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("common.done"), action: save)
                        .disabled(isImporting)
                }
            }
            .sheet(isPresented: $showFileImporter) {
                FileDocumentPicker(
                    allowsMultipleSelection: false,
                    onSelection: { result in
                        showFileImporter = false
                        importFile(result)
                    },
                    onCancel: {
                        showFileImporter = false
                    }
                )
                .ignoresSafeArea()
            }
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        isImporting = true
        validationMessageKey = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let values = try url.resourceValues(
                    forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
                )
                guard values.isDirectory != true,
                      values.isSymbolicLink != true,
                      values.isRegularFile == true else {
                    throw PatchPackageError.invalidProject
                }
                let importedData = try Data(contentsOf: url, options: .mappedIfSafe)
                DispatchQueue.main.async {
                    replacementData = importedData
                    replacementFilename = url.lastPathComponent
                    isImporting = false
                }
            } catch let error as PatchPackageError {
                DispatchQueue.main.async {
                    validationMessageKey = error.localizationKey
                    isImporting = false
                }
            } catch {
                DispatchQueue.main.async {
                    validationMessageKey = "patch.error.invalid_project"
                    isImporting = false
                }
            }
        }
    }

    private func save() {
        do {
            let canonicalBundle = try PatchPathValidator.canonicalBundleIdentifier(bundleID)
            let canonicalPath = try PatchPathValidator.canonicalRelativePath(relativePath)
            guard !replacementFilename.isEmpty else { throw PatchPackageError.invalidProject }
            onSave(PatchRule(
                id: originalRule?.id ?? UUID(),
                bundleID: canonicalBundle,
                relativePath: canonicalPath,
                replacementFilename: replacementFilename,
                replacementData: replacementData
            ))
            dismiss()
        } catch let error as PatchPackageError {
            validationMessageKey = error.localizationKey
        } catch {
            validationMessageKey = "patch.error.invalid_project"
        }
    }
}
