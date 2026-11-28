//
//  ManualCacheExtraEditor.swift
//  EnsWilde
//

import SwiftUI
import CoreFoundation

// MARK: - Value kinds
enum MGValueKind: String, CaseIterable, Identifiable {
    case string = "String"
    case integer = "Integer"
    case real = "Real"
    case boolean = "Boolean"
    case data = "Data"
    case array = "Array"
    case dictionary = "Dictionary"
    case date = "Date"

    var id: String { rawValue }

    static func detect(_ value: Any) -> Self {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .boolean }
            return CFNumberIsFloatType(unsafeBitCast(number, to: CFNumber.self)) ? .real : .integer
        }
        if value is Date { return .date }
        if value is Data { return .data }
        if value is [String: Any] { return .dictionary }
        if value is [Any] { return .array }
        return .string
    }

    func parse(_ text: String) throws -> Any {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .string:
            return text
        case .integer:
            if let v = Int64(trimmed) { return NSNumber(value: v) }
            guard let v = UInt64(trimmed) else { throw MGEditError(L("manual_editor_err_invalid_int")) }
            return NSNumber(value: v)
        case .real:
            guard let v = Double(trimmed), v.isFinite else { throw MGEditError(L("manual_editor_err_invalid_real")) }
            return NSNumber(value: v)
        case .boolean:
            switch trimmed.lowercased() {
            case "true", "1": return NSNumber(value: true)
            case "false", "0": return NSNumber(value: false)
            default: throw MGEditError(L("manual_editor_err_invalid_bool"))
            }
        case .date:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let v = formatter.date(from: trimmed) { return v }
            formatter.formatOptions = [.withInternetDateTime]
            guard let v = formatter.date(from: trimmed) else {
                throw MGEditError(L("manual_editor_err_invalid_date"))
            }
            return v
        case .data:
            guard let v = Data(base64Encoded: trimmed.filter { !$0.isWhitespace }) else {
                throw MGEditError(L("manual_editor_err_invalid_data"))
            }
            return v
        case .array, .dictionary:
            let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\">\(text)</plist>"
            guard let v = try? PropertyListSerialization.propertyList(from: Data(xml.utf8), options: [], format: nil),
                  (self == .array && v is [Any]) || (self == .dictionary && v is [String: Any]) else {
                throw MGEditError(L("manual_editor_err_invalid_xml"))
            }
            return v
        }
    }

    func text(for value: Any) -> String {
        switch self {
        case .boolean:
            return (value as? NSNumber)?.boolValue == true ? "true" : "false"
        case .date:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return (value as? Date).map { formatter.string(from: $0) } ?? ""
        case .data:
            return (value as? Data)?.base64EncodedString() ?? ""
        case .array, .dictionary:
            guard let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0),
                  let xml = String(data: data, encoding: .utf8),
                  let start = xml.range(of: "<plist version=\"1.0\">"),
                  let end = xml.range(of: "</plist>", options: .backwards) else { return "" }
            return String(xml[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return String(describing: value)
        }
    }
}

struct MGEditError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct MGCacheExtraEntry: Identifiable, Equatable {
    var id: String { key }
    let key: String
    var kind: MGValueKind
    var text: String
}

// MARK: - Edit Tracker
enum ManualEditTracker {
    private static let setKey = "EnsWilde.manualCacheExtraSet.v1"
    private static let removedKey = "EnsWilde.manualCacheExtraRemoved.v1"

    static func setValue(_ value: Any, forKey key: String) {
        var dict = loadSet()
        dict[key] = value
        saveSet(dict)
        var removed = loadRemoved()
        removed.remove(key)
        saveRemoved(removed)
    }

    static func removeKey(_ key: String) {
        var dict = loadSet()
        dict.removeValue(forKey: key)
        saveSet(dict)
        var removed = loadRemoved()
        removed.insert(key)
        saveRemoved(removed)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: setKey)
        UserDefaults.standard.removeObject(forKey: removedKey)
    }

    static func loadSet() -> [String: Any] {
        guard let data = UserDefaults.standard.data(forKey: setKey),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return [:] }
        return dict
    }

    static func loadRemoved() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: removedKey) ?? [])
    }

    static func saveSet(_ dict: [String: Any]) {
        guard PropertyListSerialization.propertyList(dict, isValidFor: .binary),
              let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) else { return }
        UserDefaults.standard.set(data, forKey: setKey)
    }

    static func saveRemoved(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: removedKey)
    }
}

// MARK: - Main View
struct ManualCacheExtraEditorView: View {
    @ObservedObject var store: GestaltStore
    @AppStorage("manualCacheEditorEnabled") private var manualCacheEditorEnabled: Bool = false
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false

    @State private var entries: [MGCacheExtraEntry] = []
    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var editing: MGCacheExtraEntry?
    @State private var errorMessage: String?
    @State private var successMessage: String?

    @State private var isSaving = false
    @State private var isReverting = false
    @State private var showRevertConfirm = false

    private var filtered: [MGCacheExtraEntry] {
        searchText.isEmpty ? entries : entries.filter { $0.key.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Form {
            Section(header: Text(L("manual_editor_title"))) {
                Toggle(L("enable_tweak"), isOn: $manualCacheEditorEnabled)
                    .onChange(of: manualCacheEditorEnabled) { isEnabled in
                        if !isEnabled { showApplyTab = false }
                    }

                UniversalLogView()
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section(header: Text(L("manual_editor_fields"))) {
                if entries.isEmpty {
                    Text(L("manual_editor_empty")).foregroundColor(.secondary)
                } else {
                    ForEach(filtered) { entry in
                        Button { editing = entry } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.key).font(.system(.caption, design: .monospaced)).lineLimit(1)
                                Text("\(entry.kind.rawValue) · \(entry.text.prefix(120))")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                        .tint(.primary)
                        .swipeActions {
                            Button(role: .destructive) { removeEntry(entry) } label: { Label(L("manual_editor_delete"), systemImage: "trash") }
                        }
                    }
                }
            }

            Section(header: Text(L("manual_editor_save_revert"))) {
                Button { saveChanges() } label: {
                    HStack {
                        if isSaving { ProgressView().controlSize(.small) } else { Image(systemName: "square.and.arrow.down") }
                        Text(isSaving ? L("manual_editor_saving") : L("manual_editor_save"))
                    }
                }.disabled(isSaving || isReverting)

                Button(role: .destructive) { showRevertConfirm = true } label: {
                    HStack {
                        if isReverting { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.counterclockwise") }
                        Text(isReverting ? L("manual_editor_reverting") : L("manual_editor_revert"))
                    }
                }.disabled(isSaving || isReverting)
            }
        }
        .searchable(text: $searchText, prompt: L("manual_editor_search"))
        .navigationTitle(L("manual_editor_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { showingAdd = true } label: { Image(systemName: "plus") } }
        }
        .sheet(isPresented: $showingAdd) { ManualCacheExtraFieldEditor(field: nil) { newEntry in addOrUpdate(newEntry) } }
        .sheet(item: $editing) { entry in ManualCacheExtraFieldEditor(field: entry) { updated in addOrUpdate(updated) } }
        .alert(L("manual_editor_invalid_value"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(L("alert_ok"), role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .alert(L("alert_message_title"), isPresented: Binding(get: { successMessage != nil }, set: { if !$0 { successMessage = nil } })) {
            Button(L("alert_ok"), role: .cancel) { successMessage = nil }
        } message: { Text(successMessage ?? "") }
        .alert(L("manual_editor_revert_confirm_title"), isPresented: $showRevertConfirm) {
            Button(L("alert_cancel"), role: .cancel) { }
            Button(L("manual_editor_revert"), role: .destructive) { revertChanges() }
        } message: {
            Text(L("manual_editor_revert_confirm_message"))
        }
        .onAppear { loadIfNeeded(); reload() }
    }

    private func loadIfNeeded() {
        if store.mgCurrentDict.count > 0 { return }
        let liveURL = URL(filePath: MobileGestaltApplyTask.onDeviceMGPath)
        _ = wq.grantAccess(path: liveURL.deletingLastPathComponent().path)
        if let data = try? Data(contentsOf: liveURL),
           let dict = try? PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary {
            store.mgCurrentDict = dict
        }
    }

    private func reload() {
        var result: [MGCacheExtraEntry] = []
        let dict = store.cacheExtra
        dict.forEach { k, v in
            guard let k = k as? String else { return }
            let kind = MGValueKind.detect(v)
            result.append(MGCacheExtraEntry(key: k, kind: kind, text: kind.text(for: v)))
        }
        entries = result.sorted { $0.key < $1.key }
    }

    private func addOrUpdate(_ entry: MGCacheExtraEntry) {
        do {
            let parsed = try entry.kind.parse(entry.text)
            if let ce = store.mgCurrentDict["CacheExtra"] as? NSMutableDictionary {
                ce[entry.key] = parsed
            }
            ManualEditTracker.setValue(parsed, forKey: entry.key)

            let newDict = NSMutableDictionary(dictionary: store.mgCurrentDict)
            store.mgCurrentDict = newDict

            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeEntry(_ entry: MGCacheExtraEntry) {
        if let ce = store.mgCurrentDict["CacheExtra"] as? NSMutableDictionary {
            ce.removeObject(forKey: entry.key)
        }
        ManualEditTracker.removeKey(entry.key)

        let newDict = NSMutableDictionary(dictionary: store.mgCurrentDict)
        store.mgCurrentDict = newDict

        reload()
    }

    private func saveChanges() {
        guard !isSaving && !isReverting else { return }
        isSaving = true
        GLOBAL_LOG.step("Đang chuẩn bị lưu Cache Extra...")

        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            do {
                try await MobileGestaltApplyTask.applyGestalt(store: store) { log in print(log) }
                let liveURL = URL(filePath: MobileGestaltApplyTask.onDeviceMGPath)
                let modURL = URL.documentsDirectory.appendingPathComponent("ModifiedMobileGestalt.plist", conformingTo: .data)
                if let data = try? Data(contentsOf: liveURL) { try? data.write(to: modURL) }

                await MainActor.run {
                    store.loadFromPlist(url: modURL)
                    reload()
                    isSaving = false
                    showApplyTab = true
                    GLOBAL_LOG.success("Đã lưu Cache Extra thành công!")
                    successMessage = L("mg_save_success_message")
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    GLOBAL_LOG.error("Lỗi: \(error.localizedDescription)")
                    errorMessage = L("mg_save_failed") + " \(error.localizedDescription)"
                }
            }
        }
    }

    private func revertChanges() {
        guard !isSaving && !isReverting else { return }
        isReverting = true
        GLOBAL_LOG.step("Đang khôi phục Cache Extra...")

        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            do {
                try await MobileGestaltApplyTask.restoreGestalt { log in print(log) }
                ManualEditTracker.clear()
                let modURL = URL.documentsDirectory.appendingPathComponent("ModifiedMobileGestalt.plist", conformingTo: .data)
                try? FileManager.default.removeItem(at: modURL)

                await MainActor.run {
                    store.mgCurrentDict = NSMutableDictionary()
                    reload()
                    isReverting = false
                    showApplyTab = true
                    GLOBAL_LOG.success("Đã khôi phục Cache Extra thành công!")
                    successMessage = L("mg_revert_success_message")
                }
            } catch {
                await MainActor.run {
                    isReverting = false
                    GLOBAL_LOG.error("Lỗi: \(error.localizedDescription)")
                    errorMessage = L("mg_revert_failed") + " \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Field Editor
struct ManualCacheExtraFieldEditor: View {
    @Environment(\.dismiss) var dismiss
    let field: MGCacheExtraEntry?
    let onSave: (MGCacheExtraEntry) -> Void

    @State private var key = ""
    @State private var kind: MGValueKind = .string
    @State private var text = ""
    @State private var localError: String?

    var body: some View {
        NavigationView {
            Form {
                Section(L("manual_editor_key")) {
                    TextField(L("manual_editor_key_placeholder"), text: $key).font(.system(.body, design: .monospaced)).disabled(field != nil)
                }
                Section(L("manual_editor_type")) {
                    Picker(L("manual_editor_type"), selection: $kind) {
                        ForEach(MGValueKind.allCases) { k in Text(k.rawValue).tag(k) }
                    }.pickerStyle(.menu)
                }
                Section(L("manual_editor_value")) {
                    valueEditor
                    if let e = localError { Text(e).font(.caption).foregroundColor(.red) }
                }
            }
            .navigationTitle(field == nil ? L("manual_editor_add_field") : L("manual_editor_edit_field"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("alert_cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("alert_save")) { save() }.disabled(key.isEmpty) }
            }
            .onAppear {
                if let f = field { key = f.key; kind = f.kind; text = f.text }
            }
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch kind {
        case .boolean:
            Picker(L("manual_editor_value"), selection: $text) { Text("true").tag("true"); Text("false").tag("false") }.pickerStyle(.segmented)
        case .integer:
            TextField(L("manual_editor_placeholder_int"), text: $text).keyboardType(.numbersAndPunctuation).font(.system(.body, design: .monospaced))
        case .real:
            TextField(L("manual_editor_placeholder_real"), text: $text).keyboardType(.decimalPad).font(.system(.body, design: .monospaced))
        case .string:
            TextField(L("manual_editor_placeholder_string"), text: $text)
        case .data:
            VStack(alignment: .leading) { Text(L("manual_editor_placeholder_base64")).font(.caption).foregroundColor(.secondary); TextEditor(text: $text).frame(minHeight: 100).font(.system(.caption, design: .monospaced)) }
        case .date:
            TextField(L("manual_editor_placeholder_date"), text: $text).font(.system(.body, design: .monospaced))
        case .array, .dictionary:
            VStack(alignment: .leading) { Text(L("manual_editor_placeholder_xml")).font(.caption).foregroundColor(.secondary); TextEditor(text: $text).frame(minHeight: 150).font(.system(.caption, design: .monospaced)) }
        }
    }

    private func save() {
        do { _ = try kind.parse(text) }
        catch { localError = error.localizedDescription; return }
        onSave(MGCacheExtraEntry(key: key, kind: kind, text: text))
        dismiss()
    }
}
