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

    // TỪ ĐIỂN CHUẨN 100% - FULL 9 NGÔN NGỮ
    private let dict: [String: [String: String]] = [
        "en": [
            "nav_home": "Home", "nav_theme_store": "Theme Store", "nav_settings": "Settings", "nav_about": "About", "nav_apply": "Apply",
            "section_tweaks": "Tweaks", "settings_run_test_header": "RUN TEST (WorseQuery Access)", "settings_run_test_btn": "Test MobileGestalt read/write permissions", "settings_respring_header": "RESPRING (NeoSpring)", "settings_respring_btn": "Respring Device", "settings_tunnel_status": "Tunnel Connection",
            "theme_store_repos": "Repositories", "theme_store_theme_count": "%d themes", "theme_store_by_author": "by %@", "theme_store_download_btn": "Download", "theme_store_json_url": "JSON URL", "theme_store_json_desc": "Paste a direct themes JSON or an index.",
            "translation_by": "%@ (%@) translation", "credit_community": "For support my project.", "credit_yang_support": "For supporting me during development", "credit_yang_original": "Original developer of EnsWilde", "credit_ls_new": "Developer of new EnsWilde", "credit_forcequit_badquery": "Bad_query exploit", "credit_johnny_airlift": "Airlift exploit", "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "Config tweak, new logic mobilegestalt", "credit_likepass_sound": "Disable Call Recording Sound (iOS 27)", "credit_little_34306_concept": "Original concept of disable call recording sound", "credit_yihooong_silent": "For the silent tone assets and replacement research.", "credit_kianuni_erosion": "Erosion-cn Developer - Write & Revert tweaks logic",
            "tool_mobile_gestalt": "MobileGestalt", "enable_tweak": "Enable Tweak", "save_changes": "Save Changes", "alert_ok": "OK", "alert_cancel": "Cancel",
            "mg_save_success_message": "Saved and applied successfully. Hard reboot the device so iOS picks up the new configuration.", "mg_revert_success_message": "All tweaks reverted successfully. Please go to SETTINGS and tap 'Respring Device' to apply the changes.", "mg_revert_failed": "Revert failed:", "mg_init_failed": "Failed to load MobileGestalt: %@"
        ],
        "vi": [
            "nav_home": "Trang chủ", "nav_theme_store": "Kho giao diện", "nav_settings": "Cài đặt", "nav_about": "Giới thiệu", "nav_apply": "Áp dụng",
            "section_tweaks": "Tinh chỉnh", "settings_run_test_header": "CHẠY THỬ NGHIỆM (WorseQuery)", "settings_run_test_btn": "Kiểm tra quyền đọc/ghi MobileGestalt", "settings_respring_header": "RESPRING (NeoSpring)", "settings_respring_btn": "Khởi động lại SpringBoard", "settings_tunnel_status": "Kết nối Tunnel",
            "theme_store_repos": "Kho lưu trữ", "theme_store_theme_count": "%d giao diện", "theme_store_by_author": "bởi %@", "theme_store_download_btn": "Tải xuống", "theme_store_json_url": "Đường dẫn JSON", "theme_store_json_desc": "Dán JSON trực tiếp hoặc liên kết index.",
            "translation_by": "Bản dịch %@ (%@)", "credit_community": "Đã hỗ trợ dự án của tôi.", "credit_yang_support": "Đã hỗ trợ tôi trong quá trình phát triển", "credit_yang_original": "Nhà phát triển gốc của EnsWilde", "credit_ls_new": "Nhà phát triển EnsWilde bản mới", "credit_forcequit_badquery": "Khai thác Bad_query", "credit_johnny_airlift": "Khai thác Airlift", "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "Tinh chỉnh Config, logic MobileGestalt mới", "credit_likepass_sound": "Tắt âm ghi âm cuộc gọi (iOS 27)", "credit_little_34306_concept": "Ý tưởng gốc về tắt âm ghi âm cuộc gọi", "credit_yihooong_silent": "Đã cung cấp âm thanh im lặng và nghiên cứu thay thế.", "credit_kianuni_erosion": "Nhà phát triển Erosion-cn - Logic ghi & hoàn tác tinh chỉnh",
            "tool_mobile_gestalt": "MobileGestalt", "enable_tweak": "Bật tinh chỉnh", "save_changes": "Lưu thay đổi", "alert_ok": "OK", "alert_cancel": "Hủy",
            "mg_save_success_message": "Đã lưu và áp dụng thành công. Hãy Hard Reboot để iOS nhận cấu hình mới.", "mg_revert_success_message": "Đã khôi phục thành công. Vào Cài đặt và chọn 'Respring Device' để áp dụng.", "mg_revert_failed": "Khôi phục thất bại:", "mg_init_failed": "Không thể tải MobileGestalt: %@"
        ],
        "ja": [
            "nav_home": "ホーム", "nav_theme_store": "テーマストア", "nav_settings": "設定", "nav_about": "情報", "nav_apply": "適用",
            "section_tweaks": "微調整", "settings_run_test_header": "テスト実行 (WorseQuery アクセス)", "settings_run_test_btn": "MobileGestalt の読み取り/書き込み権限をテスト", "settings_respring_header": "再スプリング (NeoSpring)", "settings_respring_btn": "デバイスを再スプリング", "settings_tunnel_status": "トンネル接続",
            "theme_store_repos": "リポジトリ", "theme_store_theme_count": "%d テーマ", "theme_store_by_author": "作成者: %@", "theme_store_download_btn": "ダウンロード", "theme_store_json_url": "JSON URL", "theme_store_json_desc": "テーマのJSONを直接貼り付けるか、インデックスを貼り付けます。",
            "translation_by": "%@ (%@) 翻訳", "credit_community": "プロジェクトのサポートに感謝します。", "credit_yang_support": "開発中のサポートに感謝します", "credit_yang_original": "EnsWildeのオリジナル開発者", "credit_ls_new": "新しいEnsWildeの開発者", "credit_forcequit_badquery": "Bad_query エクスプロイト", "credit_johnny_airlift": "Airlift エクスプロイト", "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "Config 微調整、新しい MobileGestalt ロジック", "credit_likepass_sound": "通話録音音を無効にする (iOS 27)", "credit_little_34306_concept": "通話録音音を無効にするオリジナルのコンセプト", "credit_yihooong_silent": "無音トーンのアセットと置換調査に感謝します。", "credit_kianuni_erosion": "Erosion-cn 開発者 - 微調整の書き込みと元に戻すロジック",
            "tool_mobile_gestalt": "MobileGestalt", "enable_tweak": "微調整を有効にする", "save_changes": "変更を保存", "alert_ok": "OK", "alert_cancel": "キャンセル",
            "mg_save_success_message": "保存して適用しました。iOSが新しい構成を認識するように、デバイスをハードリブートしてください。", "mg_revert_success_message": "すべての微調整が正常に元に戻されました。設定に移動して「デバイスを再スプリング」をタップしてください。", "mg_revert_failed": "元に戻すのに失敗しました:", "mg_init_failed": "MobileGestaltの読み込みに失敗しました: %@"
        ],
        "zh-CN": [
            "nav_home": "主页", "nav_theme_store": "主题商店", "nav_settings": "设置", "nav_about": "关于", "nav_apply": "应用",
            "section_tweaks": "微调", "settings_run_test_header": "运行测试 (WorseQuery 访问)", "settings_run_test_btn": "测试 MobileGestalt 读/写权限", "settings_respring_header": "注销 (NeoSpring)", "settings_respring_btn": "注销设备", "settings_tunnel_status": "隧道连接",
            "theme_store_repos": "仓库", "theme_store_theme_count": "%d 个主题", "theme_store_by_author": "作者: %@", "theme_store_download_btn": "下载", "theme_store_json_url": "JSON URL", "theme_store_json_desc": "粘贴直接的 JSON 或索引链接。",
            "translation_by": "%@ (%@) 翻译", "credit_community": "感谢支持我的项目。", "credit_yang_support": "感谢在开发期间支持我", "credit_yang_original": "EnsWilde 的原开发者", "credit_ls_new": "新 EnsWilde 的开发者", "credit_forcequit_badquery": "Bad_query 漏洞", "credit_johnny_airlift": "Airlift 漏洞", "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "配置微调，新的 MobileGestalt 逻辑", "credit_likepass_sound": "禁用通话录音声音 (iOS 27)", "credit_little_34306_concept": "禁用通话录音声音的原始概念", "credit_yihooong_silent": "感谢提供静音音频资源和替换研究。", "credit_kianuni_erosion": "Erosion-cn 开发者 - 写入和还原微调逻辑",
            "tool_mobile_gestalt": "MobileGestalt", "enable_tweak": "启用插件", "save_changes": "保存更改", "alert_ok": "确定", "alert_cancel": "取消",
            "mg_save_success_message": "保存并应用成功。请硬重启设备以便 iOS 读取新配置。", "mg_revert_success_message": "所有微调已成功还原。请转到设置并点击“注销设备”以应用更改。", "mg_revert_failed": "还原失败:", "mg_init_failed": "加载 MobileGestalt 失败: %@"
        ],
        "zh-TW": [
            "nav_home": "主頁", "nav_theme_store": "主題商店", "nav_settings": "設定", "nav_about": "關於", "nav_apply": "套用",
            "section_tweaks": "微調", "settings_run_test_header": "執行測試 (WorseQuery 存取)", "settings_run_test_btn": "測試 MobileGestalt 讀取/寫入權限", "settings_respring_header": "重新載入 (NeoSpring)", "settings_respring_btn": "重新載入裝置", "settings_tunnel_status": "通道連線",
            "theme_store_repos": "儲存庫", "theme_store_theme_count": "%d 個主題", "theme_store_by_author": "作者: %@", "theme_store_download_btn": "下載", "theme_store_json_url": "JSON URL", "theme_store_json_desc": "貼上直接的 JSON 或索引連結。",
            "translation_by": "%@ (%@) 翻譯", "credit_community": "感謝支持我的專案。", "credit_yang_support": "感謝在開發期間支持我", "credit_yang_original": "EnsWilde 的原始開發者", "credit_ls_new": "新 EnsWilde 的開發者", "credit_forcequit_badquery": "Bad_query 漏洞", "credit_johnny_airlift": "Airlift 漏洞", "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "設定微調，新的 MobileGestalt 邏輯", "credit_likepass_sound": "停用通話錄音聲音 (iOS 27)", "credit_little_34306_concept": "停用通話錄音聲音的原始概念", "credit_yihooong_silent": "感謝提供靜音音訊資源與替換研究。", "credit_kianuni_erosion": "Erosion-cn 開發者 - 寫入與還原微調邏輯",
            "tool_mobile_gestalt": "MobileGestalt", "enable_tweak": "啟用外掛", "save_changes": "儲存變更", "alert_ok": "確定", "alert_cancel": "取消",
            "mg_save_success_message": "儲存並套用成功。請強制重啟裝置以便 iOS 讀取新設定。", "mg_revert_success_message": "所有微調已成功還原。請前往設定並點擊「重新載入裝置」以套用變更。", "mg_revert_failed": "還原失敗:", "mg_init_failed": "載入 MobileGestalt 失敗: %@"
        ],
        "fr": [
            "nav_home": "Accueil", "nav_theme_store": "Boutique de thèmes", "nav_settings": "Réglages", "nav_about": "À propos", "nav_apply": "Appliquer",
            "section_tweaks": "Ajustements", "settings_run_test_header": "TEST D'EXÉCUTION (Accès WorseQuery)", "settings_run_test_btn": "Tester les autorisations de lecture/écriture de MobileGestalt", "settings_respring_header": "REDÉMARRAGE (NeoSpring)", "settings_respring_btn": "Redémarrer SpringBoard", "settings_tunnel_status": "Connexion Tunnel",
            "theme_store_repos": "Dépôts", "theme_store_theme_count": "%d thèmes", "theme_store_by_author": "par %@", "theme_store_download_btn": "Télécharger", "theme_store_json_url": "URL JSON", "theme_store_json_desc": "Collez un JSON de thèmes direct ou un index.",
            "translation_by": "Traduction %@ (%@)", "credit_community": "Pour le soutien de mon projet.", "credit_yang_support": "Pour m'avoir soutenu pendant le développement", "credit_yang_original": "Développeur original d'EnsWilde", "credit_ls_new": "Développeur du nouvel EnsWilde", "credit_forcequit_badquery": "Exploit Bad_query", "credit_johnny_airlift": "Exploit Airlift", "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "Ajustement de config, nouvelle logique MobileGestalt", "credit_likepass_sound": "Désactiver le son d'enregistrement d'appel (iOS 27)", "credit_little_34306_concept": "Concept original de désactivation du son d'enregistrement d'appel", "credit_yihooong_silent": "Pour les ressources de tonalité silencieuse et la recherche de remplacement.", "credit_kianuni_erosion": "Développeur Erosion-cn - Logique d'écriture et de rétablissement des ajustements",
            "tool_mobile_gestalt": "MobileGestalt", "enable_tweak": "Activer l'ajustement", "save_changes": "Enregistrer les modifications", "alert_ok": "OK", "alert_cancel": "Annuler",
            "mg_save_success_message": "Enregistré et appliqué avec succès. Redémarrez l'appareil pour qu'iOS prenne en compte la nouvelle configuration.", "mg_revert_success_message": "Tous les ajustements ont été rétablis avec succès. Allez dans RÉGLAGES et appuyez sur 'Redémarrer SpringBoard'.", "mg_revert_failed": "Échec du rétablissement :", "mg_init_failed": "Échec du chargement de MobileGestalt : %@"
        ],
        "ar": [
            "nav_home": "الرئيسية", "nav_theme_store": "متجر الثيمات", "nav_settings": "الإعدادات", "nav_about": "حول", "nav_apply": "تطبيق",
            "section_tweaks": "تعديلات", "settings_run_test_header": "تشغيل الاختبار (WorseQuery)", "settings_run_test_btn": "اختبار أذونات القراءة/الكتابة لـ MobileGestalt", "settings_respring_header": "إعادة تشغيل (NeoSpring)", "settings_respring_btn": "إعادة تشغيل الجهاز (Respring)", "settings_tunnel_status": "اتصال النفق (Tunnel)",
            "theme_store_repos": "المستودعات", "theme_store_theme_count": "%d ثيمات", "theme_store_by_author": "بواسطة %@", "theme_store_download_btn": "تحميل", "theme_store_json_url": "رابط JSON", "theme_store_json_desc": "الصق JSON مباشر أو رابط فهرس.",
            "translation_by": "ترجمة %@ (%@)", "credit_community": "لدعم مشروعي.", "credit_yang_support": "لدعمي أثناء التطوير", "credit_yang_original": "المطور الأصلي لـ EnsWilde", "credit_ls_new": "مطور EnsWilde الجديد", "credit_forcequit_badquery": "استغلال Bad_query", "credit_johnny_airlift": "استغلال Airlift", "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "تعديل التكوين، منطق MobileGestalt الجديد", "credit_likepass_sound": "تعطيل صوت تسجيل المكالمات (iOS 27)", "credit_little_34306_concept": "الفكرة الأصلية لتعطيل صوت تسجيل المكالمات", "credit_yihooong_silent": "لأصول النغمة الصامتة وأبحاث الاستبدال.", "credit_kianuni_erosion": "مطور Erosion-cn - كتابة ومنطق إرجاع التعديلات",
            "tool_mobile_gestalt": "MobileGestalt", "enable_tweak": "تمكين التعديل", "save_changes": "حفظ التغييرات", "alert_ok": "موافق", "alert_cancel": "إلغاء",
            "mg_save_success_message": "تم الحفظ والتطبيق بنجاح. أعد تشغيل الجهاز بقوة ليتعرف iOS على التكوين الجديد.", "mg_revert_success_message": "تم إرجاع جميع التعديلات بنجاح. انتقل إلى الإعدادات واضغط على 'إعادة تشغيل الجهاز'.", "mg_revert_failed": "فشل الإرجاع:", "mg_init_failed": "فشل تحميل MobileGestalt: %@"
        ],
        "es": [
            "nav_home": "Inicio", "nav_theme_store": "Tienda de temas", "nav_settings": "Ajustes", "nav_about": "Acerca de", "nav_apply": "Aplicar",
            "section_tweaks": "Ajustes", "settings_run_test_header": "EJECUTAR PRUEBA (Acceso WorseQuery)", "settings_run_test_btn": "Probar permisos de lectura/escritura de MobileGestalt", "settings_respring_header": "RESPRING (NeoSpring)", "settings_respring_btn": "Reiniciar SpringBoard", "settings_tunnel_status": "Conexión de túnel",
            "theme_store_repos": "Repositorios", "theme_store_theme_count": "%d temas", "theme_store_by_author": "por %@", "theme_store_download_btn": "Descargar", "theme_store_json_url": "URL del JSON", "theme_store_json_desc": "Pega un JSON de temas directo o un índice.",
            "translation_by": "Traducción de %@ (%@)", "credit_community": "Por apoyar mi proyecto.", "credit_yang_support": "Por apoyarme durante el desarrollo", "credit_yang_original": "Desarrollador original de EnsWilde", "credit_ls_new": "Desarrollador del nuevo EnsWilde", "credit_forcequit_badquery": "Exploit Bad_query", "credit_johnny_airlift": "Exploit Airlift", "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "Ajuste de configuración, nueva lógica de MobileGestalt", "credit_likepass_sound": "Desactivar sonido de grabación de llamadas (iOS 27)", "credit_little_34306_concept": "Concepto original para desactivar el sonido de grabación de llamadas", "credit_yihooong_silent": "Por los recursos de tono silencioso y la investigación de reemplazo.", "credit_kianuni_erosion": "Desarrollador de Erosion-cn - Lógica de escritura y reversión de ajustes",
            "tool_mobile_gestalt": "MobileGestalt", "enable_tweak": "Activar ajuste", "save_changes": "Guardar cambios", "alert_ok": "OK", "alert_cancel": "Cancelar",
            "mg_save_success_message": "Guardado y aplicado con éxito. Reinicia el dispositivo para que iOS detecte la nueva configuración.", "mg_revert_success_message": "Todos los ajustes se revirtieron con éxito. Ve a AJUSTES y toca 'Reiniciar SpringBoard'.", "mg_revert_failed": "Error al revertir:", "mg_init_failed": "Error al cargar MobileGestalt: %@"
        ],
        "ru": [
            "nav_home": "Главная", "nav_theme_store": "Магазин тем", "nav_settings": "Настройки", "nav_about": "О программе", "nav_apply": "Применить",
            "section_tweaks": "Твики", "settings_run_test_header": "ЗАПУСТИТЬ ТЕСТ (Доступ WorseQuery)", "settings_run_test_btn": "Проверить права чтения/записи MobileGestalt", "settings_respring_header": "RESPRING (NeoSpring)", "settings_respring_btn": "Перезапустить SpringBoard", "settings_tunnel_status": "Туннельное соединение",
            "theme_store_repos": "Репозитории", "theme_store_theme_count": "%d тем", "theme_store_by_author": "от %@", "theme_store_download_btn": "Скачать", "theme_store_json_url": "URL-адрес JSON", "theme_store_json_desc": "Вставьте прямой JSON тем или индекс.",
            "translation_by": "Перевод %@ (%@)", "credit_community": "За поддержку моего проекта.", "credit_yang_support": "За поддержку во время разработки", "credit_yang_original": "Оригинальный разработчик EnsWilde", "credit_ls_new": "Разработчик нового EnsWilde", "credit_forcequit_badquery": "Эксплойт Bad_query", "credit_johnny_airlift": "Эксплойт Airlift", "credit_mak5er_aod": "Airlift-On-Device", "credit_jailbreak_config": "Настройка конфигурации, новая логика MobileGestalt", "credit_likepass_sound": "Отключить звук записи звонков (iOS 27)", "credit_little_34306_concept": "Оригинальная концепция отключения звука записи звонков", "credit_yihooong_silent": "За ресурсы беззвучного тона и исследования замены.", "credit_kianuni_erosion": "Разработчик Erosion-cn - Логика применения и отмены твиков",
            "tool_mobile_gestalt": "MobileGestalt", "enable_tweak": "Включить твик", "save_changes": "Сохранить изменения", "alert_ok": "ОК", "alert_cancel": "Отмена",
            "mg_save_success_message": "Успешно сохранено и применено. Выполните жесткую перезагрузку устройства, чтобы iOS обнаружила новую конфигурацию.", "mg_revert_success_message": "Все твики успешно отменены. Перейдите в НАСТРОЙКИ и нажмите 'Перезапустить SpringBoard'.", "mg_revert_failed": "Ошибка отмены:", "mg_init_failed": "Не удалось загрузить MobileGestalt: %@"
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
        
        // 3. Trả về key gốc nếu chịu chết
        return key
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