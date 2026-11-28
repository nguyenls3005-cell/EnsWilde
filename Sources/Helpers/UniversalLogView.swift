import SwiftUI
import UIKit

enum LogStatus: Equatable {
    case idle
    case running
    case success
    case error
}

@MainActor
final class LogModel: ObservableObject {
    static let shared = LogModel()

    @Published var currentMessage: String = ""
    @Published var status: LogStatus = .idle
    @Published var entries: [String] = []

    nonisolated init() {}

    func step(_ message: String) {
        status = .running
        currentMessage = message
        entries.append("[STEP] \(message)")
        print("[GLOBAL_LOG][STEP] \(message)")
    }

    func success(_ message: String) {
        status = .success
        currentMessage = message
        entries.append("[SUCCESS] \(message)")
        print("[GLOBAL_LOG][SUCCESS] \(message)")
    }

    func error(_ message: String) {
        status = .error
        currentMessage = message
        entries.append("[ERROR] \(message)")
        print("[GLOBAL_LOG][ERROR] \(message)")
    }

    func clear() {
        status = .idle
        currentMessage = ""
        entries.removeAll()
    }

    func fullLogText() -> String {
        entries.joined(separator: "\n")
    }
}

let GLOBAL_LOG = LogModel.shared

struct UniversalLogView: View {
    @ObservedObject private var logModel = GLOBAL_LOG
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            statusIcon

            Text(displayText)
                .font(.caption)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                UIPasteboard.general.string = logModel.fullLogText()
                withAnimation {
                    copied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation {
                        copied = false
                    }
                }
            } label: {
                Image(systemName: copied ? "checkmark.doc.on.clipboard" : "doc.on.doc")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(copied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(logModel.entries.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch logModel.status {
        case .idle:
            Image(systemName: "terminal")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var displayText: String {
        if !logModel.currentMessage.isEmpty {
            return logModel.currentMessage
        }
        return "Sẵn sàng"
    }

    private var textColor: Color {
        switch logModel.status {
        case .idle:
            return .secondary
        case .running, .success:
            return .primary
        case .error:
            return .red
        }
    }
}
