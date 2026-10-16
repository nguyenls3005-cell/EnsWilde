import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct KeypadView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @StateObject private var mgr = KeypadManager.shared
    @State private var showImporter = false
    @State private var showApplyAlert = false
    @State private var applyAlertMessage = ""
    @State private var selectedSize: KPSize = .defSize
    @State private var customWidth: String = "205"
    @State private var customHeight: String = "205"
    @State private var circleMask: Bool = false

    var body: some View {
        Form {
            Section(header: Text("Dialer Theme")) {
                Text("Thay ảnh các nút số trong app Phone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("Keys")) {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(mgr.mpKeypad) { item in
                        keypadPreview(item: item)
                    }
                }
                .padding(.vertical, 8)
            }

            Section(header: Text("Options")) {
                Picker("Size", selection: $selectedSize) {
                    ForEach(KPSize.allCases, id: \.self) { size in
                        Text(size.label).tag(size)
                    }
                }

                if selectedSize == .custom {
                    HStack {
                        Text("Width")
                        Spacer()
                        TextField("205", text: $customWidth)
                            .keyboardType(.numberPad)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("205", text: $customHeight)
                            .keyboardType(.numberPad)
                            .frame(width: 80)
                    }
                }

                Toggle("Circle mask", isOn: $circleMask)
            }

            Section {
                Button {
                    mgr.getCurrentKeypads(
                        size: selectedSize,
                        custW: Int(customWidth) ?? 205,
                        custH: Int(customHeight) ?? 205,
                        saveOgData: true
                    )
                } label: {
                    Label("Load current keys", systemImage: "arrow.down.circle")
                }

                Button {
                    showImporter = true
                } label: {
                    Label("Import .passthm theme", systemImage: "doc.badge.plus")
                }

                Button(role: .destructive) {
                    _ = mgr.resetKeypadItems()
                    applyAlertMessage = "Đã reset keypad. Mở Phone app để thấy thay đổi."
                    showApplyAlert = true
                } label: {
                    Label("Reset all keys", systemImage: "trash")
                }
            }

            Section {
                Button {
                    let success = mgr.applyKeypadItems()
                    applyAlertMessage = success
                        ? "Đã apply. Mở Phone app và đổi appearance để thấy thay đổi."
                        : "Apply failed. Xem console log để biết chi tiết."
                    showApplyAlert = true
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Apply Keypad Theme")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
            }
        }
        .headerProminence(.increased)
        .navigationTitle("Dialer Themer")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [
                UTType(filenameExtension: "passthm") ?? .zip,
                .zip
            ]
        ) { result in
            switch result {
            case .success(let url):
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                let ok = mgr.importTheme(fromURL: url)
                applyAlertMessage = ok ? "Import theme thành công." : "Import thất bại."
                showApplyAlert = true
            case .failure(let error):
                applyAlertMessage = "File picker error: \(error.localizedDescription)"
                showApplyAlert = true
            }
        }
        .alert("Dialer Themer", isPresented: $showApplyAlert) {
            Button("OK") {}
        } message: {
            Text(applyAlertMessage)
        }
        .onAppear {
            mgr.getCurrentKeypads(saveOgData: true)
        }
    }

    @ViewBuilder
    private func keypadPreview(item: KeypadItem) -> some View {
        VStack(spacing: 4) {
            if !item.imgData.isEmpty, let uiImg = UIImage(data: item.imgData) {
                Image(uiImage: uiImg)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Text(keypadLabel(item.kpID))
                            .font(.headline)
                    )
            }
            Text(keypadLabel(item.kpID))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func keypadLabel(_ id: KeypadID) -> String {
        switch id {
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .star: return "*"
        case .zero: return "0"
        case .pound: return "#"
        }
    }
}
