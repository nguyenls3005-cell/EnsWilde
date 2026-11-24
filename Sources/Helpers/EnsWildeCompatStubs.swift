import SwiftUI
import UniformTypeIdentifiers
import Combine

// MARK: - Localization Environment

struct AppLanguage {
    static let current = AppLanguage()

    func text(_ key: String) -> String {
        key
    }

    func text(_ key: String, _ arg1: CVarArg) -> String {
        String(format: "%@ (%@)", key, String(describing: arg1))
    }

    func text(_ key: String, _ arg1: CVarArg, _ arg2: CVarArg) -> String {
        String(format: "%@ (%@, %@)", key, String(describing: arg1), String(describing: arg2))
    }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .current
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

// MARK: - Container Store

enum ContainerStore {
    static func resolveAppContainerPath(bundleID: String) -> String? {
        _ = bundleID
        return nil
    }

    static func isApplicationContainerPath(_ path: String) -> Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Custom Patch Compatibility

@MainActor
final class CustomPatchStore: ObservableObject {
    static let shared = CustomPatchStore()
    @Published var isApplying = false
}

struct CustomPatchApplyTask: Identifiable {
    let id = UUID()
    let title: String
}

struct CustomPatchView: View {
    @ObservedObject var store: CustomPatchStore

    init(store: CustomPatchStore = .shared) {
        self.store = store
    }

    var body: some View {
        EmptyView()
    }
}

// MARK: - File Browser & Document Picker

struct FileEntry: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
}

struct FileReplacementNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct FileBrowserView: View {
    let containerPath: String
    let title: String
    let bundleID: String?

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
            Text(containerPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .navigationTitle(title)
    }
}

struct FileDocumentPicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let copiesSelectedDocument: Bool
    let allowsMultipleSelection: Bool
    let onSelection: (Result<[URL], Error>) -> Void
    let onCancel: () -> Void

    init(
        allowedContentTypes: [UTType] = [.item],
        copiesSelectedDocument: Bool = true,
        allowsMultipleSelection: Bool = false,
        onSelection: @escaping (Result<[URL], Error>) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.allowedContentTypes = allowedContentTypes
        self.copiesSelectedDocument = copiesSelectedDocument
        self.allowsMultipleSelection = allowsMultipleSelection
        self.onSelection = onSelection
        self.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(
            forOpeningContentTypes: allowedContentTypes,
            asCopy: copiesSelectedDocument
        )
        controller.allowsMultipleSelection = allowsMultipleSelection
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        uiViewController.allowsMultipleSelection = allowsMultipleSelection
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: FileDocumentPicker

        init(_ parent: FileDocumentPicker) {
            self.parent = parent
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            parent.onSelection(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
