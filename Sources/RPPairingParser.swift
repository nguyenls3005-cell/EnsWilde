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

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "File không phải RPPairing format (không đọc được plist)"
        case .missingKey(let key):
            return "Thiếu key bắt buộc: \(key)"
        }
    }
}

enum RPPairingParser {

    /// Parse RPPairing plist data
    static func parse(_ data: Data) throws -> RPPairingData {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw RPPairingError.invalidFormat
        }

        guard let publicKey = plist["public_key"] as? Data else {
            throw RPPairingError.missingKey("public_key")
        }

        guard let privateKey = plist["private_key"] as? Data else {
            throw RPPairingError.missingKey("private_key")
        }

        guard let identifier = plist["identifier"] as? String else {
            throw RPPairingError.missingKey("identifier")
        }

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