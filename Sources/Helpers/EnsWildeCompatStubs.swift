import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - AppLanguage & Environment

struct AppLanguage: Equatable, Hashable, Sendable {
    var code: String = "en"

    static let english = AppLanguage(code: "en")
    static let vietnamese = AppLanguage(code: "vi")

    func text(_ key: String, _ args: CVarArg...) -> String {
        _ = args
        return key
    }
}

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .english
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}

// MARK: - ContainerStore

@MainActor
final class ContainerStore: ObservableObject {
    static let shared = ContainerStore()
    @Published var containers: [URL] = []
    @Published var selectedContainerURL: URL?
}

// MARK: - FileBrowserView & FileDocumentPicker

struct FileBrowserView<Content: View>: View {
    let rootURL: URL
    let content: (URL) -> Content

    init(
        rootURL: URL = URL(fileURLWithPath: "/"),
        @ViewBuilder content: @escaping (URL) -> Content = { _ in EmptyView() }
    ) {
        self.rootURL = rootURL
        self.content = content
    }

    var body: some View {
        content(rootURL)
    }
}

struct FileDocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onPick: ([URL]) -> Void
    let onCancel: (() -> Void)?

    init(
        contentTypes: [UTType] = [.item],
        allowsMultipleSelection: Bool = false,
        onPick: @escaping ([URL]) -> Void = { _ in },
        onCancel: (() -> Void)? = nil
    ) {
        self.contentTypes = contentTypes
        self.allowsMultipleSelection = allowsMultipleSelection
        self.onPick = onPick
        self.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        controller.allowsMultipleSelection = allowsMultipleSelection
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        uiViewController.allowsMultipleSelection = allowsMultipleSelection
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: FileDocumentPicker

        init(parent: FileDocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel?()
        }
    }
}

// MARK: - Custom Patch Compatibility

struct CustomPatchConfig {
    var enabled: Bool = false
}

@MainActor
final class CustomPatchStore: ObservableObject {
    static let shared = CustomPatchStore()
    @Published var isApplying = false
    @Published var config = CustomPatchConfig()
}

enum CustomPatchApplyTask {
    @discardableResult
    static func apply(
        store: Any? = nil,
        onLogUpdate: ((String) -> Void)? = nil
    ) async throws -> Bool {
        _ = store
        onLogUpdate?("Applying custom patch...")
        return true
    }

    @discardableResult
    static func apply(_ arguments: Any...) async throws -> Bool {
        _ = arguments
        return true
    }
}

struct CustomPatchView: View {
    @ObservedObject var store: CustomPatchStore

    init(store: CustomPatchStore = .shared) {
        self.store = store
    }

    init<ToolStore>(toolStore: ToolStore) {
        _ = toolStore
        self.store = .shared
    }

    var body: some View {
        EmptyView()
    }
}
