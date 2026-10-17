import SwiftUI

struct ContentView: View {
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner
    @ObservedObject var walletStore: AppleWalletStore
    @ObservedObject var featureFlagsStore: FeatureFlagsStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Gọi đúng tên HomeView như trong dự án gốc
            HomeView(store: toolStore) 
                .tabItem {
                    Label(NSLocalizedString("nav_home", comment: ""), systemImage: "house.fill")
                }
                .tag(0)
            
            ThemeStoreView(themeStore: themeStore)
                .tabItem {
                    Label(NSLocalizedString("nav_theme_store", comment: ""), systemImage: "square.grid.2x2.fill")
                }
                .tag(1)
            
            // Gọi đúng tham số SettingsView
            SettingsView(store: toolStore)
                .tabItem {
                    Label(NSLocalizedString("nav_settings", comment: ""), systemImage: "gearshape.fill")
                }
                .tag(2)
            
            // Sửa lỗi "About" thành key dịch
            AboutView()
                .tabItem {
                    Label(NSLocalizedString("nav_about", comment: ""), systemImage: "info.circle.fill")
                }
                .tag(3)
                
            // Giữ nguyên ApplyView
            ApplyView(store: toolStore, toolRunner: toolRunner)
                .tabItem {
                    Label(NSLocalizedString("nav_apply", comment: ""), systemImage: "checkmark.circle.fill")
                }
                .tag(4)
        }
        .accentColor(.orange)
    }
}