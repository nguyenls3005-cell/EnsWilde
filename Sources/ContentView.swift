import SwiftUI

struct ContentView: View {
    @StateObject var themeStore = PasscodeThemeStore()
    @StateObject var toolStore = ToolStore()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(store: toolStore)
                .tabItem {
                    Label("nav_home", systemImage: "house.fill")
                }
                .tag(0)
            
            ThemeStoreView(themeStore: themeStore)
                .tabItem {
                    Label("nav_theme_store", systemImage: "square.grid.2x2.fill")
                }
                .tag(1)
            
            SettingsView(store: toolStore)
                .tabItem {
                    Label("nav_settings", systemImage: "gearshape.fill")
                }
                .tag(2)
            
            AboutView()
                .tabItem {
                    Label("nav_about", systemImage: "info.circle.fill") // Đã sửa "About" thành "nav_about"
                }
                .tag(3)
                
            ApplyView(store: toolStore) // Nếu có tab Apply
                .tabItem {
                    Label("nav_apply", systemImage: "checkmark.circle.fill")
                }
                .tag(4)
        }
        .accentColor(.orange)
    }
}