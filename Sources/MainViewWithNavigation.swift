import SwiftUI

enum NavigationTab {
    case home, settings, about
}

struct MainViewWithNavigation: View {
    @State private var selectedTab: NavigationTab = .home
    @StateObject private var themeStore = PasscodeThemeStore()
    @StateObject private var toolStore = ToolStore()
    @StateObject private var toolRunner = ToolRunner()
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ContentView(
                    themeStore: themeStore,
                    toolStore: toolStore,
                    toolRunner: toolRunner
                )
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(NavigationTab.home)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(NavigationTab.settings)

            NavigationStack {
                AboutView()
            }
            .tabItem { Label("About", systemImage: "info.circle.fill") }
            .tag(NavigationTab.about)
        }
        .tint(Color(hex: userTintColorHex))
    }
}