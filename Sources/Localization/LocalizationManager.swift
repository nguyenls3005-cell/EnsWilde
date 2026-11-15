//
//  LocalizationManager.swift
//  EnsWilde
//

import Foundation

/// Manager for handling localized strings
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "SelectedLanguage")
            loadStrings()
        }
    }

    @Published var availableLanguages: [LanguageInfo] = []

    private var strings: [String: String] = [:]

    // MARK: - Hardcoded Dictionary (100% Chống Lỗi)
    private let hardcodedStrings: [String: [String: String]] = [
        "en": [
            "nav_home": "Home", "nav_theme_store": "Theme Store", "nav_settings": "Settings", "nav_about": "About", "nav_apply": "Apply",
            "settings_run_test_header": "RUN TEST (WorseQuery Access)", "settings_run_test_btn": "Test MobileGestalt read/write permissions",
            "settings_respring_header": "RESPRING (NeoSpring)", "settings_respring_btn": "Respring Device", "settings_tunnel_status": "Tunnel Connection",
            "theme_store_repos": "Repositories", "theme_store_theme_count": "%d themes", "theme_store_by_author": "by %@",
            "theme_store_download_btn": "Download", "theme_store_json_url": "JSON URL", "theme_store_json_desc": "Paste a direct themes JSON or an index.",
            "translation_by": "%@ (%@) translation", "credit_community": "For support my project.", "credit_yang_support": "For supporting me during development",
            "credit_yang_original": "Original developer of EnsWilde", "credit_ls_new": "Developer of new EnsWilde", "credit_forcequit_badquery": "Bad_query exploit",
            "credit_johnny_airlift": "Airlift exploit", "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "Config tweak, new logic mobilegestalt",
            "credit_likepass_sound": "Disable Call Recording Sound (iOS 27)", "credit_little_34306_concept": "Original concept of disable call recording sound",
            "credit_yihooong_silent": "For the silent tone assets and replacement research.", "credit_kianuni_erosion": "Erosion-cn Developer - Write & Revert tweaks logic",
            "log_mcm_load_failed": "Could not load MCM APIs", "log_app_group_url_failed": "Could not get App Group URL for", "log_symlink_failed": "Symlink creation failed:",
            "log_query_failed": "Query creation failed", "log_xpc_error": "XPC Error: containermanagerd refused to grant token.", "log_kernel_token_failed": "Kernel refused to grant token",
            "log_consume_token_failed": "Consume token failed (errno:", "log_mcm_success": "Success via MCM Symlink", "log_fsgetpath_success": "Success via fsgetpath:",
            "log_fsgetpath_failed": "fsgetpath failed", "log_pointer_error": "Pointer error", "log_consume_errno": "Consume errno:"
        ],
        "vi": [
            "nav_home": "Trang chủ", "nav_theme_store": "Kho giao diện", "nav_settings": "Cài đặt", "nav_about": "Giới thiệu", "nav_apply": "Áp dụng",
            "settings_run_test_header": "CHẠY THỬ NGHIỆM (WorseQuery)", "settings_run_test_btn": "Kiểm tra quyền đọc/ghi MobileGestalt",
            "settings_respring_header": "RESPRING (NeoSpring)", "settings_respring_btn": "Khởi động lại SpringBoard", "settings_tunnel_status": "Kết nối Tunnel",
            "theme_store_repos": "Kho lưu trữ", "theme_store_theme_count": "%d giao diện", "theme_store_by_author": "bởi %@",
            "theme_store_download_btn": "Tải xuống", "theme_store_json_url": "Đường dẫn JSON", "theme_store_json_desc": "Dán JSON trực tiếp hoặc liên kết index.",
            "translation_by": "Bản dịch %@ (%@)", "credit_community": "Đã hỗ trợ dự án của tôi.", "credit_yang_support": "Đã hỗ trợ tôi trong quá trình phát triển",
            "credit_yang_original": "Nhà phát triển gốc của EnsWilde", "credit_ls_new": "Nhà phát triển EnsWilde bản mới", "credit_forcequit_badquery": "Khai thác Bad_query",
            "credit_johnny_airlift": "Khai thác Airlift", "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "Tinh chỉnh Config, logic MobileGestalt mới",
            "credit_likepass_sound": "Tắt âm ghi âm cuộc gọi (iOS 27)", "credit_little_34306_concept": "Ý tưởng gốc về tắt âm ghi âm cuộc gọi",
            "credit_yihooong_silent": "Đã cung cấp âm thanh im lặng và nghiên cứu thay thế.", "credit_kianuni_erosion": "Nhà phát triển Erosion-cn - Logic ghi & hoàn tác tinh chỉnh",
            "log_mcm_load_failed": "Không load được MCM APIs", "log_app_group_url_failed": "Không lấy được App Group URL cho", "log_symlink_failed": "Tạo symlink thất bại:",
            "log_query_failed": "Tạo query thất bại", "log_xpc_error": "XPC Error: containermanagerd từ chối cấp token.", "log_kernel_token_failed": "Kernel từ chối cấp token",
            "log_consume_token_failed": "Consume token thất bại (errno:", "log_mcm_success": "Thành công qua MCM Symlink", "log_fsgetpath_success": "Thành công qua fsgetpath:",
            "log_fsgetpath_failed": "fsgetpath thất bại", "log_pointer_error": "Lỗi con trỏ", "log_consume_errno": "Consume errno:"
        ]
    ]

    private init() {
        self.currentLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
        loadStrings()
    }

    /// Get localized string for key
    func string(for key: String) -> String {
        // 1. Ưu tiên tìm trong file JSON (nếu có)
        if let value = strings[key], !value.isEmpty {
            return value
        }
        
        // 2. Nếu không có, tìm trong Hardcoded Dictionary
        if let hardcoded = hardcodedStrings[currentLanguage]?[key] {
            return hardcoded
        }
        
        // 3. Fallback về tiếng Anh trong Hardcoded
        if let englishHardcoded = hardcodedStrings["en"]?[key] {
            return englishHardcoded
        }
        
        // 4. Cuối cùng, nếu bí quá thì trả về key đã format
        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Load strings for current language
    private func loadStrings() {
        // TẠM BỎ QUA VIỆC ĐỌC TỪ DOCUMENTS ĐỂ TRÁNH LỖI CACHE CŨ
        // Chỉ đọc từ file JSON trong Bundle (nếu có) dành cho ngôn ngữ tải từ xa
        
        if let bundlePath = Bundle.main.path(forResource: currentLanguage, ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)),
           let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
            strings = loaded
            objectWillChange.send()
            return
        }

        // Nếu không có file JSON, để trống. Hàm string(for:) sẽ tự lấy từ Hardcoded.
        strings = [:]
        objectWillChange.send()
    }

    /// Check if a language file exists locally
    func hasLanguage(_ code: String) -> Bool {
        return LanguageFileUtility.hasLanguageFile(code)
    }
}

// MARK: - Convenience Functions
func L(_ key: String) -> String {
    return LocalizationManager.shared.string(for: key)
}