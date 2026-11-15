//
//  ManualCacheExtraEditor.swift
//  EnsWilde
//
//  Standalone CacheExtra key editor with its own enable toggle, Save, and Revert.
//  Value-kind parsing ported from GestaltX.
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
            guard let v = UInt64(trimmed) else { throw MGEditError("Enter a valid whole number.") }
            return NSNumber(value: v)
        case .real:
            guard let v = Double(trimmed), v.isFinite else { throw MGEditError("Enter a finite decimal number.") }
            return NSNumber(value: v)
        case .boolean:
            switch trimmed.lowercased() {
            case "true", "1": return NSNumber(value: true)
            case "false", "0": return NSNumber(value: false)
            default: throw MGEditError("Use true or false for a Boolean value.")
            }
        case .date:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let v = formatter.date(from: trimmed) { return v }
            formatter.formatOptions = [.withInternetDateTime]
            guard let v = formatter.date(from: trimmed) else {
                throw MGEditError("Enter an ISO 8601 date, such as 2026-11-09T12:00:00Z.")
            }
            return v
        case .data:
            guard let v = Data(base64Encoded: trimmed.filter { !$0.isWhitespace }) else {
                throw MGEditError("Enter valid Base64 data.")
            }
            return v
        case .array, .dictionary:
            let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\">\(text)</plist>"
            guard let v = try? PropertyListSerialization.propertyList(from: Data(xml.utf8), options: [], format: nil),
                  (self == .array && v is [Any]) || (self == .dictionary && v is [String: Any]) else {
                throw MGEditError("Enter a valid XML plist array or dictionary fragment.")
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
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return [:]
        }
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

    @State private var isSaving = false
    @State private var isReverting = false
    @State private var showRevertConfirm = false

    private var filtered: [MGCacheExtraEntry] {
        searchText.isEmpty
            ? entries
            : entries.filter { $0.key.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Form {
            Section(header: Text("CacheExtra Editor")) {
                Toggle("Enable tweak", isOn: $manualCacheEditorEnabled)
                    .onChange(of: manualCacheEditorEnabled) { isEnabled in
                        if !isEnabled { showApplyTab = false }
                    }
            }

            Section(header: Text("Fields")) {
                if entries.isEmpty {
                    Text("CacheExtra is empty.").foregroundColor(.secondary)
                } else {
                    ForEach(filtered) { entry in
                        Button {
                            editing = entry
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.key)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                Text("\(entry.kind.rawValue) · \(entry.text.prefix(120))")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .tint(.primary)
                        .swipeActions {
                            Button(role: .destructive) {
                                removeEntry(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section(header: Text("Save & Revert")) {
                Button {
                    saveChanges()
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(isSaving ? "Saving…" : "Save Settings")
                    }
                }
                .disabled(isSaving || isReverting)

                Button(role: .destructive) {
                    showRevertConfirm = true
                } label: {
                    HStack {
                        if isReverting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        Text(isReverting ? "Reverting…" : "Revert Tweaks")
                    }
                }
                .disabled(isSaving || isReverting)
            }
        }
        .searchable(text: $searchText, prompt: "Search keys…")
        .navigationTitle("CacheExtra Editor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) {
            ManualCacheExtraFieldEditor(field: nil) { newEntry in addOrUpdate(newEntry) }
        }
        .sheet(item: $editing) { entry in
            ManualCacheExtraFieldEditor(field: entry) { updated in addOrUpdate(updated) }
        }
        .alert("Invalid value", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Revert all MobileGestalt tweaks?", isPresented: $showRevertConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Revert", role: .destructive) { revertChanges() }
        } message: {
            Text("This deletes the live MobileGestalt cache file. iOS will regenerate a clean copy on the next reboot. All tweaks — including ones from the MobileGestalt page — will be reset.")
        }
        .onAppear {
            loadIfNeeded()
            reload()
        }
    }

    // MARK: - Load / Reload

    private func loadIfNeeded() {
        if store.mgCurrentDict.count > 0 { return }
        let liveURL = URL(filePath: MobileGestaltApplyTask.onDeviceMGPath)
        _ = wq.grantAccess(path: liveURL.deletingLastPathComponent().path)
        if let data = try? Data(contentsOf: liveURL),
           let dict = try? PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary {
            store.mgCurrentDict = dict
        }
        if store.mgCurrentDict["CacheExtra"] as? NSMutableDictionary == nil {
            store.mgCurrentDict["CacheExtra"] = NSMutableDictionary()
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

    // MARK: - Edit

    private func addOrUpdate(_ entry: MGCacheExtraEntry) {
        do {
            let parsed = try entry.kind.parse(entry.text)
            store.cacheExtra[entry.key] = parsed
            ManualEditTracker.setValue(parsed, forKey: entry.key)
            store.objectWillChange.send()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeEntry(_ entry: MGCacheExtraEntry) {
        store.cacheExtra.removeObject(forKey: entry.key)
        ManualEditTracker.removeKey(entry.key)
        store.objectWillChange.send()
        reload()
    }

    // MARK: - Save

    private func saveChanges() {
        isSaving = true
        Task {
            do {
                try await MobileGestaltApplyTask.applyGestalt(store: store) { log in
                    print(log)
                }

                let liveURL = URL(filePath: MobileGestaltApplyTask.onDeviceMGPath)
                let modURL = URL.documentsDirectory
                    .appendingPathComponent("ModifiedMobileGestalt.plist", conformingTo: .data)
                if let data = try? Data(contentsOf: liveURL) {
                    try? data.write(to: modURL)
                }

                await MainActor.run {
                    store.loadFromPlist(url: modURL)
                    reload()
                    isSaving = false
                    showApplyTab = true
                    NotificationCenter.default.post(name: .switchToApplyTab, object: nil)
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Save failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Revert

    private func revertChanges() {
        isReverting = true
        Task {
            do {
                try await MobileGestaltApplyTask.restoreGestalt { log in
                    print(log)
                }
                ManualEditTracker.clear()
                let modURL = URL.documentsDirectory
                    .appendingPathComponent("ModifiedMobileGestalt.plist", conformingTo: .data)
                try? FileManager.default.removeItem(at: modURL)

                await MainActor.run {
                    store.mgCurrentDict = NSMutableDictionary()
                    reload()
                    isReverting = false
                    showApplyTab = true
                    NotificationCenter.default.post(name: .switchToApplyTab, object: nil)
                }
            } catch {
                await MainActor.run {
                    isReverting = false
                    errorMessage = "Revert failed: \(error.localizedDescription)"
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
                Section("Key") {
                    TextField("Obfuscated key (22 chars)", text: $key)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                        .disabled(field != nil)
                }
                Section("Type") {
                    Picker("Type", selection: $kind) {
                        ForEach(MGValueKind.allCases) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Value") {
                    valueEditor
                    if let e = localError {
                        Text(e).font(.caption).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(field == nil ? "Add Field" : "Edit Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let f = field {
                    key = f.key
                    kind = f.kind
                    text = f.text
                }
            }
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch kind {
        case .boolean:
            Picker("Value", selection: $text) {
                Text("true").tag("true")
                Text("false").tag("false")
            }
            .pickerStyle(.segmented)
        case .integer:
            TextField("e.g. 1", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .font(.system(.body, design: .monospaced))
        case .real:
            TextField("e.g. 1.5", text: $text)
                .keyboardType(.decimalPad)
                .font(.system(.body, design: .monospaced))
        case .string:
            TextField("String value", text: $text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        case .data:
            VStack(alignment: .leading, spacing: 4) {
                Text("Base64").font(.caption).foregroundColor(.secondary)
                TextEditor(text: $text)
                    .frame(minHeight: 100)
                    .font(.system(.caption, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        case .date:
            TextField("ISO 8601 (e.g. 2026-11-09T12:00:00Z)", text: $text)
                .font(.system(.body, design: .monospaced))
        case .array, .dictionary:
            VStack(alignment: .leading, spacing: 4) {
                Text("Plist XML fragment").font(.caption).foregroundColor(.secondary)
                TextEditor(text: $text)
                    .frame(minHeight: 150)
                    .font(.system(.caption, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
    }

    private func save() {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        do {
            _ = try kind.parse(text)
        } catch {
            localError = error.localizedDescription
            return
        }
        onSave(MGCacheExtraEntry(key: trimmedKey, kind: kind, text: text))
        dismiss()
    }
}