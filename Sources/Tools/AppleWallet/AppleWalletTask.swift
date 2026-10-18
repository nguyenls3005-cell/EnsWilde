import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ZIPFoundation

// MARK: - Document Picker Helper
struct DocumentPickerView: UIViewControllerRepresentable {
    var allowedContentTypes: [UTType] = [.data, .item]
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        init(_ parent: DocumentPickerView) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let shouldStop = url.startAccessingSecurityScopedResource()
            defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
            parent.onPick(url)
            parent.dismiss()
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { parent.dismiss() }
    }
}

// MARK: - Apple Wallet View
struct AppleWalletView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject var walletStore: AppleWalletStore
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @State private var showAddSheet = false
    @State private var showScanSheet = false
    @State private var showImportZIPSheet = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isScanning = false
    @State private var showSavedAlert = false

    var body: some View {
        Form {
            Section(header: Text(L("tool_apple_wallet"))) {
                Toggle(L("wallet_enable"), isOn: $walletStore.appleWalletEnabled)
            }

            Section(header: Text(L("section_wallet_cards"))) {
                if walletStore.cards.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(L("wallet_no_cards"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(Array(walletStore.cards.enumerated()), id: \.element.id) { index, card in
                        NavigationLink(destination: AppleWalletCardDetailView(card: card, walletStore: walletStore)) {
                            WalletCardPreview(card: card, index: index, total: walletStore.cards.count, walletStore: walletStore)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section(header: Text(L("section_add_card"))) {
                Button(L("wallet_scan_card")) {
                    showScanSheet = true
                }

                Button(L("wallet_manual_input")) {
                    showAddSheet = true
                }

                Button(L("wallet_import_default_zip")) {
                    showImportZIPSheet = true
                }
            }

            Section {
                Button {
                    showApplyTab = true
                    showSavedAlert = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save Changes")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .disabled(!walletStore.appleWalletEnabled)
            }
        }
        .headerProminence(.increased)
        .navigationTitle(L("wallet_title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            ManualAddCardSheet(walletStore: walletStore)
        }
        .sheet(isPresented: $showScanSheet) {
            ScanCardIDSheet(walletStore: walletStore, isPresented: $showScanSheet)
        }
        .sheet(isPresented: $showImportZIPSheet) {
            ImportDefaultCardSheet(walletStore: walletStore)
        }
        .alert(L("alert_error"), isPresented: $showErrorAlert) {
            Button(L("alert_ok")) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK") {}
        } message: {
            Text("Tab Apply đã được mở. Chuyển sang tab Apply để áp dụng.")
        }
    }
}

// MARK: - Wallet Card Preview
struct WalletCardPreview: View {
    let card: AppleWalletCard
    let index: Int
    let total: Int
    @ObservedObject var walletStore: AppleWalletStore
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false

    var body: some View {
        ZStack {
            if let imageData = card.backgroundImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(1.586, contentMode: .fill)
                    .frame(height: 200)
                    .cornerRadius(16)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x667eea), Color(hex: 0x764ba2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 200)
            }

            VStack {
                HStack {
                    Spacer()
                    if card.enabled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.name)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(card.id.prefix(16) + "...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                }
            }
            .padding(16)
        }
        .frame(height: 200)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .offset(y: CGFloat(index) * -8)
        .contextMenu {
            Button {
                showEditSheet = true
            } label: {
                Label(L("alert_edit"), systemImage: "pencil")
            }

            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label(L("alert_delete"), systemImage: "trash")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditCardSheet(card: card, walletStore: walletStore)
        }
        .alert(L("alert_delete_card"), isPresented: $showDeleteAlert) {
            Button(L("alert_cancel"), role: .cancel) {}
            Button(L("alert_delete"), role: .destructive) {
                walletStore.deleteCard(card)
            }
        } message: {
            Text(L("alert_delete_card_confirm").replacingOccurrences(of: "{cardName}", with: "\(card.name)?"))
        }
    }
}

// MARK: - Manual Add Card Sheet
struct ManualAddCardSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var walletStore: AppleWalletStore
    @State private var cardID = ""
    @State private var cardName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("section_card_information"))) {
                    TextField(L("wallet_card_id"), text: $cardID)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    TextField(L("wallet_card_name"), text: $cardName)
                }
            }
            .navigationTitle(L("wallet_add_manually"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("alert_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("alert_add")) {
                        let card = AppleWalletCard(id: cardID.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   name: cardName.isEmpty ? "Card \(cardID.prefix(8))" : cardName)
                        walletStore.addCard(card)
                        dismiss()
                    }
                    .disabled(cardID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Scan Card ID Sheet
struct ScanCardIDSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var walletStore: AppleWalletStore
    @Binding var isPresented: Bool
    @State private var isScanning = false
    @State private var scanStatus = L("wallet_scan_ready")
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("wallet_scan_card"))) {
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                                .frame(width: 150, height: 150)

                            if isScanning {
                                Circle()
                                    .trim(from: 0, to: 0.7)
                                    .stroke(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                    )
                                    .frame(width: 150, height: 150)
                                    .rotationEffect(.degrees(isScanning ? 360 : 0))
                                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isScanning)
                            }

                            Image(systemName: isScanning ? "wave.3.right.circle.fill" : "creditcard.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(isScanning ? .blue : .secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Text(scanStatus)
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        if isScanning {
                            Text(String(format: "%.0f / 300 seconds", elapsedTime))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(L("wallet_scan_instruction"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.vertical, 20)
                }

                Section(header: Text(L("section_actions"))) {
                    if isScanning {
                        Button(L("wallet_scan_cancel")) {
                            stopScanning()
                            dismiss()
                        }
                    } else {
                        Button(L("wallet_scan_start")) {
                            startScanning()
                        }
                    }
                }
            }
            .navigationTitle(L("wallet_scan_card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("alert_close")) {
                        stopScanning()
                        dismiss()
                    }
                }
            }
        }
    }

    private func startScanning() {
        isScanning = true
        elapsedTime = 0
        scanStatus = "Scanning... Open Apple Wallet now"

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedTime += 1
        }

        Task {
            do {
                let cardID = try await scanOneWalletCardID(timeout: 300)
                await MainActor.run {
                    stopScanning()
                    let newCard = AppleWalletCard(id: cardID, name: "Card \(cardID.prefix(8))")
                    walletStore.addCard(newCard)
                    scanStatus = "✓ Successfully scanned card ID!"

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    stopScanning()
                    scanStatus = "✗ Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func stopScanning() {
        isScanning = false
        timer?.invalidate()
        timer = nil
        JITEnableContext.shared.stopSyslogRelay()
    }
}

// MARK: - Edit Card Sheet
struct EditCardSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var card: AppleWalletCard
    @ObservedObject var walletStore: AppleWalletStore
    @State private var cardName: String

    init(card: AppleWalletCard, walletStore: AppleWalletStore) {
        self._card = State(initialValue: card)
        self.walletStore = walletStore
        self._cardName = State(initialValue: card.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("section_card_information"))) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("wallet_card_id_readonly"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(card.id)
                            .font(.system(.body, design: .monospaced))
                    }
                    TextField(L("wallet_card_name"), text: $cardName)
                }
            }
            .navigationTitle(L("edit_card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("alert_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("alert_save")) {
                        var updatedCard = card
                        updatedCard.name = cardName.isEmpty ? "Card \(card.id.prefix(8))" : cardName
                        walletStore.updateCard(updatedCard)
                        dismiss()
                    }
                    .disabled(cardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Card Detail View
struct AppleWalletCardDetailView: View {
    @State var card: AppleWalletCard
    @ObservedObject var walletStore: AppleWalletStore
    @State private var showImagePicker = false
    @State private var selectedImageType: ImageType = .background
    @State private var showDeleteAlert = false
    @State private var showPassJSONImporter = false
    @State private var showImportErrorAlert = false
    @State private var importErrorMessage = ""
    @State private var primaryAccountSuffix: String = ""
    @State private var passJSONData: Data? = nil
    @Environment(\.dismiss) var dismiss

    enum ImageType {
        case background
    }

    private var passJSONFileURL: URL {
        URL.documentsDirectory
            .appendingPathComponent("WalletCards")
            .appendingPathComponent(card.id)
            .appendingPathComponent("pass.json")
    }

    var body: some View {
        Form {
            Section(header: Text(L("section_card_preview"))) {
                if let imageData = card.backgroundImageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(1.586, contentMode: .fit)
                        .cornerRadius(12)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x667eea), Color(hex: 0x764ba2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .aspectRatio(1.586, contentMode: .fit)
                        .overlay(
                            Text(L("wallet_no_image"))
                                .foregroundStyle(.white.opacity(0.6))
                        )
                }
            }

            Section(header: Text(L("section_card_information"))) {
                TextField(L("wallet_card_name"), text: $card.name)
                    .onChange(of: card.name) { _ in walletStore.updateCard(card) }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("wallet_card_id"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(card.id)
                        .font(.system(.body, design: .monospaced))
                }

                Toggle(L("wallet_enable_card"), isOn: $card.enabled)
                    .onChange(of: card.enabled) { _ in walletStore.updateCard(card) }
            }

            Section(header: Text(L("section_image_resolution"))) {
                Picker("Resolution", selection: $card.useRetina) {
                    Text(L("wallet_resolution_2x")).tag(false)
                    Text(L("wallet_resolution_3x")).tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: card.useRetina) { _ in walletStore.updateCard(card) }
            }

            Section(header: Text(L("section_card_images"))) {
                ImagePickerButton(
                    title: "Background Image",
                    subtitle: card.useRetina ? "cardBackgroundCombined@3x.png" : "cardBackgroundCombined@2x.png",
                    hasImage: card.backgroundImageData != nil
                ) {
                    selectedImageType = .background
                    showImagePicker = true
                }
            }

            Section(header: Text(L("wallet_card_display_number"))) {
                if passJSONData != nil {
                    HStack {
                        Image(systemName: "creditcard.fill")
                            .foregroundStyle(.green)
                        Text(L("wallet_card_data_imported"))
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("wallet_display_number_label"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(L("wallet_display_number_placeholder"), text: $primaryAccountSuffix)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .onChange(of: primaryAccountSuffix) { newValue in
                                updatePrimaryAccountSuffixOnDisk(newValue)
                            }
                    }

                    Button {
                        showPassJSONImporter = true
                    } label: {
                        Label(L("wallet_replace_card_data"), systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button(role: .destructive) {
                        deletePassJSON()
                    } label: {
                        Label(L("wallet_delete_card_data"), systemImage: "trash")
                    }
                } else {
                    Button {
                        showPassJSONImporter = true
                    } label: {
                        Label(L("wallet_import_card_data"), systemImage: "doc.badge.plus")
                    }
                }
            }

            Section(header: Text(L("section_danger_zone"))) {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Text(L("alert_delete_card"))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .headerProminence(.increased)
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadPassJSONFromDisk()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(imageData: bindingForImageType(selectedImageType), useRetina: card.useRetina)
        }
        .sheet(isPresented: $showPassJSONImporter) {
            DocumentPickerView(allowedContentTypes: [.data, .item]) { url in
                handlePassJSONImport(url)
            }
        }
        .alert(L("alert_delete_card"), isPresented: $showDeleteAlert) {
            Button(L("alert_cancel"), role: .cancel) {}
            Button(L("alert_delete"), role: .destructive) {
                walletStore.deleteCard(card)
                dismiss()
            }
        } message: {
            Text(L("alert_delete_card_confirm").replacingOccurrences(of: "{cardName}", with: "\(card.name)?"))
        }
        .alert(L("alert_error"), isPresented: $showImportErrorAlert) {
            Button(L("alert_ok")) {}
        } message: {
            Text(importErrorMessage)
        }
    }

    private func bindingForImageType(_ type: ImageType) -> Binding<Data?> {
        Binding(
            get: {
                switch type {
                case .background: return card.backgroundImageData
                }
            },
            set: { newValue in
                switch type {
                case .background: card.backgroundImageData = newValue
                }
                walletStore.updateCard(card)
            }
        )
    }

    private func loadPassJSONFromDisk() {
        let fileURL = passJSONFileURL
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL) {
            passJSONData = data
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                primaryAccountSuffix = json["primaryAccountSuffix"] as? String ?? ""
            }
        } else {
            passJSONData = nil
            primaryAccountSuffix = ""
        }
    }

    private func savePassJSONToDisk(_ data: Data) throws {
        let folderURL = passJSONFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try data.write(to: passJSONFileURL)
    }

    private func deletePassJSON() {
        try? FileManager.default.removeItem(at: passJSONFileURL)
        passJSONData = nil
        primaryAccountSuffix = ""
    }

    private func updatePrimaryAccountSuffixOnDisk(_ newValue: String) {
        guard let currentData = passJSONData,
              var json = try? JSONSerialization.jsonObject(with: currentData) as? [String: Any] else {
            return
        }
        json["primaryAccountSuffix"] = newValue
        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: passJSONFileURL)
            passJSONData = updatedData
        }
    }

    private func handlePassJSONImport(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let importedData = try? Data(contentsOf: url) else {
            importErrorMessage = "Failed to read file: \(url.lastPathComponent)"
            showImportErrorAlert = true
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: importedData) as? [String: Any] else {
            importErrorMessage = "Invalid JSON format. The file must contain a JSON object."
            showImportErrorAlert = true
            return
        }

        do {
            try savePassJSONToDisk(importedData)
        } catch {
            importErrorMessage = "Failed to save pass.json: \(error.localizedDescription)"
            showImportErrorAlert = true
            return
        }

        passJSONData = importedData
        primaryAccountSuffix = json["primaryAccountSuffix"] as? String ?? ""
    }
}

// MARK: - Image Picker Button
struct ImagePickerButton: View {
    let title: String
    let subtitle: String
    let hasImage: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if hasImage {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 20))
                }
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 20))
            }
        }
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Environment(\.dismiss) var dismiss
    let useRetina: Bool

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self, useRetina: useRetina)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        let useRetina: Bool

        init(_ parent: ImagePicker, useRetina: Bool) {
            self.parent = parent
            self.useRetina = useRetina
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()

            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }

            provider.loadObject(ofClass: UIImage.self) { image, error in
                guard let image = image as? UIImage else { return }

                let targetSize: CGSize
                if self.useRetina {
                    targetSize = CGSize(width: 2304, height: 1452)
                } else {
                    targetSize = CGSize(width: 1536, height: 969)
                }

                let resizedImage = self.resizeImage(image, targetSize: targetSize)

                DispatchQueue.main.async {
                    self.parent.imageData = resizedImage.pngData()
                }
            }
        }

        private func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
            let size = image.size
            let widthRatio = targetSize.width / size.width
            let heightRatio = targetSize.height / size.height
            let ratio = min(widthRatio, heightRatio)
            let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

            let renderer = UIGraphicsImageRenderer(size: newSize)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
    }
}

// MARK: - Wallet Card ID Scanner
private enum WalletIDScanError: Error, LocalizedError {
    case timedOut
    case unknownError

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Hết thời gian chờ (Timeout). Vui lòng thêm thẻ vào Wallet và thử lại."
        case .unknownError:
            return "Lỗi không xác định khi quét ID thẻ."
        }
    }
}

private func extractWalletCardID(from line: String) -> String? {
    let patterns = [
        #"PDCardFileManager: writing card\s+([A-Za-z0-9+/]+={0,2})(?=\s|\)|,|$)"#,
        #"PDPassLibrary: wrote pass\s+([A-Za-z0-9+/]+={0,2})(?=\s|\)|,|$)"#,
        #"VerificationCheck\.([A-Za-z0-9+/]+={0,2})(?=\s|\)|,|$)"#
    ]

    for pattern in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

        let nsRange = NSRange(line.startIndex..., in: line)

        if let match = regex.firstMatch(in: line, options: [], range: nsRange) {
            if let range = Range(match.range(at: 1), in: line) {
                return String(line[range])
            }
        }
    }
    return nil
}

func scanOneWalletCardID(timeout: TimeInterval = 300) async throws -> String {
    return try await withCheckedThrowingContinuation { continuation in
        var finished = false

        JITEnableContext.shared.startSyslogRelay { line in
            guard !finished else { return }
            guard let line else { return }

            guard line.localizedCaseInsensitiveContains("passd") else { return }

            if let cardID = extractWalletCardID(from: line) {
                finished = true
                JITEnableContext.shared.stopSyslogRelay()
                continuation.resume(returning: cardID)
            }
        } onError: { error in
            guard !finished else { return }
            finished = true
            JITEnableContext.shared.stopSyslogRelay()
            continuation.resume(throwing: error ?? WalletIDScanError.unknownError)
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            guard !finished else { return }
            finished = true
            JITEnableContext.shared.stopSyslogRelay()
            continuation.resume(throwing: WalletIDScanError.timedOut)
        }
    }
}

// MARK: - Import Default Card Sheet (ZIP)
struct ImportDefaultCardSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var walletStore: AppleWalletStore
    @State private var showFilePicker = false
    @State private var isImporting = false
    @State private var importResult: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button(L("wallet_select_zip")) {
                        showFilePicker = true
                    }
                }

                if isImporting {
                    Section {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text(L("wallet_importing"))
                        }
                    }
                }

                if let result = importResult {
                    Section {
                        Label(result, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle(L("wallet_import_default_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("alert_cancel")) { dismiss() }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPickerView(allowedContentTypes: [.data, .item]) { url in
                    importZIP(url: url)
                }
            }
            .alert(L("alert_error"), isPresented: .constant(errorMessage != nil)) {
                Button(L("alert_ok")) { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }

    private func importZIP(url: URL) {
        isImporting = true
        importResult = nil

        Task {
            do {
                let count = try await performZIPImport(url: url)
                await MainActor.run {
                    isImporting = false
                    importResult = "Imported \(count) card(s)"
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    errorMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func performZIPImport(url: URL) async throws -> Int {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let tempZIP = tempDir.appendingPathComponent("import.zip")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try fm.copyItem(at: url, to: tempZIP)

        let extractDir = tempDir.appendingPathComponent("extracted")
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try fm.unzipItem(at: tempZIP, to: extractDir)

        defer { try? fm.removeItem(at: tempDir) }

        var pkpassFolders: [(id: String, url: URL)] = []

        func scanForPkpass(at dirURL: URL) {
            guard let items = try? fm.contentsOfDirectory(atPath: dirURL.path) else { return }
            for item in items {
                let itemURL = dirURL.appendingPathComponent(item)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: itemURL.path, isDirectory: &isDir)

                if isDir.boolValue && item.hasSuffix(".pkpass") {
                    let cardID = String(item.dropLast(".pkpass".count))
                    if !cardID.isEmpty {
                        pkpassFolders.append((id: cardID, url: itemURL))
                    }
                }
            }
        }

        scanForPkpass(at: extractDir)

        if pkpassFolders.isEmpty {
            if let topItems = try? fm.contentsOfDirectory(atPath: extractDir.path) {
                for item in topItems {
                    let subDir = extractDir.appendingPathComponent(item)
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: subDir.path, isDirectory: &isDir)
                    if isDir.boolValue {
                        scanForPkpass(at: subDir)
                    }
                }
            }
        }

        guard !pkpassFolders.isEmpty else {
            throw NSError(domain: "ImportDefaultCard", code: 1, userInfo: [NSLocalizedDescriptionKey: "No .pkpass folders found in ZIP"])
        }

        var importedCount = 0

        for folder in pkpassFolders {
            let cardID = folder.id
            let folderURL = folder.url

            let cardName = "Card \(String(cardID.prefix(8)))..."

            await MainActor.run {
                if !walletStore.cards.contains(where: { $0.id == cardID }) {
                    let newCard = AppleWalletCard(id: cardID, name: cardName)
                    walletStore.addCard(newCard)
                }
            }

            let cardFolder = URL.documentsDirectory
                .appendingPathComponent("WalletCards")
                .appendingPathComponent(cardID)
            try fm.createDirectory(at: cardFolder, withIntermediateDirectories: true)

            guard let files = try? fm.contentsOfDirectory(atPath: folderURL.path) else { continue }

            for filename in files {
                let srcFile = folderURL.appendingPathComponent(filename)
                var isFileDir: ObjCBool = false
                fm.fileExists(atPath: srcFile.path, isDirectory: &isFileDir)
                guard !isFileDir.boolValue else { continue }

                let destFile = cardFolder.appendingPathComponent(filename)

                try? fm.removeItem(at: destFile)
                try fm.copyItem(at: srcFile, to: destFile)
            }

            importedCount += 1
        }

        return importedCount
    }
}