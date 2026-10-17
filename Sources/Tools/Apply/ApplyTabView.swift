import SwiftUI

struct ApplyTabView: View {
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner
    @ObservedObject var themeStore: PasscodeThemeStore

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Trạng thái")) {
                    HStack {
                        Image(systemName: stateIcon)
                            .foregroundStyle(stateColor)
                        Text(stateText)
                            .font(.subheadline)
                    }
                }

                Section(header: Text("Tweaks đang bật")) {
                    if !toolStore.replaceMobileGestaltEnabled
                        && !toolStore.configTweaksEnabled {
                        Text("Chưa có tweak nào được bật.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if toolStore.replaceMobileGestaltEnabled {
                        Label("MobileGestalt", systemImage: "cpu")
                    }
                    if toolStore.configTweaksEnabled {
                        Label("Config Tweaks", systemImage: "slider.horizontal.3")
                    }
                }

                Section {
                    Button {
                        Task {
                            await toolRunner.applyAll(store: toolStore, themeStore: themeStore)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Apply All").font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }

                    if case .running(let name) = toolRunner.state {
                        HStack {
                            ProgressView()
                            Text("Đang chạy: \(name)...")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !toolRunner.logs.isEmpty {
                    Section(header: Text("Log")) {
                        ForEach(Array(toolRunner.logs.enumerated()), id: \.offset) { _, line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Apply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !toolRunner.logs.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") {
                            toolRunner.resetLogs()
                        }
                    }
                }
            }
        }
    }

    private var stateIcon: String {
        switch toolRunner.state {
        case .idle: return "circle.dashed"
        case .running: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var stateColor: Color {
        switch toolRunner.state {
        case .idle: return .secondary
        case .running: return .blue
        case .success: return .green
        case .failed: return .red
        }
    }

    private var stateText: String {
        switch toolRunner.state {
        case .idle: return "Sẵn sàng"
        case .running(let name): return "Đang chạy: \(name)"
        case .success: return "Thành công"
        case .failed(let msg): return "Lỗi: \(msg)"
        }
    }
}