import SwiftUI
import UIKit

enum UniversalLogState: Equatable {
    case idle
    case running
    case success
    case error
}

private enum UniversalLogStore {
    @MainActor static var state: UniversalLogState = .idle
    @MainActor static var currentLine: String = ""
}

extension LogModel {
    private func postMain(_ block: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                block()
            }
        } else {
            DispatchQueue.main.async {
                block()
            }
        }
    }

    func step(_ message: String) {
        postMain {
            UniversalLogStore.state = .running
            UniversalLogStore.currentLine = message
            self.append("[STEP] \(message)")
        }
    }

    func success(_ message: String) {
        postMain {
            UniversalLogStore.state = .success
            UniversalLogStore.currentLine = message
            self.append("[SUCCESS] \(message)")
        }
    }

    func error(_ message: String) {
        postMain {
            UniversalLogStore.state = .error
            UniversalLogStore.currentLine = message
            self.append("[ERROR] \(message)")
        }
    }

    var latestLine: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let last = trimmed.components(separatedBy: .newlines).last {
            return last
        }
        return ""
    }
}

struct UniversalLogView: View {
    @ObservedObject private var log = GLOBAL_LOG
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
                UIPasteboard.general.string = log.text
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
            .disabled(log.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var currentState: UniversalLogState {
        UniversalLogStore.state
    }

    private var displayText: String {
        let line = UniversalLogStore.currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty {
            return line
        }
        let fallback = log.latestLine
        return fallback.isEmpty ? "Sẵn sàng" : fallback
    }

    private var textColor: Color {
        switch currentState {
        case .idle:
            return .secondary
        case .running, .success:
            return .primary
        case .error:
            return .red
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch currentState {
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
}
