import SwiftUI
import Combine

enum MGURL {
    static let fsGestaltURL = URL(fileURLWithPath: "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist")
    static let savedGestaltURL = URL.documentsDirectory.appendingPathComponent("OriginalGestalt.plist")
}

enum MGKey {
    static let ipadosCacheEx = [
        "uKc7FPnEO++lVhHWHFlGbQ", "mG0AnH/Vy1veoqoLRAIgTA", "UCG5MkVahJxG1YULbbd5Bg",
        "ZYqko/XM5zD3XBfN5RmaXA", "nVh/gwNpy7Jv1NOk00CMrw", "qeaj75wk3HF4DwQ8qbIi7g"
    ]
    static let island = "YlEtTtHlNesRBMal1CqRaA"
    static let AOD = "2OOJf1VhaM7NxfRok3HbWQ"
    static let AOTime = "j8/Omm6s1lsmTDFsXjsBfA"
    static let AODVibrancy = "ykpu7qyhqFweVMKtxNylWA"
    static let chargeLim = "37NVydb//GP/GrhuTN+exg"
    static let bootChime = "QHxt+hGLaBPbQJbXiUJX3w"
    static let intInstall = "EqrsVvjcYDdxHBiQmGhAWw"
    static let intBuild = "LBJfwOEzExRxzlAnSuI7eg"
    static let srd = "XYlJKKkj2hztRP1NWWnhlw"
    static let appIntell = "A62OafQ85EJAiiqKn4agtg"
    static let stageMgr = "qeaj75wk3HF4DwQ8qbIi7g"
    static let crashDet = "HCzWusHQwZDea6nNhaKndw"
    static let appPencil = "yhHcB0iH0d1XzPO/CFd3ow"
    static let camButton = "CwvKxM2cEogD3p+HYgaW0Q"
    static let grapPefr = "oOV1jhJbdV3AddkcCg0AEA"
    static let actButton = "cT44WE1EohiwRzhsZ8xEsw"
    static let tapToWake = "yZf3GTRMGTuwSV/lD7Cagw"
    static let deviceClass = "+3Uf0Pm5F8Xy7Onyvko0vA"
    static let artwork = "oPeik/9e8lQWMszEjbPzng"
    static let prodType = "h9jDsbgj7xIVeIQ8S3/X3Q"
}

final class GestaltStore: ObservableObject {
    static let shared = GestaltStore()
    
    @Published var mgCurrentDict = NSMutableDictionary()
    
    var cacheExtra: NSMutableDictionary {
        if let existing = mgCurrentDict["CacheExtra"] as? NSMutableDictionary {
            return existing
        } else {
            let newDict = NSMutableDictionary()
            mgCurrentDict["CacheExtra"] = newDict
            return newDict
        }
    }
    
    func loadFromPlist(url: URL) {
        if let dict = try? NSMutableDictionary(contentsOf: url, error: ()) {
            self.mgCurrentDict = dict
            self.objectWillChange.send()
        }
    }
    
    // GHI TRỰC TIẾP VÀO CacheExtra (Chuẩn xác nhất cho mọi iOS)
    func mgByteBinding(key: String, enableValue: UInt8 = 1, disableValue: UInt8 = 0) -> Binding<Bool> {
        return Binding(get: {
            return (self.cacheExtra[key] as? Int) == Int(enableValue)
        }, set: { enabled in
            self.objectWillChange.send()
            
            // Xóa key cũ trước khi ghi mới (tránh xung đột kiểu dữ liệu)
            self.cacheExtra.removeObject(forKey: key)
            
            if enabled {
                self.cacheExtra[key] = Int(enableValue)
            }
        })
    }

    // BINDING CHO iPADOS (Giữ nguyên hàm Hex vì nó hoạt động tốt)
    func mgTrollPadBinding() -> Binding<Bool> {
        return Binding(get: {
            if let value = self.cacheExtra[MGKey.ipadosCacheEx.first!] as? Int { return value == 1 }
            return false
        }, set: { enabled in
            self.objectWillChange.send()
            
            for key in MGKey.ipadosCacheEx {
                if enabled { self.cacheExtra[key] = 1 }
                else { self.cacheExtra.removeObject(forKey: key) }
            }
            
            if self.mgCurrentDict["CacheData"] is Data {
                _ = self.mgSetiPadOS(enable: enabled)
            }
        })
    }
    
    // HÀM HEX CHO iPADOS (Erosion)
    func mgSetiPadOS(enable: Bool) -> Bool {
        guard let cacheData = mgCurrentDict["CacheData"] as? Data else { return false }
        let hexString = cacheData.map { String(format: "%02x", $0) }.joined()
        var hex = Array(hexString)
        let sliceStart = 1616
        let sliceLength = 200
        
        guard hex.count > sliceStart else { return false }
        let end = min(hex.count, sliceStart + sliceLength)
        let slice = String(hex[sliceStart..<end])
        guard let regex = try? NSRegularExpression(pattern: "0+(?:5555)*([0-9a-f]{4})") else { return false }
        let nsRange = NSRange(slice.startIndex..<slice.endIndex, in: slice)
        
        var matchedOffset: Int?
        regex.enumerateMatches(in: slice, range: nsRange) { match, _, stop in
            guard let match = match, let range = Range(match.range(at: 1), in: slice) else { return }
            let value = slice[range]
            if value.filter({ $0 != "0" }).count >= 3 {
                matchedOffset = sliceStart + slice.distance(from: slice.startIndex, to: range.lowerBound)
                stop.pointee = true
            }
        }
        
        guard let offset = matchedOffset else { return false }
        let rightOffset = offset + 13
        let leftOffset = offset - 67
        
        guard leftOffset > 0, rightOffset < hex.count - 1 else { return false }
        for position in [leftOffset, rightOffset] {
            guard ["1", "3"].contains(String(hex[position])), hex[position - 1] == "0", hex[position + 1] == "0" else { return false }
        }
        
        hex[leftOffset] = enable ? "3" : "1"
        let updatedHex = String(hex)
        var updatedData = Data(capacity: updatedHex.count / 2)
        var index = updatedHex.startIndex
        while index < updatedHex.endIndex {
            let next = updatedHex.index(index, offsetBy: 2)
            guard next <= updatedHex.endIndex, let byte = UInt8(updatedHex[index..<next], radix: 16) else { return false }
            updatedData.append(byte)
            index = next
        }
        mgCurrentDict["CacheData"] = updatedData
        return true
    }
}