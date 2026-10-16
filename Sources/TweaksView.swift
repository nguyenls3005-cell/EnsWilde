import SwiftUI

struct TweaksView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        PosterBoardView()
                    } label: {
                        Label("Custom Wallpapers", systemImage: "photo.on.rectangle")
                    }
                    NavigationLink {
                        KeypadView()
                    } label: {
                        Label("Dialer Themer", systemImage: "phone.circle")
                    }
                } header: {
                    Label("Theming", systemImage: "paintbrush")
                        .font(.subheadline.bold())
                }

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
                    NavigationLink {
                        OperationsView()
                    } label: {
                        Label("File Operations", systemImage: "folder")
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