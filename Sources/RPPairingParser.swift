import Foundation

struct RPPairingData {
    let publicKey: Data
    let privateKey: Data
    let identifier: String
    let altIRK: Data
}

enum RPPairingError: Error, LocalizedError {
    case invalidFormat
    case missingKey(String)
    case invalidBase64(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "File không phải RPPairing format"
        case .missingKey(let key):
            return "Thiếu key: \(key)"
        case .invalidBase64(let key):
            return "Key \(key) không phải base64 hợp lệ"
        }
    }
}

enum RPPairingParser {

    /// Parse RPPairing plist data
    static func parse(_ data: Data) throws -> RPPairingData {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw RPPairingError.invalidFormat
        }

        // public_key (Data)
        guard let publicKey = plist["public_key"] as? Data else {
            // Try base64 string fallback
            if let str = plist["public_key"] as? String,
               let decoded = Data(base64Encoded: str) {
                // OK
            } else {
                throw RPPairingError.missingKey("public_key")
            }
            throw RPPairingError.missingKey("public_key")
        }

        // private_key (Data)
        guard let privateKey = plist["private_key"] as? Data else {
            throw RPPairingError.missingKey("private_key")
        }

        // identifier (String)
        guard let identifier = plist["identifier"] as? String else {
            throw RPPairingError.missingKey("identifier")
        }

        // alt_irk (Data)
        guard let altIRK = plist["alt_irk"] as? Data else {
            throw RPPairingError.missingKey("alt_irk")
        }

        return RPPairingData(
            publicKey: publicKey,
            privateKey: privateKey,
            identifier: identifier,
            altIRK: altIRK
        )
    }

    /// Validate file
    static func validate(_ data: Data) -> Bool {
        return (try? parse(data)) != nil
    }
}