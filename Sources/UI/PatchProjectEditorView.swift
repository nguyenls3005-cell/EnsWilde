import SwiftUI

struct PatchProjectEditorView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    let existingProject: PatchProject?
    let passwordIsProtected: Bool
    let initialDraft: PatchProjectDraft?
    let onSave: (PatchProject, String?) -> Void

    @State private var name: String
    @State private var author: String
    @State private var isPrivate: Bool
    @State private var bundleID: String
    @State private var bundleIdentifiers: [String]
    @State private var directories: [PatchDirectory]
    @State private var rules: [PatchRule]
    @State private var password = ""
    @State private var ruleEditor: PatchRuleEditorContext?
    @State private var validationMessageKey: String?

    init(
        existingProject: PatchProject?,
        passwordIsProtected: Bool,
        initialDraft: PatchProjectDraft? = nil,
        onSave: @escaping (PatchProject, String?) -> Void
    ) {
        self.existingProject = existingProject
        self.passwordIsProtected = passwordIsProtected
        self.initialDraft = initialDraft
        self.onSave = onSave
        _name = State(initialValue: existingProject?.name ?? initialDraft?.name ?? "")
        _author = State(initialValue: existingProject?.author ?? "")
        _isPrivate = State(initialValue: existingProject?.isPrivate ?? false)
        _bundleID = State(initialValue: initialDraft?.bundleIdentifiers.first ?? "")
        _bundleIdentifiers = State(
            initialValue: existingProject?.bundleIdentifiers
                ?? initialDraft?.bundleIdentifiers
                ?? []
        )
        _directories = State(
            initialValue: existingProject?.directories ?? initialDraft?.directories ?? []
        )
        _rules = State(initialValue: existingProject?.rules ?? initialDraft?.rules ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(language.text("patch.project")) {
                    TextField(language.text("patch.project_name"), text: $name)
                        .textInputAutocapitalization(.words)
                    TextField(language.text("patch.author_optional"), text: $author)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                if existingProject == nil {
                    Section {
                        if let capturedBundle = initialDraft?.bundleIdentifiers.first {
                            LabeledContent(language.text("patch.target_bundle")) {
                                Text(capturedBundle)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            TextField("com.example.app", text: $bundleID)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.body.monospaced())
                        }
                    } header: {
                        Text(language.text("patch.target_bundle"))
                    } footer: {
                        Text(language.text("patch.workspace_bundle_footer"))
                    }
                }

                if existingProject != nil || !rules.isEmpty || !directories.isEmpty {
                    Section {
                        ForEach(rules) { rule in
                            Button {
                                ruleEditor = PatchRuleEditorContext(rule: rule)
                            } label: {
                                HStack(spacing: 10) {
                                    ruleRow(rule)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(language.text("patch.edit_rule_hint"))
                        }
                        .onDelete { rules.remove(atOffsets: $0) }

                        if existingProject != nil {
                            Button {
                                ruleEditor = PatchRuleEditorContext(rule: nil)
                            } label: {
                                Label(language.text("patch.add_rule"), systemImage: "plus.circle.fill")
                            }
                        }
                        if !directories.isEmpty {
                            LabeledContent(language.text("patch.folders")) {
                                Text("\(directories.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text(language.text("patch.captured_content"))
                    } footer: {
                        Text(language.text("patch.workspace_edit_footer"))
                    }
                }

                Section {
                    if existingProject == nil {
                        SecureField(language.text("patch.password_optional"), text: $password)
                            .textContentType(.newPassword)
                    } else {
                        Label(
                            language.text(passwordIsProtected ? "patch.password_locked" : "patch.no_password"),
                            systemImage: passwordIsProtected ? "lock.fill" : "lock.open"
                        )
                    }
                } header: {
                    Text(language.text("patch.password"))
                } footer: {
                    Text(language.text(existingProject == nil
                        ? "patch.password_immutable_footer"
                        : "patch.password_existing_footer"))
                }

                Section {
                    Toggle(isOn: $isPrivate) {
                        Label(
                            language.text("patch.private"),
                            systemImage: "eye.slash.fill"
                        )
                    }
                    .disabled(existingProject != nil)
                } header: {
                    Text(language.text("patch.privacy"))
                } footer: {
                    Text(language.text(existingProject == nil
                        ? "patch.private_footer"
                        : "patch.private_existing_footer"))
                }

                if let validationMessageKey {
                    Section {
                        Label(language.text(validationMessageKey), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(language.text(existingProject == nil ? "patch.new" : "patch.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("common.done"), action: save)
                }
            }
            .sheet(item: $ruleEditor) { context in
                PatchRuleEditorView(rule: context.rule) { savedRule in
                    if let index = rules.firstIndex(where: { $0.id == savedRule.id }) {
                        rules[index] = savedRule
                    } else {
                        rules.append(savedRule)
                    }
                }
            }
        }
    }

    private func ruleRow(_ rule: PatchRule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rule.bundleID)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(rule.relativePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if rule.hasReplacement {
                Text(rule.replacementFilename)
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
            } else {
                Label(language.text("patch.replacement_required"), systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
    }

    private func save() {
        let projectName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectName.isEmpty, projectName.utf8.count <= 120 else {
            validationMessageKey = "patch.error.invalid_project"
            return
        }
        guard projectAuthor.utf8.count <= PatchPackageLimits.maximumAuthorBytes,
              !projectAuthor.unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains
              ) else {
            validationMessageKey = "patch.error.invalid_author"
            return
        }
        author = projectAuthor
        if existingProject == nil, isPrivate, password.isEmpty {
            validationMessageKey = "patch.error.private_password"
            return
        }
        if existingProject == nil, initialDraft == nil {
            do {
                let canonical = try PatchPathValidator.canonicalBundleIdentifier(bundleID)
                guard canonical == bundleID.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    throw PatchPackageError.invalidBundleIdentifier
                }
                bundleID = canonical
                bundleIdentifiers = [canonical]
            } catch let error as PatchPackageError {
                validationMessageKey = error.localizationKey
                return
            } catch {
                validationMessageKey = "patch.error.invalid_bundle"
                return
            }
        }
        guard !bundleIdentifiers.isEmpty || !rules.isEmpty || !directories.isEmpty else {
            validationMessageKey = "patch.error.invalid_project"
            return
        }
        guard let incompleteRule = rules.first(where: { !$0.hasReplacement }) else {
            saveCompleteProject(named: projectName)
            return
        }
        validationMessageKey = "patch.error.replacement_required"
        ruleEditor = PatchRuleEditorContext(rule: incompleteRule)
    }

    private func saveCompleteProject(named projectName: String) {
        let project = PatchProject(
            id: existingProject?.id ?? UUID(),
            name: projectName,
            author: author,
            isPrivate: isPrivate,
            createdAt: existingProject?.createdAt ?? Date(),
            updatedAt: Date(),
            bundleIdentifiers: bundleIdentifiers,
            directories: directories,
            rules: rules
        )
        do {
            try PatchPackageCodec.validate(project)
            onSave(project, existingProject == nil && !password.isEmpty ? password : nil)
            dismiss()
        } catch let error as PatchPackageError {
            validationMessageKey = error.localizationKey
        } catch {
            validationMessageKey = "patch.error.invalid_project"
        }
    }
}

private struct PatchRuleEditorContext: Identifiable {
    let id = UUID()
    let rule: PatchRule?
}
