import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @State private var path = NavigationPath()

    @AppStorage("manualCacheEditorEnabled") private var manualCacheEditorEnabled: Bool = false

    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner
    @ObservedObject var walletStore: AppleWalletStore
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var featureFlagsStore: FeatureFlagsStore
    var onNavigateToApply: (() -> Void)? = nil

    init(
        themeStore: PasscodeThemeStore,
        toolStore: ToolStore,
        toolRunner: ToolRunner,
        walletStore: AppleWalletStore,
        featureFlagsStore: FeatureFlagsStore,
        onNavigateToApply: (() -> Void)? = nil
    ) {
        self.themeStore = themeStore
        self.toolStore = toolStore
        self.toolRunner = toolRunner
        self.walletStore = walletStore
        self.featureFlagsStore = featureFlagsStore
        self.onNavigateToApply = onNavigateToApply
    }
