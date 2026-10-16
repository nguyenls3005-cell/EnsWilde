import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner

    @State private var path = NavigationPath()
    @State private var showApplySheet = false

    var body: some View {
        Form {
            exploitStatusSection
            tweaksSection
            applySection
        }
        .headerProminence(.increased)
        .navigationTitle("EnsWilde")
        .navigationDestination(for: String.self) { route in
            if route == "MobileGestalt" {
                MobileGestaltView(toolStore: toolStore)
            } else if route == "PasscodeTheme" {
                PasscodeThemeView(themeStore: themeStore)
            }
        }
        .sheet(isPresented: $showApplySheet) {
            applySheetContent
        }
    }

    @ViewBuilder
    private var exploitStatusSection: some View {
        Section(header: Text("Exploit")) {
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("bad_query")
                        .font(.subheadline.bold())
                    Text("Sandbox escape active (iOS 26.0 – 27.0b4)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var tweaksSection: some View {
        Section(header: Text("Tweaks")) {
            toolLink(
                value: "MobileGestalt",
                title: "MobileGestalt",
                subtitle: "Replace system MobileGestalt values",
                icon: "cpu",
                enabled: toolStore.replaceMobileGestaltEnabled
            )

            toolLink(
                value: "PasscodeTheme",
                title: "Passcode Theme",
                subtitle: "Waiting for exploit support",
                icon: "lock.rectangle",
                enabled: false   // Disabled — chờ exploit
            )
        }
    }

    @ViewBuilder
    private func toolLink(value: String, title: String, subtitle: String, icon: String, enabled: Bool) -> some View {
        if enabled {
            NavigationLink(value: value) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: icon)
                }
            }
        } else {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: icon)
                }
                Spacer()
                Image(systemName: "hourglass")
                    .foregroundStyle(.orange)
            }
            .opacity(0.5)
        }
    }

    @ViewBuilder
    private var applySection: some View {
        Section {
            Button {
                showApplySheet = true
            } label: {
                Label("Apply Tweaks", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var applySheetContent: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Run") {
                        Task {
                            await toolRunner.applyAll(store: toolStore, themeStore: themeStore)
                        }
                    }
                }
                if !toolRunner.logs.isEmpty {
                    Section(header: Text("Logs")) {
                        ForEach(toolRunner.logs, id: \.text) { line in
                            Text(line.text)
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                }
            }
            .navigationTitle("Apply")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { showApplySheet = false }
                }
            }
        }
    }
}