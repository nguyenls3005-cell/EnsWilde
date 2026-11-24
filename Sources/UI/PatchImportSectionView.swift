import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum PatchPackagePickerPolicy {
    static let packageType = UTType(filenameExtension: "3105") ?? .data
    static let allowedContentTypes: [UTType] = [packageType, .data]
    static let copiesSelectedDocument = true
}

struct PatchImportSectionView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var draftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var store: PatchProjectStore

    @State private var showCreate = false
    @State private var showImporter = false

    var body: some View {
        Menu {
            Button {
                showCreate = true
            } label: {
                Label(language.text("patch.new"), systemImage: "doc.badge.plus")
            }
            Button {
                showImporter = true
            } label: {
                Label(language.text("patch.import"), systemImage: "square.and.arrow.down")
            }
        } label: {
            if store.isBusy {
                ProgressView()
            } else {
                Image(systemName: "plus")
            }
        }
        .disabled(store.isBusy)
        .accessibilityLabel(language.text("patch.add"))
        .sheet(isPresented: $showImporter) {
            FileDocumentPicker(
                allowedContentTypes: PatchPackagePickerPolicy.allowedContentTypes,
                copiesSelectedDocument: PatchPackagePickerPolicy.copiesSelectedDocument,
                allowsMultipleSelection: false,
                onSelection: { result in
                    showImporter = false
                    if case .success(let urls) = result, let url = urls.first {
                        store.importPackage(at: url)
                    }
                },
                onCancel: {
                    showImporter = false
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCreate) {
            PatchProjectEditorView(
                existingProject: nil,
                passwordIsProtected: false
            ) { project, password in
                store.create(project: project, password: password)
            }
        }
        .sheet(item: $draftCoordinator.request) { request in
            PatchProjectEditorView(
                existingProject: nil,
                passwordIsProtected: false,
                initialDraft: request.draft
            ) { project, password in
                store.create(project: project, password: password)
                draftCoordinator.clear()
            }
        }
        .onAppear {
            consumeExternalImport()
        }
        .onChange(of: draftCoordinator.importRequest?.id) { _ in
            consumeExternalImport()
        }
    }

    private func consumeExternalImport() {
        guard let request = draftCoordinator.importRequest else { return }
        draftCoordinator.clearImport()
        store.importPackage(from: request.source)
    }
}
