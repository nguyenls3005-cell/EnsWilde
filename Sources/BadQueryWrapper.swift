import Foundation

enum BadQueryError: Error, LocalizedError {
    case cantResolve
    case cantCreateQuery
    case outsideSandbox
    case kernelDenied
    case unknown(Int64)

    var errorDescription: String? {
        switch self {
        case .cantResolve:       return "bad_query: cannot resolve symbol"
        case .cantCreateQuery:   return "bad_query: cannot create sandbox query"
        case .outsideSandbox:    return "bad_query: path outside sandbox"
        case .kernelDenied:      return "bad_query: kernel denied"
        case .unknown(let code): return "bad_query: unknown error \(code)"
        }
    }
}

enum BadQueryWrapper {
    static func writeFile(
        at path: String,
        data: Data,
        groupIdentifier: String? = nil,
        isGroup: Bool = false
    ) throws {
        var cPath = path.cString(using: .utf8)!

        let handle: Int64
        if let group = groupIdentifier {
            var cGroup = group.cString(using: .utf8)!
            handle = bad_query(&cPath, true, &cGroup, isGroup)
        } else {
            handle = bad_query(&cPath, true, nil, false)
        }

        switch handle {
        case -1: throw BadQueryError.cantResolve
        case -2: throw BadQueryError.cantCreateQuery
        case -3: throw BadQueryError.outsideSandbox
        case -4: throw BadQueryError.kernelDenied
        default: break
        }

        guard handle > 0 else {
            throw BadQueryError.unknown(Int64(handle))   // ← ÉP KIỂU Int64
        }
        defer { bad_query_release(handle) }

        try data.write(to: URL(fileURLWithPath: path))
    }
}