import SwiftUI

struct TweaksView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        MobileGestaltView(toolStore: ToolStore())
                    } label: {
                        Label("MobileGestalt", systemImage: "cpu")
                    }
                    NavigationLink {
                        ConfigView()
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