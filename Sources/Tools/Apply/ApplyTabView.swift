import SwiftUI

struct ApplyTabView: View {
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner
    @ObservedObject var themeStore: PasscodeThemeStore

    @AppStorage("RespringAfterApply") private var respringAfterApply: Bool = true

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Tweaks").font(.headline).foregroundColor(.primary).padding(.bottom, 4)) {
                    if toolStore.replaceMobileGestaltEnabled {
                        Label("MobileGestalt", systemImage: "cpu")
                            .padding(.vertical, 4)
                    }
                    if toolStore.configTweaksEnabled {
                        Label("Config Tweaks", systemImage: "textformat")
                            .padding(.vertical, 4)
                    }
                    if !toolStore.replaceMobileGestaltEnabled && !toolStore.configTweaksEnabled {
                        Text("No tweaks enabled.")
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section(header: Text("Options").font(.headline).foregroundColor(.primary).padding(.bottom, 4)) {
                    Toggle(isOn: $respringAfterApply) {
                        Label("Respring after apply", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section {
                    Button {
                        Task {
                            await toolRunner.applyAll(store: toolStore, themeStore: themeStore)
                        }
                    } label: {
                        Text("Apply Enabled Tweaks")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if !toolRunner.logs.isEmpty {
                    Section(header: Text("Log").font(.headline)) {
                        ForEach(Array(toolRunner.logs.enumerated()), id: \.offset) { _, line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Apply")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}