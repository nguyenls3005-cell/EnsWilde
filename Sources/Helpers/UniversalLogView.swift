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
    var statusText: String? = nil
    var isRunning: Bool = false
    var isSuccess: Bool = false
    var isError: Bool = false
    var allLogText: String? = nil

    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            statusIcon

            Text(displayText)
                .font(.footnote)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                UIPasteboard.general.string = combinedLogText()
                withAnimation {
                    copied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation {
                        copied = false
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "Copied" : "Copy Log")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(copied ? .green : .secondary)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.borderless)
            .disabled(combinedLogText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.vertical, 2)
    }

    private func combinedLogText() -> String {
        let gText = log.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = (allLogText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !gText.isEmpty && !extra.isEmpty && !gText.contains(extra) {
            return gText + "\n" + extra
        }
        return !gText.isEmpty ? gText : extra
    }

    private var displayText: String {
        if let custom = statusText?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        let line = UniversalLogStore.currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty {
            return line
        }
        let fallback = log.latestLine
        return fallback.isEmpty ? "Ready to apply." : fallback
    }

    private var textColor: Color {
        if isError || UniversalLogStore.state == .error {
            return .red
        }
        if isRunning || UniversalLogStore.state == .running || isSuccess || UniversalLogStore.state == .success {
            return .primary
        }
        return .secondary
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isRunning || UniversalLogStore.state == .running {
            ProgressView()
                .controlSize(.small)
                .tint(Color(hex: UserDefaults.standard.string(forKey: "EnsWilde.userTintColor") ?? "#ef9f76"))
        } else if isError || UniversalLogStore.state == .error {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        } else if isSuccess || UniversalLogStore.state == .success {
            Image(systemName: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
