import SwiftUI

@main
struct MyApp: App {
    @AppStorage("hasChosenMode") private var hasChosenMode: Bool = false
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    
    init() {
        // ✅ Reset trạng thái Tab Apply mỗi khi app khởi động lại từ đầu
        // (Khi bị vuốt khỏi đa nhiệm hoặc kill hẳn)
        UserDefaults.standard.set(false, forKey: "ShowApplyTab")
    }
    
    var body: some Scene {
        WindowGroup {
            if !hasChosenMode && isVersionBlocked() {
                VersionBlockedView()
            } else {
                MainViewWithNavigation()
            }
        }
    }
    
    private func isVersionBlocked() -> Bool {
        let version = UIDevice.current.systemVersion
        return version.hasPrefix("27.0")
    }
}

struct VersionBlockedView: View {
    @AppStorage("isAirLiftMode") private var isAirLiftMode: Bool = false
    @AppStorage("hasChosenMode") private var hasChosenMode: Bool = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                
                Text("iOS Version Not Supported")
                    .font(.title.bold())
                    .foregroundColor(.white)
                
                Text("This app only supports iOS versions 27.0 Developer Beta 1-4 / Public Beta 1-2")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("Your current iOS version:")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Text(UIDevice.current.systemVersion)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("To use this app:")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.gray)
                        Text("Downgrade to iOS 27 Developer Beta 4 or earlier")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                    }
                    
                    HStack(spacing: 10) {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundColor(.gray)
                        Text("Contact the developer for support")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                    }
                    
                    Divider().background(Color.gray)
                    
                    Button(action: {
                        withAnimation {
                            isAirLiftMode = true
                            hasChosenMode = true
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "airplane.circle.fill")
                            Text("Tiếp tục với AirLift (Không có MobileGestalt)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(25)
                    }
                    .padding(.top, 10)
                }
                .padding(20)
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)
                .padding(.horizontal)
            }
        }
    }
}