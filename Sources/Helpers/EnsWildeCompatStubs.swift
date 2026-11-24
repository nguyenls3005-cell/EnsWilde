import SwiftUI
import Combine

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
