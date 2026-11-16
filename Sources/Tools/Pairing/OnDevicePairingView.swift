import SwiftUI

struct OnDevicePairingView: View {
    @StateObject private var manager = OnDevicePairingManager()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Form {
            Section {
                if manager.isPairing {
                    VStack(spacing: 16) {
                        Text(L("pair_enter_pin_title"))
                            .font(.headline)
                        
                        HStack {
                            Text(manager.pin.isEmpty ? "------" : manager.pin)
                                .font(.system(size: 48, weight: .bold, design: .monospaced))
                                .foregroundStyle(.blue)
                            
                            if !manager.pin.isEmpty {
                                Button {
                                    UIPasteboard.general.string = manager.pin
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.title2)
                                }
                            }
                        }
                        
                        Text(L("pair_step_instruction"))
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else if manager.isSuccess {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text(L("pair_success_title"))
                            .font(.headline)
                        Button(L("alert_close")) { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    Button(L("pair_start_btn")) {
                        manager.startPairing()
                    }
                }
            } header: {
                Text(L("pair_on_device"))
            } footer: {
                Text(L("pair_background_info"))
            }
            
            if !manager.statusLog.isEmpty {
                Section("Log") {
                    ForEach(manager.statusLog, id: \.self) { line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            
            if manager.isPairing {
                Section {
                    Button(L("alert_cancel"), role: .destructive) {
                        manager.stopPairing()
                    }
                }
            }
        }
        .navigationTitle(L("pair_on_device"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            manager.stopPairing()
        }
    }
}