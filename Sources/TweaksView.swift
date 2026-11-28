import SwiftUI

struct TweaksView: View {
    @ObservedObject var toolStore: ToolStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        MobileGestaltView(toolStore: toolStore)
                    } label: {
                        Label("MobileGestalt", systemImage: "cpu")
                    }
                    NavigationLink {
                        ConfigView(toolStore: toolStore)
                    } label: {
                        Label("Config Tweaks", systemImage: "slider.horizontal.3")
                    }
                } header: {
                    Label("System", systemImage: "gear")
                        .font(.subheadline.bold())
                }
            }
            .navigationTitle("Tweaks")
        }
    }
}
