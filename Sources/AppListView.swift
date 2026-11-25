import SwiftUI

struct AppItemView: View {
    let appDetails: [String : Any]
    let bundleID: String
    var body: some View {
        Form {
            NavigationLink {
                List {
                    ForEach(Array(appDetails.keys), id: \.self) { k in
                        let v = appDetails[k] as? String
                        VStack(alignment: .leading) {
                            Text(k)
                            Text(v ?? "(not a String)")
                                .font(Font.footnote)
                                .textSelection(.enabled)
                        }
                    }
                }
            } label: {
                Text(L("app_view_details"))
            }
            Section(header: Text(L("section_arbitrary_read"))) {
                if let bundlePath = appDetails["Path"] {
                    Button(L("app_copy_bundle")) {
                        UIPasteboard.general.string = "file://a\(bundlePath)"
                    }
                }
                if let containerPath = appDetails["Container"] {
                    Button(L("app_copy_data")) {
                        UIPasteboard.general.string = "file://a\(containerPath)"
                    }
                }
            }
        }
        .navigationTitle((appDetails["CFBundleName"] as? String) ?? bundleID)
    }

    init(bundleID: String) {
        self.bundleID = bundleID
        self.appDetails = ["Loading": AnyCodable("...")]
    }

    init(appDetails: [String: Any]) {
        self.appDetails = appDetails
        self.bundleID = (appDetails["CFBundleIdentifier"] as? String) ?? ""
    }
}

struct AppListView: View {
    @State var apps: [String : [String : Any]] = [:]
    @State var appIcons: [String : UIImage] = [:]
    @State var searchString: String = ""

    var results: [String] {
        let filtered: [String]
        if searchString.isEmpty {
            filtered = Array(apps.keys)
        } else {
            let q = searchString.lowercased()
            filtered = apps.compactMap { key, appDetails in
                let appName = (appDetails["CFBundleName"] as? String ?? "").lowercased()
                let appPath = (appDetails["Path"] as? String ?? "").lowercased()
                let bid = (appDetails["CFBundleIdentifier"] as? String ?? key).lowercased()
                return (appName.contains(q) || appPath.contains(q) || bid.contains(q)) ? key : nil
            }
        }
        return filtered.sorted { a, b in
            let nameA = (apps[a]?["CFBundleName"] as? String) ?? a
            let nameB = (apps[b]?["CFBundleName"] as? String) ?? b
            return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
        }
    }

    var body: some View {
        List {
            ForEach(results, id: \.self) { bundleID in
                let appDetails = apps[bundleID]
                let appName = (appDetails?["CFBundleName"] as? String) ?? bundleID
                let appBundleID = (appDetails?["CFBundleIdentifier"] as? String) ?? bundleID
                NavigationLink {
                    if let details = appDetails {
                        AppItemView(appDetails: details)
                    } else {
                        AppItemView(bundleID: bundleID)
                    }
                } label: {
                    Image(uiImage: appIcons[bundleID] ?? UIImage(systemName: "app")!)
                        .resizable()
                        .frame(width: 40, height: 40)
                        .task(id: bundleID) {
                            guard appIcons[bundleID] == nil else { return }
                            await MainActor.run {
                                appIcons[bundleID] = UIImage(systemName: "app")
                            }
                            let icon = await Task.detached(priority: .background) {
                                try? JITEnableContext.shared.getAppIcon(withBundleId: bundleID)
                            }.value
                            await MainActor.run {
                                if let icon { appIcons[bundleID] = icon }
                            }
                        }
                    VStack(alignment: .leading) {
                        Text(appName)
                        Text(appBundleID).font(Font.footnote)
                    }
                }
            }
        }
        .onAppear {
            Task {
                do {
                    let loaded = try await Task.detached(priority: .userInitiated) {
                        try JITEnableContext.shared.getAllAppsInfo() as? [String : [String : Any]] ?? [:]
                    }.value
                    
                    // Nạp toàn bộ bundleID -> Container UUID vào cache bền vững của zPatch
                    zPatchStore.shared.updateContainerCache(from: loaded)
                    
                    await MainActor.run {
                        apps = loaded
                    }
                } catch {
                    await MainActor.run {
                        apps = ["\(L("error_prefix").replacingOccurrences(of: "{error}", with: "\(error)"))": [:]]
                    }
                }
            }
        }
        .searchable(text: $searchString)
        .navigationTitle(L("app_list_title"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    init() {
        apps = ["Loading": [:]]
    }
}
