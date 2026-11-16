//
//  LocalizationManager.swift
//  EnsWilde
//

import Foundation

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "SelectedLanguage")
            objectWillChange.send()
        }
    }

    @Published var availableLanguages: [LanguageInfo] = []

    // TỪ ĐIỂN CHUẨN 100% - FULL 9 NGÔN NGỮ - ĐÃ BAO GỒM MÀN HÌNH PAIRING
    private let dict: [String: [String: String]] = [
        "en": [
            "nav_home": "Home", "nav_theme_store": "Theme Store", "nav_settings": "Settings", "nav_about": "About", "nav_apply": "Apply",
            "system_status": "System Status", "status_ready": "Ready", "section_tweaks": "Tweaks",
            "tool_mobile_gestalt": "MobileGestalt", "tool_mobile_gestalt_desc": "Modify MobileGestalt file",
            "manual_editor_title": "CacheExtra Editor", "manual_editor_subtitle": "Manually edit MobileGestalt keys",
            "tool_config_tweaks": "Config Tweaks", "tool_config_tweaks_desc": "Custom Lock Screen Footnote",
            "tool_passcode_theme": "Passcode Theme", "tool_passcode_theme_desc": "Customize passcode screen",
            "tool_apple_wallet": "Apple Wallet", "tool_apple_wallet_desc": "Manage wallet cards",
            "tool_disable_sound": "Disable Call Recording Sound", "tool_disable_sound_desc": "Disable call recording sound",
            
            "section_hardware_features": "Hardware Features", "section_display_and_ui": "Display & UI",
            "mg_boot_chime": "Boot chime", "mg_charge_limit": "Charge limit", "mg_camera_button": "Camera button",
            "mg_stage_manager": "Stage Manager", "mg_aod": "Always on Display", "mg_aod_vibrancy": "AOD Vibrancy", "mg_become_ipados": "Become iPadOS",
            
            "config_tweaks_title": "Config Tweaks", "config_enable_tweak": "Enable Tweak", "config_lock_screen_footnote": "Lock Screen Footnote",
            "config_footnote_placeholder": "Enter lock screen text...", "config_supervision_title": "Supervision", "config_enable_supervision": "Enable Supervision",
            "config_apply_save": "Apply Save Changes", "config_restore_save": "Restore Save Changes",
            
            "passcode_theme_manager": "Passcode Theme Manager", "passcode_enable_theme": "Enable Passcode Theme", "global_settings": "Global Settings",
            "passcode_language_method": "Language/Method", "passcode_telephony_version": "Telephony Version", "section_theme_library": "Theme Library",
            "section_theme_settings": "Theme Settings", "passcode_theme_name": "Theme Name", "passcode_detected_size": "Detected Size",
            "passcode_target_key_size": "Target Key Size", "passcode_selected_theme": "Selected Theme", "passcode_selected": "Selected",
            "passcode_theme_selected": "This theme will be applied", "section_theme_files": "Theme Files", "section_danger_zone": "Danger Zone",
            "passcode_delete_theme": "Delete Theme",
            
            "wallet_title": "Apple Wallet", "wallet_enable": "Enable Apple Wallet", "section_wallet_cards": "Wallet Cards",
            "wallet_no_cards": "No cards added", "section_add_card": "Add Card", "wallet_scan_card": "Scan Card ID",
            "wallet_manual_input": "Manual Input", "wallet_import_default_zip": "Import Default Card (ZIP)",
            
            "recording_sound_title": "Disable Call Recording Sound", "tone_status": "Tone Status", "current_tone": "Current Tone",
            "pairing_not_found": "Pairing file not found", "check_tone_status": "Check Tone Status", "tone_status_footer": "Checks whether the audio file on device is the original Apple file.",
            "backup_system": "Backup System", "backup_status": "Backup Status", "backup_ready": "Backup Ready", "refresh_backup_status": "Refresh Backup Status",
            "backup_system_footer": "On the first Apply, the app will automatically extract the original file to device storage.",
            "restore_default_sounds": "Restore Default Sounds", "restore_footer": "Restore original sounds from the auto-created backup.",
            
            "theme_store_downloaded": "Downloaded", "theme_store_download_btn": "Download", "theme_store_by_author": "by %@", "theme_store_repos": "Repositories",
            "theme_store_theme_count": "%d themes", "theme_store_json_url": "JSON URL", "theme_store_json_desc": "Paste a direct themes JSON or an index.",
            "theme_store_loading": "Loading...", "theme_store_empty": "Empty. Tap + to add.", "theme_store_delete_group": "Delete Group", "theme_store_delete_repo": "Delete Repo",
            
            "settings_run_test_header": "RUN TEST (WorseQuery Access)", "settings_run_test_btn": "Test MobileGestalt read/write permissions",
            "settings_respring_header": "RESPRING (NeoSpring)", "settings_respring_btn": "Respring Device", "settings_tunnel_status": "Tunnel Connection",
            "connection_status": "Connection Status", "pairing_file": "Pairing File", "status_not_ready": "Not Ready",
            "import_pairing": "Import Pairing", "pair_on_device": "Pair On Device (iOS 27+)", "button_reset_pairing": "Reset Pairing",
            "settings_language": "Language", "settings_accent_color": "Accent Color", "settings_app_info": "App Info",
            "color_orange": "Orange", "color_pink": "Pink", "color_mauve": "Mauve", "color_red": "Red", "color_green": "Green", "color_blue": "Blue",
            "app_ios": "iOS", "app_device": "Device", "app_info_footer": "iOS 27+: bad_query can modify lock screen text and PosterBoard wallpaper. iOS 26: Airlift only.",
            
            "about_desc": "Thanks for using Enswilde, Rebuild with bad_query.", "button_donate": "Donate",
            "about_group_yang": "Telegram Group YangJiii", "about_group_ls": "Telegram Group LSNguyen", "about_contact": "Contact Me",
            "settings_thanks_to": "Thanks To", "credit_yang_support": "For supporting me during development", "credit_yang_original": "Original developer of EnsWilde",
            "credit_ls_new": "Developer of new EnsWilde", "credit_forcequit_badquery": "Bad_query exploit", "credit_johnny_airlift": "Airlift exploit",
            "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "Config tweak, new logic mobilegestalt", "credit_likepass_sound": "Disable Call Recording Sound (iOS 27)",
            "credit_little_34306_concept": "Original concept of disable call recording sound", "credit_yihooong_silent": "For the silent tone assets and replacement research.",
            "credit_kianuni_erosion": "Erosion-cn Developer - Write & Revert tweaks logic", "credit_community": "For support my project.",
            "settings_translators": "Translators", "translation_by": "%@ (%@) translation",
            
            "enable_tweak": "Enable Tweak", "mg_save_settings": "Save Settings", "mg_revert_tweaks": "Revert Tweaks",
            "mg_save_success_message": "Saved and applied successfully. Hard reboot the device so iOS picks up the new configuration.",
            "mg_revert_success_message": "All tweaks reverted successfully. Please go to SETTINGS and tap 'Respring Device' to apply the changes.",
            "mg_revert_failed": "Revert failed:", "mg_init_failed": "Failed to load MobileGestalt: %@",
            "mg_device_subtype_preset": "Device Subtype Preset", "mg_subtype_none": "None", "mg_subtype_2436": "2436 (iPhone X Gestures)",
            "mg_subtype_2556": "2556 (iPhone 14 Pro)", "mg_subtype_2796": "2796 (iPhone 14 Pro Max)", "mg_subtype_2976": "2976 (iPhone 15 Pro Max)",
            "mg_subtype_2622": "2622 (iPhone 16 Pro)", "mg_subtype_2868": "2868 (iPhone 16 Pro Max)", "mg_subtype_2736": "2736 (iPhone Air)",
            "mg_subtype_2662": "2662 (iPhone 18 Pro)", "mg_subtype_custom": "Custom Subtype", "mg_enable_custom_subtype": "Enable Custom Subtype",
            "mg_custom_subtype_placeholder": "Enter ArtworkDeviceSubType (e.g. 2xxx)", "mg_change_model_name": "Change Device Model Name",
            "mg_model_name_placeholder": "Model Name", "mg_region": "Region", "mg_device_model": "Device model", "mg_device_model_unchanged": "unchanged",
            
            "manual_editor_fields": "Fields", "manual_editor_empty": "CacheExtra is empty.", "manual_editor_delete": "Delete", "manual_editor_save": "Save Settings",
            "manual_editor_saving": "Saving…", "manual_editor_revert": "Revert Tweaks", "manual_editor_reverting": "Reverting…", "manual_editor_save_revert": "Save & Revert",
            "manual_editor_invalid_value": "Invalid value", "manual_editor_search": "Search keys…", "manual_editor_revert_confirm_title": "Revert all MobileGestalt tweaks?",
            "manual_editor_revert_confirm_message": "This deletes the live MobileGestalt cache file. iOS will regenerate a clean copy on the next reboot.",
            "manual_editor_key": "Key", "manual_editor_key_placeholder": "Obfuscated key (22 chars)", "manual_editor_type": "Type", "manual_editor_value": "Value",
            "manual_editor_add_field": "Add Field", "manual_editor_edit_field": "Edit Field", "manual_editor_placeholder_int": "e.g. 1", "manual_editor_placeholder_real": "e.g. 1.5",
            "manual_editor_placeholder_string": "String value", "manual_editor_placeholder_base64": "Base64", "manual_editor_placeholder_date": "ISO 8601",
            "manual_editor_placeholder_xml": "Plist XML fragment", "manual_editor_err_invalid_int": "Enter a valid whole number.",
            "manual_editor_err_invalid_real": "Enter a finite decimal number.", "manual_editor_err_invalid_bool": "Use true or false for a Boolean value.",
            "manual_editor_err_invalid_date": "Enter an ISO 8601 date.", "manual_editor_err_invalid_data": "Enter valid Base64 data.", "manual_editor_err_invalid_xml": "Enter a valid XML plist fragment.",
            
            // --- PAIRING KEYS ---
            "pair_enter_pin_title": "Enter this PIN in Settings",
            "pair_step_instruction": "Settings > Privacy & Security > Developer Mode > Pair with EnsWilde",
            "pair_success_title": "Pairing Successful!",
            "pair_start_btn": "Start Pair On Device",
            "pair_background_info": "The app has infinite background execution enabled. You can safely switch to Settings to enter the PIN without iOS terminating it.",
            
            "alert_ok": "OK", "alert_cancel": "Cancel", "alert_message_title": "Message", "alert_error": "Error", "alert_close": "Close", "button_add": "Add", "save_changes": "Save Changes"
        ],
        "vi": [
            "nav_home": "Trang chủ", "nav_theme_store": "Kho giao diện", "nav_settings": "Cài đặt", "nav_about": "Giới thiệu", "nav_apply": "Áp dụng",
            "system_status": "Trạng thái hệ thống", "status_ready": "Sẵn sàng", "section_tweaks": "Tinh chỉnh",
            "tool_mobile_gestalt": "MobileGestalt", "tool_mobile_gestalt_desc": "Chỉnh sửa file MobileGestalt",
            "manual_editor_title": "Chỉnh sửa CacheExtra", "manual_editor_subtitle": "Chỉnh tay các key MobileGestalt",
            "tool_config_tweaks": "Tinh chỉnh Config", "tool_config_tweaks_desc": "Tùy chỉnh chú thích màn hình khóa",
            "tool_passcode_theme": "Theme màn hình khóa", "tool_passcode_theme_desc": "Tùy chỉnh màn hình nhập mật khẩu",
            "tool_apple_wallet": "Apple Wallet", "tool_apple_wallet_desc": "Quản lý thẻ trong ví",
            "tool_disable_sound": "Tắt âm báo ghi âm cuộc gọi", "tool_disable_sound_desc": "Tắt âm thanh ghi âm cuộc gọi",
            
            "section_hardware_features": "Tính năng phần cứng", "section_display_and_ui": "Hiển thị & Giao diện",
            "mg_boot_chime": "Âm thanh khởi động", "mg_charge_limit": "Giới hạn sạc", "mg_camera_button": "Nút camera",
            "mg_stage_manager": "Stage Manager", "mg_aod": "Màn hình luôn bật (AOD)", "mg_aod_vibrancy": "Độ sống động AOD", "mg_become_ipados": "Chuyển thành iPadOS",
            
            "config_tweaks_title": "Tinh chỉnh Config", "config_enable_tweak": "Bật tinh chỉnh", "config_lock_screen_footnote": "Chữ trên màn hình khóa",
            "config_footnote_placeholder": "Nhập chữ cho màn hình khoá...", "config_supervision_title": "Giám sát (Supervision)", "config_enable_supervision": "Bật giám sát",
            "config_apply_save": "Áp dụng thay đổi", "config_restore_save": "Khôi phục thay đổi",
            
            "passcode_theme_manager": "Quản lý Theme mật khẩu", "passcode_enable_theme": "Bật Theme mật khẩu", "global_settings": "Cài đặt chung",
            "passcode_language_method": "Ngôn ngữ/Phương thức", "passcode_telephony_version": "Phiên bản Telephony", "section_theme_library": "Thư viện Theme",
            "section_theme_settings": "Cài đặt Theme", "passcode_theme_name": "Tên Theme", "passcode_detected_size": "Kích thước phát hiện",
            "passcode_target_key_size": "Kích thước phím đích", "passcode_selected_theme": "Theme đã chọn", "passcode_selected": "Đã chọn",
            "passcode_theme_selected": "Theme này sẽ được áp dụng", "section_theme_files": "Tệp Theme", "section_danger_zone": "Vùng nguy hiểm",
            "passcode_delete_theme": "Xóa Theme",
            
            "wallet_title": "Apple Wallet", "wallet_enable": "Bật Apple Wallet", "section_wallet_cards": "Thẻ trong ví",
            "wallet_no_cards": "Chưa thêm thẻ nào", "section_add_card": "Thêm thẻ", "wallet_scan_card": "Quét Card ID",
            "wallet_manual_input": "Nhập thủ công", "wallet_import_default_zip": "Nhập thẻ mặc định (ZIP)",
            
            "recording_sound_title": "Tắt âm báo ghi âm cuộc gọi", "tone_status": "Trạng thái âm thanh", "current_tone": "Âm thanh hiện tại",
            "pairing_not_found": "Không tìm thấy tệp pairing", "check_tone_status": "Kiểm tra trạng thái âm thanh", "tone_status_footer": "Kiểm tra xem file âm thanh trên máy đang là file gốc của Apple.",
            "backup_system": "Hệ thống sao lưu", "backup_status": "Trạng thái sao lưu", "backup_ready": "Backup sẵn sàng", "refresh_backup_status": "Làm mới trạng thái sao lưu",
            "backup_system_footer": "Ở lần Apply đầu tiên, App sẽ tự động trích xuất file gốc vào bộ nhớ máy.",
            "restore_default_sounds": "Khôi phục âm thanh mặc định", "restore_footer": "Khôi phục lại âm thanh gốc từ bản Backup đã được tạo tự động.",
            
            "theme_store_downloaded": "Đã tải xuống", "theme_store_download_btn": "Tải xuống", "theme_store_by_author": "bởi %@", "theme_store_repos": "Kho lưu trữ",
            "theme_store_theme_count": "%d giao diện", "theme_store_json_url": "Đường dẫn JSON", "theme_store_json_desc": "Dán JSON trực tiếp hoặc liên kết index.",
            "theme_store_loading": "Đang tải...", "theme_store_empty": "Trống. Nhấn + để thêm.", "theme_store_delete_group": "Xóa nhóm", "theme_store_delete_repo": "Xóa kho",
            
            "settings_run_test_header": "CHẠY THỬ NGHIỆM (WorseQuery)", "settings_run_test_btn": "Kiểm tra quyền đọc/ghi MobileGestalt",
            "settings_respring_header": "RESPRING (NeoSpring)", "settings_respring_btn": "Khởi động lại SpringBoard", "settings_tunnel_status": "Kết nối Tunnel",
            "connection_status": "Trạng thái kết nối", "pairing_file": "Tệp Pairing", "status_not_ready": "Chưa sẵn sàng",
            "import_pairing": "Nhập Pairing", "pair_on_device": "Ghép nối trên thiết bị (iOS 27+)", "button_reset_pairing": "Đặt lại Pairing",
            "settings_language": "Ngôn ngữ", "settings_accent_color": "Màu nhấn", "settings_app_info": "Thông tin ứng dụng",
            "color_orange": "Cam", "color_pink": "Hồng", "color_mauve": "Tím nhạt", "color_red": "Đỏ", "color_green": "Xanh lá", "color_blue": "Xanh dương",
            "app_ios": "iOS", "app_device": "Thiết bị", "app_info_footer": "iOS 27+: bad_query có thể sửa chữ màn hình khóa và hình nền PosterBoard. iOS 26: chỉ Airlift.",
            
            "about_desc": "Cảm ơn bạn đã dùng Enswilde, được xây dựng lại bằng bad_query.", "button_donate": "Ủng hộ",
            "about_group_yang": "Nhóm Telegram YangJiii", "about_group_ls": "Nhóm Telegram LSNguyen", "about_contact": "Liên hệ tôi",
            "settings_thanks_to": "Cảm ơn", "credit_yang_support": "Đã hỗ trợ tôi trong quá trình phát triển", "credit_yang_original": "Nhà phát triển gốc của EnsWilde",
            "credit_ls_new": "Nhà phát triển EnsWilde bản mới", "credit_forcequit_badquery": "Khai thác Bad_query", "credit_johnny_airlift": "Khai thác Airlift",
            "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "Tinh chỉnh Config, logic MobileGestalt mới", "credit_likepass_sound": "Tắt âm ghi âm cuộc gọi (iOS 27)",
            "credit_little_34306_concept": "Ý tưởng gốc về tắt âm ghi âm cuộc gọi", "credit_yihooong_silent": "Đã cung cấp âm thanh im lặng và nghiên cứu thay thế.",
            "credit_kianuni_erosion": "Nhà phát triển Erosion-cn - Logic ghi & hoàn tác tinh chỉnh", "credit_community": "Đã hỗ trợ dự án của tôi.",
            "settings_translators": "Người dịch", "translation_by": "Bản dịch %@ (%@)",
            
            "enable_tweak": "Bật tinh chỉnh", "mg_save_settings": "Lưu cài đặt", "mg_revert_tweaks": "Khôi phục mặc định",
            "mg_save_success_message": "Đã lưu và áp dụng thành công. Hãy Hard Reboot để iOS nhận cấu hình mới.",
            "mg_revert_success_message": "Đã khôi phục thành công. Vào Cài đặt và chọn 'Respring Device' để áp dụng.",
            "mg_revert_failed": "Khôi phục thất bại:", "mg_init_failed": "Không thể tải MobileGestalt: %@",
            "mg_device_subtype_preset": "Mẫu kiểu thiết bị", "mg_subtype_none": "Không", "mg_subtype_2436": "2436 (Cử chỉ iPhone X)",
            "mg_subtype_2556": "2556 (iPhone 14 Pro)", "mg_subtype_2796": "2796 (iPhone 14 Pro Max)", "mg_subtype_2976": "2976 (iPhone 15 Pro Max)",
            "mg_subtype_2622": "2622 (iPhone 16 Pro)", "mg_subtype_2868": "2868 (iPhone 16 Pro Max)", "mg_subtype_2736": "2736 (iPhone Air)",
            "mg_subtype_2662": "2662 (iPhone 18 Pro)", "mg_subtype_custom": "Tùy chỉnh Subtype", "mg_enable_custom_subtype": "Bật tùy chỉnh Subtype",
            "mg_custom_subtype_placeholder": "Nhập ArtworkDeviceSubType (ví dụ: 2xxx)", "mg_change_model_name": "Đổi tên Model thiết bị",
            "mg_model_name_placeholder": "Tên Model", "mg_region": "Vùng", "mg_device_model": "Model thiết bị", "mg_device_model_unchanged": "không đổi",
            
            "manual_editor_fields": "Danh sách key", "manual_editor_empty": "CacheExtra đang trống.", "manual_editor_delete": "Xóa", "manual_editor_save": "Lưu cài đặt",
            "manual_editor_saving": "Đang lưu…", "manual_editor_revert": "Khôi phục mặc định", "manual_editor_reverting": "Đang khôi phục…", "manual_editor_save_revert": "Lưu / Khôi phục",
            "manual_editor_invalid_value": "Giá trị không hợp lệ", "manual_editor_search": "Tìm key…", "manual_editor_revert_confirm_title": "Khôi phục toàn bộ tweak MobileGestalt?",
            "manual_editor_revert_confirm_message": "Thao tác này sẽ xóa file cache MobileGestalt đang dùng. iOS sẽ tạo lại file sạch khi khởi động lại.",
            "manual_editor_key": "Khóa (Key)", "manual_editor_key_placeholder": "Key 22 ký tự", "manual_editor_type": "Kiểu dữ liệu", "manual_editor_value": "Giá trị",
            "manual_editor_add_field": "Thêm field", "manual_editor_edit_field": "Sửa field", "manual_editor_placeholder_int": "ví dụ: 1", "manual_editor_placeholder_real": "ví dụ: 1.5",
            "manual_editor_placeholder_string": "Giá trị chuỗi", "manual_editor_placeholder_base64": "Base64", "manual_editor_placeholder_date": "ISO 8601",
            "manual_editor_placeholder_xml": "Đoạn XML plist", "manual_editor_err_invalid_int": "Nhập số nguyên hợp lệ.",
            "manual_editor_err_invalid_real": "Nhập số thực hợp lệ.", "manual_editor_err_invalid_bool": "Nhập true hoặc false.",
            "manual_editor_err_invalid_date": "Nhập ngày theo ISO 8601.", "manual_editor_err_invalid_data": "Nhập Base64 hợp lệ.", "manual_editor_err_invalid_xml": "Nhập đoạn XML plist hợp lệ.",
            
            // --- PAIRING KEYS ---
            "pair_enter_pin_title": "Nhập mã PIN này vào Cài đặt",
            "pair_step_instruction": "Cài đặt > Quyền riêng tư & Bảo mật > Chế độ nhà phát triển > Pair with EnsWilde",
            "pair_success_title": "Pairing Thành Công!",
            "pair_start_btn": "Bắt đầu Pair On Device",
            "pair_background_info": "App đã được bật chế độ chạy ngầm vô hạn. Bạn có thể yên tâm chuyển sang Settings để nhập PIN mà không lo bị iOS tắt.",
            
            "alert_ok": "OK", "alert_cancel": "Hủy", "alert_message_title": "Thông báo", "alert_error": "Lỗi", "alert_close": "Đóng", "button_add": "Thêm", "save_changes": "Lưu thay đổi"
        ],
        "ja": [
            "nav_home": "ホーム", "nav_theme_store": "テーマストア", "nav_settings": "設定", "nav_about": "情報", "nav_apply": "適用",
            "system_status": "システムステータス", "status_ready": "準備完了", "section_tweaks": "微調整",
            "tool_mobile_gestalt": "MobileGestalt", "tool_mobile_gestalt_desc": "MobileGestaltファイルを変更",
            "manual_editor_title": "CacheExtraエディタ", "manual_editor_subtitle": "MobileGestaltキーを手動で編集",
            "tool_config_tweaks": "Config 微調整", "tool_config_tweaks_desc": "ロック画面のフッターをカスタマイズ",
            "tool_passcode_theme": "パスコードテーマ", "tool_passcode_theme_desc": "パスコード画面をカスタマイズ",
            "tool_apple_wallet": "Apple Wallet", "tool_apple_wallet_desc": "ウォレットカードを管理",
            "tool_disable_sound": "通話録音音を無効にする", "tool_disable_sound_desc": "通話録音のサウンドを無効にする",
            
            "section_hardware_features": "ハードウェア機能", "section_display_and_ui": "ディスプレイとUI",
            "mg_boot_chime": "起動音", "mg_charge_limit": "充電制限", "mg_camera_button": "カメラボタン",
            "mg_stage_manager": "ステージマネージャ", "mg_aod": "常時表示ディスプレイ (AOD)", "mg_aod_vibrancy": "AODの鮮やかさ", "mg_become_ipados": "iPadOS化",
            
            "config_tweaks_title": "Config 微調整", "config_enable_tweak": "微調整を有効にする", "config_lock_screen_footnote": "ロック画面のフッター",
            "config_footnote_placeholder": "ロック画面のテキストを入力...", "config_supervision_title": "監視 (Supervision)", "config_enable_supervision": "監視を有効にする",
            "config_apply_save": "変更を適用して保存", "config_restore_save": "変更を復元して保存",
            
            "passcode_theme_manager": "パスコードテーママネージャー", "passcode_enable_theme": "パスコードテーマを有効にする", "global_settings": "グローバル設定",
            "passcode_language_method": "言語/メソッド", "passcode_telephony_version": "Telephonyバージョン", "section_theme_library": "テーマライブラリ",
            "section_theme_settings": "テーマ設定", "passcode_theme_name": "テーマ名", "passcode_detected_size": "検出されたサイズ",
            "passcode_target_key_size": "ターゲットキーサイズ", "passcode_selected_theme": "選択されたテーマ", "passcode_selected": "選択済み",
            "passcode_theme_selected": "このテーマが適用されます", "section_theme_files": "テーマファイル", "section_danger_zone": "危険ゾーン",
            "passcode_delete_theme": "テーマを削除",
            
            "wallet_title": "Apple Wallet", "wallet_enable": "Apple Walletを有効にする", "section_wallet_cards": "ウォレットカード",
            "wallet_no_cards": "カードが追加されていません", "section_add_card": "カードを追加", "wallet_scan_card": "カードIDをスキャン",
            "wallet_manual_input": "手動入力", "wallet_import_default_zip": "デフォルトカードをインポート (ZIP)",
            
            "recording_sound_title": "通話録音音を無効にする", "tone_status": "トーンステータス", "current_tone": "現在のトーン",
            "pairing_not_found": "ペアリングファイルが見つかりません", "check_tone_status": "トーンステータスを確認", "tone_status_footer": "デバイス上のオーディオファイルが元のAppleファイルかどうかを確認します。",
            "backup_system": "バックアップシステム", "backup_status": "バックアップステータス", "backup_ready": "バックアップ準備完了", "refresh_backup_status": "バックアップステータスを更新",
            "backup_system_footer": "最初の適用時に、アプリは元のファイルをデバイスストレージに自動的に抽出します。",
            "restore_default_sounds": "デフォルトのサウンドを復元", "restore_footer": "自動作成されたバックアップから元のサウンドを復元します。",
            
            "theme_store_downloaded": "ダウンロード済み", "theme_store_download_btn": "ダウンロード", "theme_store_by_author": "作成者: %@", "theme_store_repos": "リポジトリ",
            "theme_store_theme_count": "%d テーマ", "theme_store_json_url": "JSON URL", "theme_store_json_desc": "テーマのJSONを直接貼り付けるか、インデックスを貼り付けます。",
            "theme_store_loading": "読み込み中...", "theme_store_empty": "空です。+をタップして追加。", "theme_store_delete_group": "グループを削除", "theme_store_delete_repo": "リポジトリを削除",
            
            "settings_run_test_header": "テスト実行 (WorseQuery アクセス)", "settings_run_test_btn": "MobileGestalt の読み取り/書き込み権限をテスト",
            "settings_respring_header": "再スプリング (NeoSpring)", "settings_respring_btn": "デバイスを再スプリング", "settings_tunnel_status": "トンネル接続",
            "connection_status": "接続ステータス", "pairing_file": "ペアリングファイル", "status_not_ready": "準備未完了",
            "import_pairing": "ペアリングをインポート", "pair_on_device": "デバイスでペアリング (iOS 27+)", "button_reset_pairing": "ペアリングをリセット",
            "settings_language": "言語", "settings_accent_color": "アクセントカラー", "settings_app_info": "アプリ情報",
            "color_orange": "オレンジ", "color_pink": "ピンク", "color_mauve": "モーヴ", "color_red": "赤", "color_green": "緑", "color_blue": "青",
            "app_ios": "iOS", "app_device": "デバイス", "app_info_footer": "iOS 27+: bad_queryはロック画面のテキストと壁紙を変更できます。iOS 26: Airliftのみ。",
            
            "about_desc": "Enswildeをご利用いただきありがとうございます。bad_queryで再構築されました。", "button_donate": "寄付",
            "about_group_yang": "Telegramグループ YangJiii", "about_group_ls": "Telegramグループ LSNguyen", "about_contact": "お問い合わせ",
            "settings_thanks_to": "感謝", "credit_yang_support": "開発中のサポートに感謝します", "credit_yang_original": "EnsWildeのオリジナル開発者",
            "credit_ls_new": "新しいEnsWildeの開発者", "credit_forcequit_badquery": "Bad_query エクスプロイト", "credit_johnny_airlift": "Airlift エクスプロイト",
            "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "Config 微調整、新しい MobileGestalt ロジック", "credit_likepass_sound": "通話録音音を無効にする (iOS 27)",
            "credit_little_34306_concept": "通話録音音を無効にするオリジナルのコンセプト", "credit_yihooong_silent": "無音トーンのアセットと置換調査に感謝します。",
            "credit_kianuni_erosion": "Erosion-cn 開発者 - 微調整の書き込みと元に戻すロジック", "credit_community": "プロジェクトのサポートに感謝します。",
            "settings_translators": "翻訳者", "translation_by": "%@ (%@) 翻訳",
            
            "enable_tweak": "微調整を有効にする", "mg_save_settings": "設定を保存", "mg_revert_tweaks": "微調整を元に戻す",
            "mg_save_success_message": "保存して適用しました。iOSが新しい構成を認識するように、デバイスをハードリブートしてください。",
            "mg_revert_success_message": "すべての微調整が正常に元に戻されました。設定に移動して「デバイスを再スプリング」をタップしてください。",
            "mg_revert_failed": "元に戻すのに失敗しました:", "mg_init_failed": "MobileGestaltの読み込みに失敗しました: %@",
            "mg_device_subtype_preset": "デバイスサブタイプのプリセット", "mg_subtype_none": "なし", "mg_subtype_2436": "2436 (iPhone Xジェスチャー)",
            "mg_subtype_2556": "2556 (iPhone 14 Pro)", "mg_subtype_2796": "2796 (iPhone 14 Pro Max)", "mg_subtype_2976": "2976 (iPhone 15 Pro Max)",
            "mg_subtype_2622": "2622 (iPhone 16 Pro)", "mg_subtype_2868": "2868 (iPhone 16 Pro Max)", "mg_subtype_2736": "2736 (iPhone Air)",
            "mg_subtype_2662": "2662 (iPhone 18 Pro)", "mg_subtype_custom": "カスタムサブタイプ", "mg_enable_custom_subtype": "カスタムサブタイプを有効にする",
            "mg_custom_subtype_placeholder": "ArtworkDeviceSubTypeを入力 (例: 2xxx)", "mg_change_model_name": "デバイスモデル名を変更",
            "mg_model_name_placeholder": "モデル名", "mg_region": "地域", "mg_device_model": "デバイスモデル", "mg_device_model_unchanged": "変更なし",
            
            "manual_editor_fields": "フィールド", "manual_editor_empty": "CacheExtraは空です。", "manual_editor_delete": "削除", "manual_editor_save": "設定を保存",
            "manual_editor_saving": "保存中…", "manual_editor_revert": "微調整を元に戻す", "manual_editor_reverting": "元に戻しています…", "manual_editor_save_revert": "保存して元に戻す",
            "manual_editor_invalid_value": "無効な値", "manual_editor_search": "キーを検索…", "manual_editor_revert_confirm_title": "すべてのMobileGestaltの微調整を元に戻しますか？",
            "manual_editor_revert_confirm_message": "これにより、ライブのMobileGestaltキャッシュファイルが削除されます。iOSは次回の再起動時にクリーンなコピーを再生成します。",
            "manual_editor_key": "キー", "manual_editor_key_placeholder": "難読化されたキー (22文字)", "manual_editor_type": "タイプ", "manual_editor_value": "値",
            "manual_editor_add_field": "フィールドを追加", "manual_editor_edit_field": "フィールドを編集", "manual_editor_placeholder_int": "例: 1", "manual_editor_placeholder_real": "例: 1.5",
            "manual_editor_placeholder_string": "文字列値", "manual_editor_placeholder_base64": "Base64", "manual_editor_placeholder_date": "ISO 8601",
            "manual_editor_placeholder_xml": "Plist XMLフラグメント", "manual_editor_err_invalid_int": "有効な整数を入力してください。",
            "manual_editor_err_invalid_real": "有効な小数を入力してください。", "manual_editor_err_invalid_bool": "ブール値にはtrueまたはfalseを使用してください。",
            "manual_editor_err_invalid_date": "ISO 8601形式の日付を入力してください。", "manual_editor_err_invalid_data": "有効なBase64データを入力してください。", "manual_editor_err_invalid_xml": "有効なXML plistフラグメントを入力してください。",
            
            "pair_enter_pin_title": "設定でこのPINを入力してください",
            "pair_step_instruction": "設定 > プライバシーとセキュリティ > デベロッパモード > Pair with EnsWilde",
            "pair_success_title": "ペアリング成功！",
            "pair_start_btn": "デバイスでのペアリングを開始",
            "pair_background_info": "アプリは無限のバックグラウンド実行が有効になっています。iOSによって終了されることなく、設定に移動してPINを安全に入力できます。",
            
            "alert_ok": "OK", "alert_cancel": "キャンセル", "alert_message_title": "メッセージ", "alert_error": "エラー", "alert_close": "閉じる", "button_add": "追加", "save_changes": "変更を保存"
        ],
        "zh-CN": [
            "nav_home": "主页", "nav_theme_store": "主题商店", "nav_settings": "设置", "nav_about": "关于", "nav_apply": "应用",
            "system_status": "系统状态", "status_ready": "准备就绪", "section_tweaks": "微调",
            "tool_mobile_gestalt": "MobileGestalt", "tool_mobile_gestalt_desc": "修改 MobileGestalt 文件",
            "manual_editor_title": "CacheExtra 编辑器", "manual_editor_subtitle": "手动编辑 MobileGestalt 键",
            "tool_config_tweaks": "配置微调", "tool_config_tweaks_desc": "自定义锁屏页脚",
            "tool_passcode_theme": "密码界面主题", "tool_passcode_theme_desc": "自定义密码屏幕",
            "tool_apple_wallet": "Apple Wallet", "tool_apple_wallet_desc": "管理钱包卡片",
            "tool_disable_sound": "禁用通话录音声音", "tool_disable_sound_desc": "禁用通话录音声音",
            
            "section_hardware_features": "硬件功能", "section_display_and_ui": "显示与界面",
            "mg_boot_chime": "启动提示音", "mg_charge_limit": "充电限制", "mg_camera_button": "相机按钮",
            "mg_stage_manager": "台前调度 (Stage Manager)", "mg_aod": "全天候显示 (AOD)", "mg_aod_vibrancy": "AOD 生动度", "mg_become_ipados": "变身 iPadOS",
            
            "config_tweaks_title": "配置微调", "config_enable_tweak": "启用插件", "config_lock_screen_footnote": "锁屏页脚文本",
            "config_footnote_placeholder": "输入锁屏文本...", "config_supervision_title": "监督 (Supervision)", "config_enable_supervision": "启用监督",
            "config_apply_save": "应用并保存更改", "config_restore_save": "恢复并保存更改",
            
            "passcode_theme_manager": "密码主题管理器", "passcode_enable_theme": "启用密码主题", "global_settings": "全局设置",
            "passcode_language_method": "语言/方法", "passcode_telephony_version": "Telephony 版本", "section_theme_library": "主题库",
            "section_theme_settings": "主题设置", "passcode_theme_name": "主题名称", "passcode_detected_size": "检测到的尺寸",
            "passcode_target_key_size": "目标按键尺寸", "passcode_selected_theme": "已选主题", "passcode_selected": "已选择",
            "passcode_theme_selected": "此主题将被应用", "section_theme_files": "主题文件", "section_danger_zone": "危险区域",
            "passcode_delete_theme": "删除主题",
            
            "wallet_title": "Apple Wallet", "wallet_enable": "启用 Apple Wallet", "section_wallet_cards": "钱包卡片",
            "wallet_no_cards": "未添加卡片", "section_add_card": "添加卡片", "wallet_scan_card": "扫描卡片 ID",
            "wallet_manual_input": "手动输入", "wallet_import_default_zip": "导入默认卡片 (ZIP)",
            
            "recording_sound_title": "禁用通话录音声音", "tone_status": "提示音状态", "current_tone": "当前提示音",
            "pairing_not_found": "未找到配对文件", "check_tone_status": "检查提示音状态", "tone_status_footer": "检查设备上的音频文件是否为 Apple 原始文件。",
            "backup_system": "备份系统", "backup_status": "备份状态", "backup_ready": "备份就绪", "refresh_backup_status": "刷新备份状态",
            "backup_system_footer": "首次应用时，应用会自动将原始文件提取到设备存储空间。",
            "restore_default_sounds": "恢复默认声音", "restore_footer": "从自动创建的备份中恢复原始声音。",
            
            "theme_store_downloaded": "已下载", "theme_store_download_btn": "下载", "theme_store_by_author": "作者: %@", "theme_store_repos": "仓库",
            "theme_store_theme_count": "%d 个主题", "theme_store_json_url": "JSON URL", "theme_store_json_desc": "粘贴直接的 JSON 或索引链接。",
            "theme_store_loading": "加载中...", "theme_store_empty": "空。点击 + 添加。", "theme_store_delete_group": "删除组", "theme_store_delete_repo": "删除仓库",
            
            "settings_run_test_header": "运行测试 (WorseQuery 访问)", "settings_run_test_btn": "测试 MobileGestalt 读/写权限",
            "settings_respring_header": "注销 (NeoSpring)", "settings_respring_btn": "注销设备", "settings_tunnel_status": "隧道连接",
            "connection_status": "连接状态", "pairing_file": "配对文件", "status_not_ready": "未就绪",
            "import_pairing": "导入配对", "pair_on_device": "在设备上配对 (iOS 27+)", "button_reset_pairing": "重置配对",
            "settings_language": "语言", "settings_accent_color": "强调色", "settings_app_info": "应用信息",
            "color_orange": "橙色", "color_pink": "粉色", "color_mauve": "淡紫色", "color_red": "红色", "color_green": "绿色", "color_blue": "蓝色",
            "app_ios": "iOS", "app_device": "设备", "app_info_footer": "iOS 27+: bad_query 可修改锁屏文本和 PosterBoard 壁纸。iOS 26: 仅限 Airlift。",
            
            "about_desc": "感谢使用 Enswilde，使用 bad_query 重建。", "button_donate": "捐赠",
            "about_group_yang": "Telegram 群组 YangJiii", "about_group_ls": "Telegram 群组 LSNguyen", "about_contact": "联系我",
            "settings_thanks_to": "致谢", "credit_yang_support": "感谢在开发期间支持我", "credit_yang_original": "EnsWilde 的原开发者",
            "credit_ls_new": "新 EnsWilde 的开发者", "credit_forcequit_badquery": "Bad_query 漏洞", "credit_johnny_airlift": "Airlift 漏洞",
            "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "配置微调，新的 MobileGestalt 逻辑", "credit_likepass_sound": "禁用通话录音声音 (iOS 27)",
            "credit_little_34306_concept": "禁用通话录音声音的原始概念", "credit_yihooong_silent": "感谢提供静音音频资源和替换研究。",
            "credit_kianuni_erosion": "Erosion-cn 开发者 - 写入和还原微调逻辑", "credit_community": "感谢支持我的项目。",
            "settings_translators": "翻译者", "translation_by": "%@ (%@) 翻译",
            
            "enable_tweak": "启用插件", "mg_save_settings": "保存设置", "mg_revert_tweaks": "还原微调",
            "mg_save_success_message": "保存并应用成功。请硬重启设备以便 iOS 读取新配置。",
            "mg_revert_success_message": "所有微调已成功还原。请转到设置并点击“注销设备”以应用更改。",
            "mg_revert_failed": "还原失败:", "mg_init_failed": "加载 MobileGestalt 失败: %@",
            "mg_device_subtype_preset": "设备子型号预设", "mg_subtype_none": "无", "mg_subtype_2436": "2436 (iPhone X 手势)",
            "mg_subtype_2556": "2556 (iPhone 14 Pro)", "mg_subtype_2796": "2796 (iPhone 14 Pro Max)", "mg_subtype_2976": "2976 (iPhone 15 Pro Max)",
            "mg_subtype_2622": "2622 (iPhone 16 Pro)", "mg_subtype_2868": "2868 (iPhone 16 Pro Max)", "mg_subtype_2736": "2736 (iPhone Air)",
            "mg_subtype_2662": "2662 (iPhone 18 Pro)", "mg_subtype_custom": "自定义子类型", "mg_enable_custom_subtype": "启用自定义子类型",
            "mg_custom_subtype_placeholder": "输入 ArtworkDeviceSubType (例如 2xxx)", "mg_change_model_name": "更改设备型号名称",
            "mg_model_name_placeholder": "型号名称", "mg_region": "地区", "mg_device_model": "设备型号", "mg_device_model_unchanged": "保持不变",
            
            "manual_editor_fields": "字段", "manual_editor_empty": "CacheExtra 为空。", "manual_editor_delete": "删除", "manual_editor_save": "保存设置",
            "manual_editor_saving": "保存中…", "manual_editor_revert": "还原微调", "manual_editor_reverting": "还原中…", "manual_editor_save_revert": "保存并还原",
            "manual_editor_invalid_value": "无效值", "manual_editor_search": "搜索键…", "manual_editor_revert_confirm_title": "还原所有 MobileGestalt 微调？",
            "manual_editor_revert_confirm_message": "这将删除实时 MobileGestalt 缓存文件。iOS 将在下次重启时重新生成干净副本。",
            "manual_editor_key": "键 (Key)", "manual_editor_key_placeholder": "混淆键 (22 个字符)", "manual_editor_type": "类型", "manual_editor_value": "值",
            "manual_editor_add_field": "添加字段", "manual_editor_edit_field": "编辑字段", "manual_editor_placeholder_int": "例如: 1", "manual_editor_placeholder_real": "例如: 1.5",
            "manual_editor_placeholder_string": "字符串值", "manual_editor_placeholder_base64": "Base64", "manual_editor_placeholder_date": "ISO 8601",
            "manual_editor_placeholder_xml": "Plist XML 片段", "manual_editor_err_invalid_int": "请输入有效的整数。",
            "manual_editor_err_invalid_real": "请输入有效的小数。", "manual_editor_err_invalid_bool": "布尔值请输入 true 或 false。",
            "manual_editor_err_invalid_date": "请输入 ISO 8601 日期。", "manual_editor_err_invalid_data": "请输入有效的 Base64 数据。", "manual_editor_err_invalid_xml": "请输入有效的 XML plist 片段。",
            
            "pair_enter_pin_title": "在设置中输入此 PIN 码",
            "pair_step_instruction": "设置 > 隐私与安全性 > 开发者模式 > Pair with EnsWilde",
            "pair_success_title": "配对成功！",
            "pair_start_btn": "开始在设备上配对",
            "pair_background_info": "应用已启用无限后台运行。您可以安全地切换到设置输入 PIN，而不必担心被 iOS 终止。",
            
            "alert_ok": "确定", "alert_cancel": "取消", "alert_message_title": "消息", "alert_error": "错误", "alert_close": "关闭", "button_add": "添加", "save_changes": "保存更改"
        ],
        "zh-TW": [
            "nav_home": "主頁", "nav_theme_store": "主題商店", "nav_settings": "設定", "nav_about": "關於", "nav_apply": "套用",
            "system_status": "系統狀態", "status_ready": "準備就緒", "section_tweaks": "微調",
            "tool_mobile_gestalt": "MobileGestalt", "tool_mobile_gestalt_desc": "修改 MobileGestalt 檔案",
            "manual_editor_title": "CacheExtra 編輯器", "manual_editor_subtitle": "手動編輯 MobileGestalt 鍵",
            "tool_config_tweaks": "設定微調", "tool_config_tweaks_desc": "自訂鎖定畫面頁尾",
            "tool_passcode_theme": "密碼介面主題", "tool_passcode_theme_desc": "自訂密碼畫面",
            "tool_apple_wallet": "Apple Wallet", "tool_apple_wallet_desc": "管理錢包卡片",
            "tool_disable_sound": "停用通話錄音聲音", "tool_disable_sound_desc": "停用通話錄音聲音",
            
            "section_hardware_features": "硬體功能", "section_display_and_ui": "顯示與介面",
            "mg_boot_chime": "開機提示音", "mg_charge_limit": "充電限制", "mg_camera_button": "相機按鈕",
            "mg_stage_manager": "台前調度 (Stage Manager)", "mg_aod": "永遠顯示 (AOD)", "mg_aod_vibrancy": "AOD 生動度", "mg_become_ipados": "變身 iPadOS",
            
            "config_tweaks_title": "設定微調", "config_enable_tweak": "啟用外掛", "config_lock_screen_footnote": "鎖定畫面頁尾文字",
            "config_footnote_placeholder": "輸入鎖定畫面文字...", "config_supervision_title": "監督 (Supervision)", "config_enable_supervision": "啟用監督",
            "config_apply_save": "套用並儲存變更", "config_restore_save": "還原並儲存變更",
            
            "passcode_theme_manager": "密碼主題管理器", "passcode_enable_theme": "啟用密碼主題", "global_settings": "全域設定",
            "passcode_language_method": "語言/方法", "passcode_telephony_version": "Telephony 版本", "section_theme_library": "主題庫",
            "section_theme_settings": "主題設定", "passcode_theme_name": "主題名稱", "passcode_detected_size": "偵測到的尺寸",
            "passcode_target_key_size": "目標按鍵尺寸", "passcode_selected_theme": "已選主題", "passcode_selected": "已選擇",
            "passcode_theme_selected": "此主題將被套用", "section_theme_files": "主題檔案", "section_danger_zone": "危險區域",
            "passcode_delete_theme": "刪除主題",
            
            "wallet_title": "Apple Wallet", "wallet_enable": "啟用 Apple Wallet", "section_wallet_cards": "錢包卡片",
            "wallet_no_cards": "未新增卡片", "section_add_card": "新增卡片", "wallet_scan_card": "掃描卡片 ID",
            "wallet_manual_input": "手動輸入", "wallet_import_default_zip": "匯入預設卡片 (ZIP)",
            
            "recording_sound_title": "停用通話錄音聲音", "tone_status": "提示音狀態", "current_tone": "目前提示音",
            "pairing_not_found": "找不到配對檔案", "check_tone_status": "檢查提示音狀態", "tone_status_footer": "檢查裝置上的音訊檔案是否為 Apple 原始檔案。",
            "backup_system": "備份系統", "backup_status": "備份狀態", "backup_ready": "備份就緒", "refresh_backup_status": "重新整理備份狀態",
            "backup_system_footer": "首次套用時，應用程式會自動將原始檔案擷取到裝置儲存空間。",
            "restore_default_sounds": "還原預設聲音", "restore_footer": "從自動建立的備份中還原原始聲音。",
            
            "theme_store_downloaded": "已下載", "theme_store_download_btn": "下載", "theme_store_by_author": "作者: %@", "theme_store_repos": "儲存庫",
            "theme_store_theme_count": "%d 個主題", "theme_store_json_url": "JSON URL", "theme_store_json_desc": "貼上直接的 JSON 或索引連結。",
            "theme_store_loading": "載入中...", "theme_store_empty": "空。點擊 + 新增。", "theme_store_delete_group": "刪除群組", "theme_store_delete_repo": "刪除儲存庫",
            
            "settings_run_test_header": "執行測試 (WorseQuery 存取)", "settings_run_test_btn": "測試 MobileGestalt 讀取/寫入權限",
            "settings_respring_header": "重新載入 (NeoSpring)", "settings_respring_btn": "重新載入裝置", "settings_tunnel_status": "通道連線",
            "connection_status": "連線狀態", "pairing_file": "配對檔案", "status_not_ready": "未就緒",
            "import_pairing": "匯入配對", "pair_on_device": "在裝置上配對 (iOS 27+)", "button_reset_pairing": "重置配對",
            "settings_language": "語言", "settings_accent_color": "強調色", "settings_app_info": "應用程式資訊",
            "color_orange": "橘色", "color_pink": "粉色", "color_mauve": "淡紫色", "color_red": "紅色", "color_green": "綠色", "color_blue": "藍色",
            "app_ios": "iOS", "app_device": "裝置", "app_info_footer": "iOS 27+: bad_query 可修改鎖定畫面文字和 PosterBoard 桌布。iOS 26: 僅限 Airlift。",
            
            "about_desc": "感謝使用 Enswilde，使用 bad_query 重建。", "button_donate": "捐贈",
            "about_group_yang": "Telegram 群組 YangJiii", "about_group_ls": "Telegram 群組 LSNguyen", "about_contact": "聯絡我",
            "settings_thanks_to": "致謝", "credit_yang_support": "感謝在開發期間支持我", "credit_yang_original": "EnsWilde 的原始開發者",
            "credit_ls_new": "新 EnsWilde 的開發者", "credit_forcequit_badquery": "Bad_query 漏洞", "credit_johnny_airlift": "Airlift 漏洞",
            "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "設定微調，新的 MobileGestalt 邏輯", "credit_likepass_sound": "停用通話錄音聲音 (iOS 27)",
            "credit_little_34306_concept": "停用通話錄音聲音的原始概念", "credit_yihooong_silent": "感謝提供靜音音訊資源與替換研究。",
            "credit_kianuni_erosion": "Erosion-cn 開發者 - 寫入與還原微調邏輯", "credit_community": "感謝支持我的專案。",
            "settings_translators": "翻譯者", "translation_by": "%@ (%@) 翻譯",
            
            "enable_tweak": "啟用外掛", "mg_save_settings": "儲存設定", "mg_revert_tweaks": "還原微調",
            "mg_save_success_message": "儲存並套用成功。請強制重啟裝置以便 iOS 讀取新設定。",
            "mg_revert_success_message": "所有微調已成功還原。請前往設定並點擊「重新載入裝置」以套用變更。",
            "mg_revert_failed": "還原失敗:", "mg_init_failed": "載入 MobileGestalt 失敗: %@",
            "mg_device_subtype_preset": "裝置子型號預設", "mg_subtype_none": "無", "mg_subtype_2436": "2436 (iPhone X 手勢)",
            "mg_subtype_2556": "2556 (iPhone 14 Pro)", "mg_subtype_2796": "2796 (iPhone 14 Pro Max)", "mg_subtype_2976": "2976 (iPhone 15 Pro Max)",
            "mg_subtype_2622": "2622 (iPhone 16 Pro)", "mg_subtype_2868": "2868 (iPhone 16 Pro Max)", "mg_subtype_2736": "2736 (iPhone Air)",
            "mg_subtype_2662": "2662 (iPhone 18 Pro)", "mg_subtype_custom": "自訂子類型", "mg_enable_custom_subtype": "啟用自訂子類型",
            "mg_custom_subtype_placeholder": "輸入 ArtworkDeviceSubType (例如 2xxx)", "mg_change_model_name": "更改裝置型號名稱",
            "mg_model_name_placeholder": "型號名稱", "mg_region": "地區", "mg_device_model": "裝置型號", "mg_device_model_unchanged": "保持不變",
            
            "manual_editor_fields": "欄位", "manual_editor_empty": "CacheExtra 為空。", "manual_editor_delete": "刪除", "manual_editor_save": "儲存設定",
            "manual_editor_saving": "儲存中…", "manual_editor_revert": "還原微調", "manual_editor_reverting": "還原中…", "manual_editor_save_revert": "儲存並還原",
            "manual_editor_invalid_value": "無效值", "manual_editor_search": "搜尋鍵…", "manual_editor_revert_confirm_title": "還原所有 MobileGestalt 微調？",
            "manual_editor_revert_confirm_message": "這將刪除即時 MobileGestalt 快取檔案。iOS 將在下次重啟時重新產生乾淨副本。",
            "manual_editor_key": "鍵 (Key)", "manual_editor_key_placeholder": "混淆鍵 (22 個字元)", "manual_editor_type": "類型", "manual_editor_value": "值",
            "manual_editor_add_field": "新增欄位", "manual_editor_edit_field": "編輯欄位", "manual_editor_placeholder_int": "例如: 1", "manual_editor_placeholder_real": "例如: 1.5",
            "manual_editor_placeholder_string": "字串值", "manual_editor_placeholder_base64": "Base64", "manual_editor_placeholder_date": "ISO 8601",
            "manual_editor_placeholder_xml": "Plist XML 片段", "manual_editor_err_invalid_int": "請輸入有效的整數。",
            "manual_editor_err_invalid_real": "請輸入有效的小數。", "manual_editor_err_invalid_bool": "布林值請輸入 true 或 false。",
            "manual_editor_err_invalid_date": "請輸入 ISO 8601 日期。", "manual_editor_err_invalid_data": "請輸入有效的 Base64 資料。", "manual_editor_err_invalid_xml": "請輸入有效的 XML plist 片段。",
            
            "pair_enter_pin_title": "在設定中輸入此 PIN 碼",
            "pair_step_instruction": "設定 > 隱私權與安全性 > 開發者模式 > Pair with EnsWilde",
            "pair_success_title": "配對成功！",
            "pair_start_btn": "開始在裝置上配對",
            "pair_background_info": "應用程式已啟用無限背景執行。您可以安全地切換到設定輸入 PIN，而不必擔心被 iOS 終止。",
            
            "alert_ok": "確定", "alert_cancel": "取消", "alert_message_title": "訊息", "alert_error": "錯誤", "alert_close": "關閉", "button_add": "新增", "save_changes": "儲存變更"
        ],
        "fr": [
            "nav_home": "Accueil", "nav_theme_store": "Boutique de thèmes", "nav_settings": "Réglages", "nav_about": "À propos", "nav_apply": "Appliquer",
            "system_status": "État du système", "status_ready": "Prêt", "section_tweaks": "Ajustements",
            "tool_mobile_gestalt": "MobileGestalt", "tool_mobile_gestalt_desc": "Modifier le fichier MobileGestalt",
            "manual_editor_title": "Éditeur CacheExtra", "manual_editor_subtitle": "Modifier manuellement les clés MobileGestalt",
            "tool_config_tweaks": "Ajustements de configuration", "tool_config_tweaks_desc": "Note de bas de page de l'écran de verrouillage",
            "tool_passcode_theme": "Thème du code", "tool_passcode_theme_desc": "Personnaliser l'écran du code",
            "tool_apple_wallet": "Apple Wallet", "tool_apple_wallet_desc": "Gérer les cartes",
            "tool_disable_sound": "Désactiver le son d'enregistrement", "tool_disable_sound_desc": "Désactiver le son d'enregistrement d'appel",
            
            "section_hardware_features": "Fonctionnalités matérielles", "section_display_and_ui": "Affichage et interface",
            "mg_boot_chime": "Carillon de démarrage", "mg_charge_limit": "Limite de charge", "mg_camera_button": "Bouton de l'appareil photo",
            "mg_stage_manager": "Stage Manager", "mg_aod": "Toujours activé (AOD)", "mg_aod_vibrancy": "Vibrance AOD", "mg_become_ipados": "Devenir iPadOS",
            
            "config_tweaks_title": "Ajustements de configuration", "config_enable_tweak": "Activer l'ajustement", "config_lock_screen_footnote": "Note de bas de page",
            "config_footnote_placeholder": "Entrez le texte de l'écran de verrouillage...", "config_supervision_title": "Supervision", "config_enable_supervision": "Activer la supervision",
            "config_apply_save": "Appliquer les modifications", "config_restore_save": "Restaurer les modifications",
            
            "passcode_theme_manager": "Gestionnaire de thèmes de code", "passcode_enable_theme": "Activer le thème du code", "global_settings": "Paramètres globaux",
            "passcode_language_method": "Langue/Méthode", "passcode_telephony_version": "Version Telephony", "section_theme_library": "Bibliothèque de thèmes",
            "section_theme_settings": "Paramètres du thème", "passcode_theme_name": "Nom du thème", "passcode_detected_size": "Taille détectée",
            "passcode_target_key_size": "Taille de touche cible", "passcode_selected_theme": "Thème sélectionné", "passcode_selected": "Sélectionné",
            "passcode_theme_selected": "Ce thème sera appliqué", "section_theme_files": "Fichiers de thème", "section_danger_zone": "Zone de danger",
            "passcode_delete_theme": "Supprimer le thème",
            
            "wallet_title": "Apple Wallet", "wallet_enable": "Activer Apple Wallet", "section_wallet_cards": "Cartes du portefeuille",
            "wallet_no_cards": "Aucune carte ajoutée", "section_add_card": "Ajouter une carte", "wallet_scan_card": "Scanner l'ID de la carte",
            "wallet_manual_input": "Saisie manuelle", "wallet_import_default_zip": "Importer la carte par défaut (ZIP)",
            
            "recording_sound_title": "Désactiver le son d'enregistrement", "tone_status": "État de la tonalité", "current_tone": "Tonalité actuelle",
            "pairing_not_found": "Fichier d'appairage introuvable", "check_tone_status": "Vérifier l'état de la tonalité", "tone_status_footer": "Vérifie si le fichier audio de l'appareil est le fichier Apple d'origine.",
            "backup_system": "Système de sauvegarde", "backup_status": "État de la sauvegarde", "backup_ready": "Sauvegarde prête", "refresh_backup_status": "Actualiser l'état",
            "backup_system_footer": "Lors de la première application, l'application extraira automatiquement le fichier d'origine.",
            "restore_default_sounds": "Restaurer les sons par défaut", "restore_footer": "Restaurer les sons d'origine à partir de la sauvegarde créée automatiquement.",
            
            "theme_store_downloaded": "Téléchargé", "theme_store_download_btn": "Télécharger", "theme_store_by_author": "par %@", "theme_store_repos": "Dépôts",
            "theme_store_theme_count": "%d thèmes", "theme_store_json_url": "URL JSON", "theme_store_json_desc": "Collez un JSON de thèmes direct ou un index.",
            "theme_store_loading": "Chargement...", "theme_store_empty": "Vide. Appuyez sur + pour ajouter.", "theme_store_delete_group": "Supprimer le groupe", "theme_store_delete_repo": "Supprimer le dépôt",
            
            "settings_run_test_header": "TEST D'EXÉCUTION (Accès WorseQuery)", "settings_run_test_btn": "Tester les autorisations de lecture/écriture de MobileGestalt",
            "settings_respring_header": "REDÉMARRAGE (NeoSpring)", "settings_respring_btn": "Redémarrer SpringBoard", "settings_tunnel_status": "Connexion Tunnel",
            "connection_status": "État de la connexion", "pairing_file": "Fichier d'appairage", "status_not_ready": "Non prêt",
            "import_pairing": "Importer l'appairage", "pair_on_device": "Appairer sur l'appareil (iOS 27+)", "button_reset_pairing": "Réinitialiser l'appairage",
            "settings_language": "Langue", "settings_accent_color": "Couleur d'accentuation", "settings_app_info": "Infos sur l'app",
            "color_orange": "Orange", "color_pink": "Rose", "color_mauve": "Mauve", "color_red": "Rouge", "color_green": "Vert", "color_blue": "Bleu",
            "app_ios": "iOS", "app_device": "Appareil", "app_info_footer": "iOS 27+: bad_query peut modifier le texte de l'écran de verrouillage et le fond d'écran PosterBoard. iOS 26 : Airlift uniquement.",
            
            "about_desc": "Merci d'utiliser Enswilde, reconstruit avec bad_query.", "button_donate": "Faire un don",
            "about_group_yang": "Groupe Telegram YangJiii", "about_group_ls": "Groupe Telegram LSNguyen", "about_contact": "Me contacter",
            "settings_thanks_to": "Remerciements", "credit_yang_support": "Pour m'avoir soutenu pendant le développement", "credit_yang_original": "Développeur original d'EnsWilde",
            "credit_ls_new": "Développeur du nouvel EnsWilde", "credit_forcequit_badquery": "Exploit Bad_query", "credit_johnny_airlift": "Exploit Airlift",
            "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "Ajustement de config, nouvelle logique MobileGestalt", "credit_likepass_sound": "Désactiver le son d'enregistrement d'appel (iOS 27)",
            "credit_little_34306_concept": "Concept original de désactivation du son d'enregistrement d'appel", "credit_yihooong_silent": "Pour les ressources de tonalité silencieuse et la recherche de remplacement.",
            "credit_kianuni_erosion": "Développeur Erosion-cn - Logique d'écriture et de rétablissement des ajustements", "credit_community": "Pour le soutien de mon projet.",
            "settings_translators": "Traducteurs", "translation_by": "Traduction %@ (%@)",
            
            "enable_tweak": "Activer l'ajustement", "mg_save_settings": "Enregistrer les paramètres", "mg_revert_tweaks": "Rétablir les ajustements",
            "mg_save_success_message": "Enregistré et appliqué avec succès. Redémarrez l'appareil pour qu'iOS prenne en compte la nouvelle configuration.",
            "mg_revert_success_message": "Tous les ajustements ont été rétablis avec succès. Allez dans RÉGLAGES et appuyez sur 'Redémarrer SpringBoard'.",
            "mg_revert_failed": "Échec du rétablissement :", "mg_init_failed": "Échec du chargement de MobileGestalt : %@",
            "mg_device_subtype_preset": "Préréglage du sous-type", "mg_subtype_none": "Aucun", "mg_subtype_2436": "2436 (Gestes iPhone X)",
            "mg_subtype_2556": "2556 (iPhone 14 Pro)", "mg_subtype_2796": "2796 (iPhone 14 Pro Max)", "mg_subtype_2976": "2976 (iPhone 15 Pro Max)",
            "mg_subtype_2622": "2622 (iPhone 16 Pro)", "mg_subtype_2868": "2868 (iPhone 16 Pro Max)", "mg_subtype_2736": "2736 (iPhone Air)",
            "mg_subtype_2662": "2662 (iPhone 18 Pro)", "mg_subtype_custom": "Sous-type personnalisé", "mg_enable_custom_subtype": "Activer le sous-type personnalisé",
            "mg_custom_subtype_placeholder": "Entrez ArtworkDeviceSubType (ex : 2xxx)", "mg_change_model_name": "Changer le nom du modèle",
            "mg_model_name_placeholder": "Nom du modèle", "mg_region": "Région", "mg_device_model": "Modèle d'appareil", "mg_device_model_unchanged": "inchangé",
            
            "manual_editor_fields": "Champs", "manual_editor_empty": "CacheExtra est vide.", "manual_editor_delete": "Supprimer", "manual_editor_save": "Enregistrer",
            "manual_editor_saving": "Enregistrement…", "manual_editor_revert": "Rétablir", "manual_editor_reverting": "Rétablissement…", "manual_editor_save_revert": "Enregistrer & Rétablir",
            "manual_editor_invalid_value": "Valeur invalide", "manual_editor_search": "Rechercher des clés…", "manual_editor_revert_confirm_title": "Rétablir tous les ajustements MobileGestalt ?",
            "manual_editor_revert_confirm_message": "Cela supprime le fichier de cache MobileGestalt actif. iOS en générera une copie propre au prochain redémarrage.",
            "manual_editor_key": "Clé", "manual_editor_key_placeholder": "Clé obscurcie (22 car.)", "manual_editor_type": "Type", "manual_editor_value": "Valeur",
            "manual_editor_add_field": "Ajouter un champ", "manual_editor_edit_field": "Modifier le champ", "manual_editor_placeholder_int": "ex : 1", "manual_editor_placeholder_real": "ex : 1.5",
            "manual_editor_placeholder_string": "Valeur chaîne", "manual_editor_placeholder_base64": "Base64", "manual_editor_placeholder_date": "ISO 8601",
            "manual_editor_placeholder_xml": "Fragment XML plist", "manual_editor_err_invalid_int": "Entrez un nombre entier valide.",
            "manual_editor_err_invalid_real": "Entrez un nombre décimal fini.", "manual_editor_err_invalid_bool": "Utilisez true ou false pour un booléen.",
            "manual_editor_err_invalid_date": "Entrez une date ISO 8601.", "manual_editor_err_invalid_data": "Entrez des données Base64 valides.", "manual_editor_err_invalid_xml": "Entrez un fragment XML plist valide.",
            
            "pair_enter_pin_title": "Entrez ce code PIN dans Réglages",
            "pair_step_instruction": "Réglages > Confidentialité et sécurité > Mode développeur > Pair with EnsWilde",
            "pair_success_title": "Appairage réussi !",
            "pair_start_btn": "Démarrer l'appairage sur l'appareil",
            "pair_background_info": "L'application a une exécution en arrière-plan infinie activée. Vous pouvez passer en toute sécurité aux Réglages pour saisir le code PIN sans qu'iOS ne la ferme.",
            
            "alert_ok": "OK", "alert_cancel": "Annuler", "alert_message_title": "Message", "alert_error": "Erreur", "alert_close": "Fermer", "button_add": "Ajouter", "save_changes": "Enregistrer"
        ],
        "ar": [
            "nav_home": "الرئيسية", "nav_theme_store": "متجر الثيمات", "nav_settings": "الإعدادات", "nav_about": "حول", "nav_apply": "تطبيق",
            "system_status": "حالة النظام", "status_ready": "جاهز", "section_tweaks": "تعديلات",
            "tool_mobile_gestalt": "MobileGestalt", "tool_mobile_gestalt_desc": "تعديل ملف MobileGestalt",
            "manual_editor_title": "محرر CacheExtra", "manual_editor_subtitle": "تعديل مفاتيح MobileGestalt يدويًا",
            "tool_config_tweaks": "تعديلات التكوين", "tool_config_tweaks_desc": "تخصيص تذييل شاشة القفل",
            "tool_passcode_theme": "ثيم رمز المرور", "tool_passcode_theme_desc": "تخصيص شاشة رمز المرور",
            "tool_apple_wallet": "Apple Wallet", "tool_apple_wallet_desc": "إدارة بطاقات المحفظة",
            "tool_disable_sound": "تعطيل صوت تسجيل المكالمات", "tool_disable_sound_desc": "تعطيل صوت تسجيل المكالمات",
            
            "section_hardware_features": "ميزات الأجهزة", "section_display_and_ui": "العرض والواجهة",
            "mg_boot_chime": "نغمة التشغيل", "mg_charge_limit": "حد الشحن", "mg_camera_button": "زر الكاميرا",
            "mg_stage_manager": "مدير المهام (Stage Manager)", "mg_aod": "العرض الدائم (AOD)", "mg_aod_vibrancy": "حيوية AOD", "mg_become_ipados": "التحول إلى iPadOS",
            
            "config_tweaks_title": "تعديلات التكوين", "config_enable_tweak": "تمكين التعديل", "config_lock_screen_footnote": "تذييل شاشة القفل",
            "config_footnote_placeholder": "أدخل نص شاشة القفل...", "config_supervision_title": "الإشراف (Supervision)", "config_enable_supervision": "تمكين الإشراف",
            "config_apply_save": "تطبيق وحفظ التغييرات", "config_restore_save": "استعادة وحفظ التغييرات",
            
            "passcode_theme_manager": "مدير ثيمات رمز المرور", "passcode_enable_theme": "تمكين ثيم رمز المرور", "global_settings": "إعدادات عامة",
            "passcode_language_method": "اللغة/الطريقة", "passcode_telephony_version": "إصدار Telephony", "section_theme_library": "مكتبة الثيمات",
            "section_theme_settings": "إعدادات الثيم", "passcode_theme_name": "اسم الثيم", "passcode_detected_size": "الحجم المكتشف",
            "passcode_target_key_size": "حجم المفتاح المستهدف", "passcode_selected_theme": "الثيم المحدد", "passcode_selected": "محدد",
            "passcode_theme_selected": "سيتم تطبيق هذا الثيم", "section_theme_files": "ملفات الثيم", "section_danger_zone": "منطقة الخطر",
            "passcode_delete_theme": "حذف الثيم",
            
            "wallet_title": "Apple Wallet", "wallet_enable": "تمكين Apple Wallet", "section_wallet_cards": "بطاقات المحفظة",
            "wallet_no_cards": "لم تتم إضافة بطاقات", "section_add_card": "إضافة بطاقة", "wallet_scan_card": "مسح معرف البطاقة",
            "wallet_manual_input": "إدخال يدوي", "wallet_import_default_zip": "استيراد البطاقة الافتراضية (ZIP)",
            
            "recording_sound_title": "تعطيل صوت تسجيل المكالمات", "tone_status": "حالة النغمة", "current_tone": "النغمة الحالية",
            "pairing_not_found": "ملف الاقتران غير موجود", "check_tone_status": "التحقق من حالة النغمة", "tone_status_footer": "يتحقق مما إذا كان ملف الصوت على الجهاز هو ملف Apple الأصلي.",
            "backup_system": "نظام النسخ الاحتياطي", "backup_status": "حالة النسخ الاحتياطي", "backup_ready": "النسخ الاحتياطي جاهز", "refresh_backup_status": "تحديث حالة النسخ الاحتياطي",
            "backup_system_footer": "في أول تطبيق، سيقوم التطبيق تلقائيًا باستخراج الملف الأصلي إلى مساحة تخزين الجهاز.",
            "restore_default_sounds": "استعادة الأصوات الافتراضية", "restore_footer": "استعادة الأصوات الأصلية من النسخة الاحتياطية التي تم إنشاؤها تلقائيًا.",
            
            "theme_store_downloaded": "تم التحميل", "theme_store_download_btn": "تحميل", "theme_store_by_author": "بواسطة %@", "theme_store_repos": "المستودعات",
            "theme_store_theme_count": "%d ثيمات", "theme_store_json_url": "رابط JSON", "theme_store_json_desc": "الصق JSON مباشر أو رابط فهرس.",
            "theme_store_loading": "جاري التحميل...", "theme_store_empty": "فارغ. اضغط + للإضافة.", "theme_store_delete_group": "حذف المجموعة", "theme_store_delete_repo": "حذف المستودع",
            
            "settings_run_test_header": "تشغيل الاختبار (WorseQuery)", "settings_run_test_btn": "اختبار أذونات القراءة/الكتابة لـ MobileGestalt",
            "settings_respring_header": "إعادة تشغيل (NeoSpring)", "settings_respring_btn": "إعادة تشغيل الجهاز (Respring)", "settings_tunnel_status": "اتصال النفق (Tunnel)",
            "connection_status": "حالة الاتصال", "pairing_file": "ملف الاقتران", "status_not_ready": "غير جاهز",
            "import_pairing": "استيراد الاقتران", "pair_on_device": "الاقتران على الجهاز (iOS 27+)", "button_reset_pairing": "إعادة تعيين الاقتران",
            "settings_language": "اللغة", "settings_accent_color": "لون التمييز", "settings_app_info": "معلومات التطبيق",
            "color_orange": "برتقالي", "color_pink": "وردي", "color_mauve": "أرجواني", "color_red": "أحمر", "color_green": "أخضر", "color_blue": "أزرق",
            "app_ios": "iOS", "app_device": "الجهاز", "app_info_footer": "iOS 27+: يمكن لـ bad_query تعديل نص شاشة القفل وخلفية PosterBoard. iOS 26: Airlift فقط.",
            
            "about_desc": "شكرًا لاستخدامك Enswilde، تم إعادة بنائه باستخدام bad_query.", "button_donate": "تبرع",
            "about_group_yang": "مجموعة تليجرام YangJiii", "about_group_ls": "مجموعة تليجرام LSNguyen", "about_contact": "اتصل بي",
            "settings_thanks_to": "شكر وتقدير", "credit_yang_support": "لدعمي أثناء التطوير", "credit_yang_original": "المطور الأصلي لـ EnsWilde",
            "credit_ls_new": "مطور EnsWilde الجديد", "credit_forcequit_badquery": "استغلال Bad_query", "credit_johnny_airlift": "استغلال Airlift",
            "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "تعديل التكوين، منطق MobileGestalt الجديد", "credit_likepass_sound": "تعطيل صوت تسجيل المكالمات (iOS 27)",
            "credit_little_34306_concept": "الفكرة الأصلية لتعطيل صوت تسجيل المكالمات", "credit_yihooong_silent": "لأصول النغمة الصامتة وأبحاث الاستبدال.",
            "credit_kianuni_erosion": "مطور Erosion-cn - كتابة ومنطق إرجاع التعديلات", "credit_community": "لدعم مشروعي.",
            "settings_translators": "المترجمون", "translation_by": "ترجمة %@ (%@)",
            
            "enable_tweak": "تمكين التعديل", "mg_save_settings": "حفظ الإعدادات", "mg_revert_tweaks": "إرجاع التعديلات",
            "mg_save_success_message": "تم الحفظ والتطبيق بنجاح. أعد تشغيل الجهاز بقوة ليتعرف iOS على التكوين الجديد.",
            "mg_revert_success_message": "تم إرجاع جميع التعديلات بنجاح. انتقل إلى الإعدادات واضغط على 'إعادة تشغيل الجهاز'.",
            "mg_revert_failed": "فشل الإرجاع:", "mg_init_failed": "فشل تحميل MobileGestalt: %@",
            "mg_device_subtype_preset": "إعداد مسبق للنوع الفرعي", "mg_subtype_none": "لا شيء", "mg_subtype_2436": "2436 (إيماءات iPhone X)",
            "mg_subtype_2556": "2556 (iPhone 14 Pro)", "mg_subtype_2796": "2796 (iPhone 14 Pro Max)", "mg_subtype_2976": "2976 (iPhone 15 Pro Max)",
            "mg_subtype_2622": "2622 (iPhone 16 Pro)", "mg_subtype_2868": "2868 (iPhone 16 Pro Max)", "mg_subtype_2736": "2736 (iPhone Air)",
            "mg_subtype_2662": "2662 (iPhone 18 Pro)", "mg_subtype_custom": "نوع فرعي مخصص", "mg_enable_custom_subtype": "تمكين النوع الفرعي المخصص",
            "mg_custom_subtype_placeholder": "أدخل ArtworkDeviceSubType (مثال: 2xxx)", "mg_change_model_name": "تغيير اسم طراز الجهاز",
            "mg_model_name_placeholder": "اسم الطراز", "mg_region": "المنطقة", "mg_device_model": "طراز الجهاز", "mg_device_model_unchanged": "دون تغيير",
            
            "manual_editor_fields": "الحقول", "manual_editor_empty": "CacheExtra فارغ.", "manual_editor_delete": "حذف", "manual_editor_save": "حفظ الإعدادات",
            "manual_editor_saving": "جاري الحفظ…", "manual_editor_revert": "إرجاع التعديلات", "manual_editor_reverting": "جاري الإرجاع…", "manual_editor_save_revert": "حفظ وإرجاع",
            "manual_editor_invalid_value": "قيمة غير صالحة", "manual_editor_search": "البحث عن مفاتيح…", "manual_editor_revert_confirm_title": "إرجاع كل تعديلات MobileGestalt؟",
            "manual_editor_revert_confirm_message": "سيؤدي هذا إلى حذف ملف ذاكرة التخزين المؤقت المباشر MobileGestalt. سيقوم iOS بإنشاء نسخة نظيفة عند إعادة التشغيل التالية.",
            "manual_editor_key": "المفتاح", "manual_editor_key_placeholder": "مفتاح مبهم (22 حرفًا)", "manual_editor_type": "النوع", "manual_editor_value": "القيمة",
            "manual_editor_add_field": "إضافة حقل", "manual_editor_edit_field": "تعديل الحقل", "manual_editor_placeholder_int": "مثال: 1", "manual_editor_placeholder_real": "مثال: 1.5",
            "manual_editor_placeholder_string": "قيمة نصية", "manual_editor_placeholder_base64": "Base64", "manual_editor_placeholder_date": "ISO 8601",
            "manual_editor_placeholder_xml": "جزء XML plist", "manual_editor_err_invalid_int": "أدخل عددًا صحيحًا صالحًا.",
            "manual_editor_err_invalid_real": "أدخل عددًا عشريًا صالحًا.", "manual_editor_err_invalid_bool": "استخدم true أو false لقيمة منطقية.",
            "manual_editor_err_invalid_date": "أدخل تاريخ ISO 8601.", "manual_editor_err_invalid_data": "أدخل بيانات Base64 صالحة.", "manual_editor_err_invalid_xml": "أدخل جزء XML plist صالح.",
            
            "pair_enter_pin_title": "أدخل رمز PIN هذا في الإعدادات",
            "pair_step_instruction": "الإعدادات > الخصوصية والأمان > وضع المطور > Pair with EnsWilde",
            "pair_success_title": "نجح الاقتران!",
            "pair_start_btn": "بدء الاقتران على الجهاز",
            "pair_background_info": "تم تفعيل التشغيل غير المحدود في الخلفية للتطبيق. يمكنك الانتقال بأمان إلى الإعدادات لإدخال رمز PIN دون قلق من إيقاف iOS له.",
            
            "alert_ok": "موافق", "alert_cancel": "إلغاء", "alert_message_title": "رسالة", "alert_error": "خطأ", "alert_close": "إغلاق", "button_add": "إضافة", "save_changes": "حفظ التغييرات"
        ],
        "es": [
            "nav_home": "Inicio", "nav_theme_store": "Tienda de temas", "nav_settings": "Ajustes", "nav_about": "Acerca de", "nav_apply": "Aplicar",
            "system_status": "Estado del sistema", "status_ready": "Listo", "section_tweaks": "Ajustes",
            "tool_mobile_gestalt": "MobileGestalt", "tool_mobile_gestalt_desc": "Modificar archivo MobileGestalt",
            "manual_editor_title": "Editor CacheExtra", "manual_editor_subtitle": "Editar manualmente claves MobileGestalt",
            "tool_config_tweaks": "Ajustes de configuración", "tool_config_tweaks_desc": "Nota al pie de pantalla de bloqueo",
            "tool_passcode_theme": "Tema de contraseña", "tool_passcode_theme_desc": "Personalizar pantalla de contraseña",
            "tool_apple_wallet": "Apple Wallet", "tool_apple_wallet_desc": "Gestionar tarjetas",
            "tool_disable_sound": "Desactivar sonido de grabación", "tool_disable_sound_desc": "Desactivar sonido de grabación de llamadas",
            
            "section_hardware_features": "Funciones de hardware", "section_display_and_ui": "Pantalla e interfaz",
            "mg_boot_chime": "Sonido de arranque", "mg_charge_limit": "Límite de carga", "mg_camera_button": "Botón de cámara",
            "mg_stage_manager": "Stage Manager", "mg_aod": "Pantalla siempre activa (AOD)", "mg_aod_vibrancy": "Vibrancia AOD", "mg_become_ipados": "Convertirse en iPadOS",
            
            "config_tweaks_title": "Ajustes de configuración", "config_enable_tweak": "Activar ajuste", "config_lock_screen_footnote": "Nota al pie",
            "config_footnote_placeholder": "Ingresa texto de pantalla de bloqueo...", "config_supervision_title": "Supervisión", "config_enable_supervision": "Activar supervisión",
            "config_apply_save": "Aplicar y guardar cambios", "config_restore_save": "Restaurar y guardar cambios",
            
            "passcode_theme_manager": "Gestor de temas de contraseña", "passcode_enable_theme": "Activar tema de contraseña", "global_settings": "Ajustes globales",
            "passcode_language_method": "Idioma/Método", "passcode_telephony_version": "Versión de Telephony", "section_theme_library": "Biblioteca de temas",
            "section_theme_settings": "Ajustes del tema", "passcode_theme_name": "Nombre del tema", "passcode_detected_size": "Tamaño detectado",
            "passcode_target_key_size": "Tamaño de tecla objetivo", "passcode_selected_theme": "Tema seleccionado", "passcode_selected": "Seleccionado",
            "passcode_theme_selected": "Este tema será aplicado", "section_theme_files": "Archivos del tema", "section_danger_zone": "Zona de peligro",
            "passcode_delete_theme": "Eliminar tema",
            
            "wallet_title": "Apple Wallet", "wallet_enable": "Activar Apple Wallet", "section_wallet_cards": "Tarjetas de wallet",
            "wallet_no_cards": "No hay tarjetas añadidas", "section_add_card": "Añadir tarjeta", "wallet_scan_card": "Escanear ID de tarjeta",
            "wallet_manual_input": "Entrada manual", "wallet_import_default_zip": "Importar tarjeta predeterminada (ZIP)",
            
            "recording_sound_title": "Desactivar sonido de grabación", "tone_status": "Estado del tono", "current_tone": "Tono actual",
            "pairing_not_found": "Archivo de emparejamiento no encontrado", "check_tone_status": "Verificar estado del tono", "tone_status_footer": "Comprueba si el archivo de audio del dispositivo es el archivo original de Apple.",
            "backup_system": "Sistema de copia de seguridad", "backup_status": "Estado de la copia", "backup_ready": "Copia lista", "refresh_backup_status": "Actualizar estado",
            "backup_system_footer": "En la primera aplicación, la app extraerá automáticamente el archivo original al almacenamiento del dispositivo.",
            "restore_default_sounds": "Restaurar sonidos predeterminados", "restore_footer": "Restaurar sonidos originales desde la copia de seguridad creada automáticamente.",
            
            "theme_store_downloaded": "Descargado", "theme_store_download_btn": "Descargar", "theme_store_by_author": "por %@", "theme_store_repos": "Repositorios",
            "theme_store_theme_count": "%d temas", "theme_store_json_url": "URL del JSON", "theme_store_json_desc": "Pega un JSON de temas directo o un índice.",
            "theme_store_loading": "Cargando...", "theme_store_empty": "Vacío. Toca + para añadir.", "theme_store_delete_group": "Eliminar grupo", "theme_store_delete_repo": "Eliminar repositorio",
            
            "settings_run_test_header": "EJECUTAR PRUEBA (Acceso WorseQuery)", "settings_run_test_btn": "Probar permisos de lectura/escritura de MobileGestalt",
            "settings_respring_header": "RESPRING (NeoSpring)", "settings_respring_btn": "Reiniciar SpringBoard", "settings_tunnel_status": "Conexión de túnel",
            "connection_status": "Estado de conexión", "pairing_file": "Archivo de emparejamiento", "status_not_ready": "No listo",
            "import_pairing": "Importar emparejamiento", "pair_on_device": "Emparejar en dispositivo (iOS 27+)", "button_reset_pairing": "Restablecer emparejamiento",
            "settings_language": "Idioma", "settings_accent_color": "Color de acento", "settings_app_info": "Información de la app",
            "color_orange": "Naranja", "color_pink": "Rosa", "color_mauve": "Malva", "color_red": "Rojo", "color_green": "Verde", "color_blue": "Azul",
            "app_ios": "iOS", "app_device": "Dispositivo", "app_info_footer": "iOS 27+: bad_query puede modificar el texto de la pantalla de bloqueo y el fondo de pantalla PosterBoard. iOS 26: solo Airlift.",
            
            "about_desc": "Gracias por usar Enswilde, reconstruido con bad_query.", "button_donate": "Donar",
            "about_group_yang": "Grupo de Telegram YangJiii", "about_group_ls": "Grupo de Telegram LSNguyen", "about_contact": "Contáctame",
            "settings_thanks_to": "Agradecimientos", "credit_yang_support": "Por apoyarme durante el desarrollo", "credit_yang_original": "Desarrollador original de EnsWilde",
            "credit_ls_new": "Desarrollador del nuevo EnsWilde", "credit_forcequit_badquery": "Exploit Bad_query", "credit_johnny_airlift": "Exploit Airlift",
            "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "Ajuste de configuración, nueva lógica de MobileGestalt", "credit_likepass_sound": "Desactivar sonido de grabación de llamadas (iOS 27)",
            "credit_little_34306_concept": "Concepto original para desactivar el sonido de grabación de llamadas", "credit_yihooong_silent": "Por los recursos de tono silencioso y la investigación de reemplazo.",
            "credit_kianuni_erosion": "Desarrollador de Erosion-cn - Lógica de escritura y reversión de ajustes", "credit_community": "Por apoyar mi proyecto.",
            "settings_translators": "Traductores", "translation_by": "Traducción de %@ (%@)",
            
            "enable_tweak": "Activar ajuste", "mg_save_settings": "Guardar ajustes", "mg_revert_tweaks": "Revertir ajustes",
            "mg_save_success_message": "Guardado y aplicado con éxito. Reinicia el dispositivo para que iOS detecte la nueva configuración.",
            "mg_revert_success_message": "Todos los ajustes se revirtieron con éxito. Ve a AJUSTES y toca 'Reiniciar SpringBoard'.",
            "mg_revert_failed": "Error al revertir:", "mg_init_failed": "Error al cargar MobileGestalt: %@",
            "mg_device_subtype_preset": "Preajuste de subtipo", "mg_subtype_none": "Ninguno", "mg_subtype_2436": "2436 (Gestos iPhone X)",
            "mg_subtype_2556": "2556 (iPhone 14 Pro)", "mg_subtype_2796": "2796 (iPhone 14 Pro Max)", "mg_subtype_2976": "2976 (iPhone 15 Pro Max)",
            "mg_subtype_2622": "2622 (iPhone 16 Pro)", "mg_subtype_2868": "2868 (iPhone 16 Pro Max)", "mg_subtype_2736": "2736 (iPhone Air)",
            "mg_subtype_2662": "2662 (iPhone 18 Pro)", "mg_subtype_custom": "Subtipo personalizado", "mg_enable_custom_subtype": "Activar subtipo personalizado",
            "mg_custom_subtype_placeholder": "Ingresa ArtworkDeviceSubType (ej. 2xxx)", "mg_change_model_name": "Cambiar nombre del modelo",
            "mg_model_name_placeholder": "Nombre del modelo", "mg_region": "Región", "mg_device_model": "Modelo del dispositivo", "mg_device_model_unchanged": "sin cambios",
            
            "manual_editor_fields": "Campos", "manual_editor_empty": "CacheExtra está vacío.", "manual_editor_delete": "Eliminar", "manual_editor_save": "Guardar",
            "manual_editor_saving": "Guardando…", "manual_editor_revert": "Revertir", "manual_editor_reverting": "Revirtiendo…", "manual_editor_save_revert": "Guardar y revertir",
            "manual_editor_invalid_value": "Valor inválido", "manual_editor_search": "Buscar claves…", "manual_editor_revert_confirm_title": "¿Revertir todos los ajustes de MobileGestalt?",
            "manual_editor_revert_confirm_message": "Esto elimina el archivo de caché activo de MobileGestalt. iOS generará una copia limpia en el próximo reinicio.",
            "manual_editor_key": "Clave", "manual_editor_key_placeholder": "Clave ofuscada (22 caracteres)", "manual_editor_type": "Tipo", "manual_editor_value": "Valor",
            "manual_editor_add_field": "Añadir campo", "manual_editor_edit_field": "Editar campo", "manual_editor_placeholder_int": "ej. 1", "manual_editor_placeholder_real": "ej. 1.5",
            "manual_editor_placeholder_string": "Valor de cadena", "manual_editor_placeholder_base64": "Base64", "manual_editor_placeholder_date": "ISO 8601",
            "manual_editor_placeholder_xml": "Fragmento XML plist", "manual_editor_err_invalid_int": "Ingresa un número entero válido.",
            "manual_editor_err_invalid_real": "Ingresa un número decimal finito.", "manual_editor_err_invalid_bool": "Usa true o false para un valor booleano.",
            "manual_editor_err_invalid_date": "Ingresa una fecha ISO 8601.", "manual_editor_err_invalid_data": "Ingresa datos Base64 válidos.", "manual_editor_err_invalid_xml": "Ingresa un fragmento XML plist válido.",
            
            "pair_enter_pin_title": "Ingresa este PIN en Ajustes",
            "pair_step_instruction": "Ajustes > Privacidad y seguridad > Modo desarrollador > Pair with EnsWilde",
            "pair_success_title": "¡Emparejamiento exitoso!",
            "pair_start_btn": "Iniciar emparejamiento en el dispositivo",
            "pair_background_info": "La app tiene habilitada la ejecución en segundo plano infinita. Puedes cambiar a Ajustes de forma segura para ingresar el PIN sin que iOS la cierre.",
            
            "alert_ok": "OK", "alert_cancel": "Cancelar", "alert_message_title": "Mensaje", "alert_error": "Error", "alert_close": "Cerrar", "button_add": "Añadir", "save_changes": "Guardar cambios"
        ],
        "ru": [
            "nav_home": "Главная", "nav_theme_store": "Магазин тем", "nav_settings": "Настройки", "nav_about": "О программе", "nav_apply": "Применить",
            "system_status": "Состояние системы", "status_ready": "Готово", "section_tweaks": "Твики",
            "tool_mobile_gestalt": "MobileGestalt", "tool_mobile_gestalt_desc": "Изменить файл MobileGestalt",
            "manual_editor_title": "Редактор CacheExtra", "manual_editor_subtitle": "Ручное редактирование ключей MobileGestalt",
            "tool_config_tweaks": "Настройка конфигурации", "tool_config_tweaks_desc": "Сноска на экране блокировки",
            "tool_passcode_theme": "Тема пароля", "tool_passcode_theme_desc": "Настроить экран пароля",
            "tool_apple_wallet": "Apple Wallet", "tool_apple_wallet_desc": "Управление картами",
            "tool_disable_sound": "Отключить звук записи звонков", "tool_disable_sound_desc": "Отключить звук записи звонков",
            
            "section_hardware_features": "Аппаратные функции", "section_display_and_ui": "Дисплей и интерфейс",
            "mg_boot_chime": "Звук загрузки", "mg_charge_limit": "Ограничение заряда", "mg_camera_button": "Кнопка камеры",
            "mg_stage_manager": "Stage Manager", "mg_aod": "Always-on Display (AOD)", "mg_aod_vibrancy": "Яркость AOD", "mg_become_ipados": "Режим iPadOS",
            
            "config_tweaks_title": "Настройка конфигурации", "config_enable_tweak": "Включить твик", "config_lock_screen_footnote": "Сноска на экране блокировки",
            "config_footnote_placeholder": "Введите текст для экрана блокировки...", "config_supervision_title": "Наблюдение (Supervision)", "config_enable_supervision": "Включить наблюдение",
            "config_apply_save": "Применить и сохранить изменения", "config_restore_save": "Восстановить изменения",
            
            "passcode_theme_manager": "Менеджер тем пароля", "passcode_enable_theme": "Включить тему пароля", "global_settings": "Глобальные настройки",
            "passcode_language_method": "Язык/Метод", "passcode_telephony_version": "Версия Telephony", "section_theme_library": "Библиотека тем",
            "section_theme_settings": "Настройки темы", "passcode_theme_name": "Название темы", "passcode_detected_size": "Обнаруженный размер",
            "passcode_target_key_size": "Целевой размер клавиши", "passcode_selected_theme": "Выбранная тема", "passcode_selected": "Выбрано",
            "passcode_theme_selected": "Эта тема будет применена", "section_theme_files": "Файлы темы", "section_danger_zone": "Опасная зона",
            "passcode_delete_theme": "Удалить тему",
            
            "wallet_title": "Apple Wallet", "wallet_enable": "Включить Apple Wallet", "section_wallet_cards": "Карты в кошельке",
            "wallet_no_cards": "Карты не добавлены", "section_add_card": "Добавить карту", "wallet_scan_card": "Сканировать ID карты",
            "wallet_manual_input": "Ручной ввод", "wallet_import_default_zip": "Импорт стандартной карты (ZIP)",
            
            "recording_sound_title": "Отключить звук записи звонков", "tone_status": "Состояние звука", "current_tone": "Текущий звук",
            "pairing_not_found": "Файл сопряжения не найден", "check_tone_status": "Проверить состояние звука", "tone_status_footer": "Проверяет, является ли аудиофайл на устройстве оригинальным файлом Apple.",
            "backup_system": "Система резервного копирования", "backup_status": "Состояние резервной копии", "backup_ready": "Копия готова", "refresh_backup_status": "Обновить состояние",
            "backup_system_footer": "При первом применении приложение автоматически извлечет исходный файл в хранилище устройства.",
            "restore_default_sounds": "Восстановить стандартные звуки", "restore_footer": "Восстановить исходные звуки из автоматически созданной резервной копии.",
            
            "theme_store_downloaded": "Загружено", "theme_store_download_btn": "Скачать", "theme_store_by_author": "от %@", "theme_store_repos": "Репозитории",
            "theme_store_theme_count": "%d тем", "theme_store_json_url": "URL-адрес JSON", "theme_store_json_desc": "Вставьте прямой JSON тем или индекс.",
            "theme_store_loading": "Загрузка...", "theme_store_empty": "Пусто. Нажмите +, чтобы добавить.", "theme_store_delete_group": "Удалить группу", "theme_store_delete_repo": "Удалить репозиторий",
            
            "settings_run_test_header": "ЗАПУСТИТЬ ТЕСТ (Доступ WorseQuery)", "settings_run_test_btn": "Проверить права чтения/записи MobileGestalt",
            "settings_respring_header": "RESPRING (NeoSpring)", "settings_respring_btn": "Перезапустить SpringBoard", "settings_tunnel_status": "Туннельное соединение",
            "connection_status": "Состояние подключения", "pairing_file": "Файл сопряжения", "status_not_ready": "Не готово",
            "import_pairing": "Импорт сопряжения", "pair_on_device": "Сопряжение на устройстве (iOS 27+)", "button_reset_pairing": "Сбросить сопряжение",
            "settings_language": "Язык", "settings_accent_color": "Цвет акцента", "settings_app_info": "Информация о приложении",
            "color_orange": "Оранжевый", "color_pink": "Розовый", "color_mauve": "Бледно-лиловый", "color_red": "Красный", "color_green": "Зеленый", "color_blue": "Синий",
            "app_ios": "iOS", "app_device": "Устройство", "app_info_footer": "iOS 27+: bad_query может изменять текст на экране блокировки и обои PosterBoard. iOS 26: только Airlift.",
            
            "about_desc": "Спасибо за использование Enswilde, пересобрано с bad_query.", "button_donate": "Пожертвовать",
            "about_group_yang": "Группа Telegram YangJiii", "about_group_ls": "Группа Telegram LSNguyen", "about_contact": "Связаться со мной",
            "settings_thanks_to": "Благодарности", "credit_yang_support": "За поддержку во время разработки", "credit_yang_original": "Оригинальный разработчик EnsWilde",
            "credit_ls_new": "Разработчик нового EnsWilde", "credit_forcequit_badquery": "Эксплойт Bad_query", "credit_johnny_airlift": "Эксплойт Airlift",
            "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "Настройка конфигурации, новая логика MobileGestalt", "credit_likepass_sound": "Отключить звук записи звонков (iOS 27)",
            "credit_little_34306_concept": "Оригинальная концепция отключения звука записи звонков", "credit_yihooong_silent": "За ресурсы беззвучного тона и исследования замены.",
            "credit_kianuni_erosion": "Разработчик Erosion-cn - Логика применения и отмены твиков", "credit_community": "За поддержку моего проекта.",
            "settings_translators": "Переводчики", "translation_by": "Перевод %@ (%@)",
            
            "enable_tweak": "Включить твик", "mg_save_settings": "Сохранить настройки", "mg_revert_tweaks": "Отменить твики",
            "mg_save_success_message": "Успешно сохранено и применено. Выполните жесткую перезагрузку устройства, чтобы iOS обнаружила новую конфигурацию.",
            "mg_revert_success_message": "Все твики успешно отменены. Перейдите в НАСТРОЙКИ и нажмите 'Перезапустить SpringBoard'.",
            "mg_revert_failed": "Ошибка отмены:", "mg_init_failed": "Не удалось загрузить MobileGestalt: %@",
            "mg_device_subtype_preset": "Пресет подтипа устройства", "mg_subtype_none": "Нет", "mg_subtype_2436": "2436 (Жесты iPhone X)",
            "mg_subtype_2556": "2556 (iPhone 14 Pro)", "mg_subtype_2796": "2796 (iPhone 14 Pro Max)", "mg_subtype_2976": "2976 (iPhone 15 Pro Max)",
            "mg_subtype_2622": "2622 (iPhone 16 Pro)", "mg_subtype_2868": "2868 (iPhone 16 Pro Max)", "mg_subtype_2736": "2736 (iPhone Air)",
            "mg_subtype_2662": "2662 (iPhone 18 Pro)", "mg_subtype_custom": "Пользовательский подтип", "mg_enable_custom_subtype": "Включить пользовательский подтип",
            "mg_custom_subtype_placeholder": "Введите ArtworkDeviceSubType (например, 2xxx)", "mg_change_model_name": "Изменить название модели",
            "mg_model_name_placeholder": "Название модели", "mg_region": "Регион", "mg_device_model": "Модель устройства", "mg_device_model_unchanged": "без изменений",
            
            "manual_editor_fields": "Поля", "manual_editor_empty": "CacheExtra пуст.", "manual_editor_delete": "Удалить", "manual_editor_save": "Сохранить",
            "manual_editor_saving": "Сохранение…", "manual_editor_revert": "Отменить", "manual_editor_reverting": "Отмена…", "manual_editor_save_revert": "Сохранить и отменить",
            "manual_editor_invalid_value": "Неверное значение", "manual_editor_search": "Поиск ключей…", "manual_editor_revert_confirm_title": "Отменить все твики MobileGestalt?",
            "manual_editor_revert_confirm_message": "Это удалит активный файл кэша MobileGestalt. iOS создаст чистую копию при следующей перезагрузке.",
            "manual_editor_key": "Ключ", "manual_editor_key_placeholder": "Обфусцированный ключ (22 символа)", "manual_editor_type": "Тип", "manual_editor_value": "Значение",
            "manual_editor_add_field": "Добавить поле", "manual_editor_edit_field": "Редактировать поле", "manual_editor_placeholder_int": "напр. 1", "manual_editor_placeholder_real": "напр. 1.5",
            "manual_editor_placeholder_string": "Строковое значение", "manual_editor_placeholder_base64": "Base64", "manual_editor_placeholder_date": "ISO 8601",
            "manual_editor_placeholder_xml": "Фрагмент XML plist", "manual_editor_err_invalid_int": "Введите корректное целое число.",
            "manual_editor_err_invalid_real": "Введите корректное десятичное число.", "manual_editor_err_invalid_bool": "Используйте true или false для логического значения.",
            "manual_editor_err_invalid_date": "Введите дату в формате ISO 8601.", "manual_editor_err_invalid_data": "Введите корректные данные Base64.", "manual_editor_err_invalid_xml": "Введите корректный фрагмент XML plist.",
            
            "pair_enter_pin_title": "Введите этот PIN-код в Настройках",
            "pair_step_instruction": "Настройки > Конфиденциальность и безопасность > Режим разработчика > Pair with EnsWilde",
            "pair_success_title": "Сопряжение успешно!",
            "pair_start_btn": "Начать сопряжение на устройстве",
            "pair_background_info": "В приложении включено бесконечное фоновое выполнение. Вы можете безопасно перейти в Настройки, чтобы ввести PIN-код, не опасаясь, что iOS закроет приложение.",
            
            "alert_ok": "ОК", "alert_cancel": "Отмена", "alert_message_title": "Сообщение", "alert_error": "Ошибка", "alert_close": "Закрыть", "button_add": "Добавить", "save_changes": "Сохранить изменения"
        ]
    ]

    private init() {
        self.currentLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
        objectWillChange.send()
    }

    /// Lấy chuỗi đã bản địa hóa (Hỗ trợ map mã ngôn ngữ linh hoạt)
    func string(for key: String) -> String {
        // Lấy mã ngôn ngữ và chuẩn hóa (vd: zh_CN -> zh-CN, vi_VN -> vi, ar_SA -> ar)
        let rawCode = currentLanguage.lowercased()
        var langCode = rawCode.components(separatedBy: CharacterSet(charactersIn: "-_")).first ?? "en"
        
        if rawCode.contains("zh") {
            langCode = rawCode.contains("tw") || rawCode.contains("hant") ? "zh-TW" : "zh-CN"
        }
        
        // 1. Ưu tiên tìm trong từ điển của ngôn ngữ hiện tại
        if let val = dict[langCode]?[key] {
            return val
        }
        
        // 2. Fallback về tiếng Anh nếu không có bản dịch
        if let val = dict["en"]?[key] {
            return val
        }
        
        // 3. CƠ CHẾ TỰ ĐỘNG FORMAT KEY (Nếu sau này có thêm key mới mà quên dịch)
        // Ví dụ: "section_my_new_feature" -> "Section My New Feature"
        let formattedKey = key
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        
        return formattedKey
    }

    /// Kiểm tra xem ngôn ngữ có sẵn trong từ điển không
    func hasLanguage(_ code: String) -> Bool {
        let rawCode = code.lowercased()
        if rawCode.contains("zh") {
            return true
        }
        let langCode = rawCode.components(separatedBy: CharacterSet(charactersIn: "-_")).first ?? ""
        return dict[langCode] != nil
    }
}

// MARK: - Convenience Functions
func L(_ key: String) -> String {
    return LocalizationManager.shared.string(for: key)
}