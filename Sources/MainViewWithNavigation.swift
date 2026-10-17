import SwiftUI
import UserNotifications

struct MainViewWithNavigation: View {
    @State private var selectedTab: NavigationTab = .home
    @StateObject private var themeStore = PasscodeThemeStore()
    @StateObject private var toolStore = ToolStore()
    @StateObject private var toolRunner = ToolRunner()
    @StateObject private var walletStore = AppleWalletStore()
    @StateObject private var featureFlagsStore = FeatureFlagsStore()
    
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @State private var tintRefreshID = UUID()
    
    // Theo dõi trực tiếp các Tweak đang bật
    private var isAnyTweakEnabled: Bool {
        toolStore.replaceMobileGestaltEnabled || toolStore.configTweaksEnabled || toolStore.disableSoundEnabled || toolStore.themesUIEnabled || toolStore.zPatchCustomEnabled || walletStore.appleWalletEnabled || themeStore.passcodeThemeEnabled || featureFlagsStore.featureFlagsEnabled
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ContentView(themeStore: themeStore, toolStore: toolStore, toolRunner: toolRunner, walletStore: walletStore, featureFlagsStore: featureFlagsStore)
            }.tabItem { Label(L("nav_home"), systemImage: "house.fill") }.tag(NavigationTab.home)
            
            NavigationStack { ThemeStoreView(themeStore: themeStore) }.tabItem { Label(L("nav_theme_store"), systemImage: "square.grid.2x2.fill") }.tag(NavigationTab.themeStore)
            
            NavigationStack { SettingsView() }.tabItem { Label(L("nav_settings"), systemImage: "gearshape.fill") }.tag(NavigationTab.settings)
            
            NavigationStack { AboutView() }.tabItem { Label("About", systemImage: "info.circle.fill") }.tag(NavigationTab.about)
            
            // Điều kiện hiện Tab Apply: Phải bật ShowApplyTab VÀ có ít nhất 1 Tweak đang bật
            if showApplyTab && isAnyTweakEnabled {
                ApplyTabView(toolStore: toolStore, toolRunner: toolRunner, walletStore: walletStore, themeStore: themeStore, featureFlagsStore: featureFlagsStore)
                .tabItem { Label(L("nav_apply"), systemImage: "checkmark.circle.fill") }
                .tag(NavigationTab.apply)
            }
        }
        .tint(Color(hex: userTintColorHex))
        .id(tintRefreshID)
        .onChange(of: userTintColorHex) { _ in applyTintColor() }
        .onChange(of: isAnyTweakEnabled) { newValue in
            // Nếu tắt hết tweak, tự văng về Home và ẩn tab
            if !newValue && selectedTab == .apply { selectedTab = .home }
        }
        .onAppear { applyTintColor() }
    }
    
    private func applyTintColor() {
        let uiColor = UIColor(Color(hex: userTintColorHex))
        UITabBar.appearance().tintColor = uiColor
        UINavigationBar.appearance().tintColor = uiColor
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { window.tintColor = uiColor }
        }
        tintRefreshID = UUID()
    }
}