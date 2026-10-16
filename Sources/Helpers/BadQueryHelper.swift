import Foundation

let bq = BadQuery()

class BadQuery {

    @discardableResult
    func grantAccess(atPath directory: String, toFileName fileName: String = "") -> (Bool, Int64, String) {
        var dirCs = directory.utf8CString.map { Int8($0) }
        let res: Int64

        if !fileName.isEmpty {
            var fileNameCs = fileName.utf8CString.map { Int8($0) }
            res = bad_query(&dirCs, false, nil, false, &fileNameCs)
        } else {
            res = bad_query(&dirCs, false, nil, false, nil)
        }

        var errorString: String?
        switch res {
        case -1: errorString = "failed to resolve one or more functions"
        case -2: errorString = "failed to create sandbox query"
        case -3: errorString = "outside of containermanager's sandbox"
        case -4: errorString = "kernel rejected sandbox query"
        default: errorString = nil
        }

        let path = fileName.isEmpty ? directory : "\(directory)/\(fileName)"
        let readable = fm.isReadableFile(atPath: path)
        let writable = fm.isWritableFile(atPath: path)

        if !writable || !readable {
            errorString = "file not actually readable/writable to this app's sandbox"
        }

        if let errorString {
            print("(bq) failed to get access at \(directory)! \(fileName.isEmpty ? "" : "file: \(fileName) ")res: \(res), \(errorString)")
            return (false, res, errorString)
        } else {
            print("(bq) access granted at \(directory)")
            return (true, res, "succeeded")
        }
    }

    func getPathsOfDir(atPath path: String, maxInode: Int64 = 100000) -> [String] {
        var array = [""]
        path.withCString { pathPtr in
            guard let res = bad_query_list(UnsafeMutablePointer(mutating: pathPtr), maxInode) else {
                return
            }
            defer { free(res) }
            let string = String(cString: res)
            array = string.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        }
        return array
    }
}

let fsHandlers = FSHandlers()

class FSHandlers {
    func getDirPaths(_ path: String, maxInode: Int64 = 10000000) -> [String] {
        var array = [""]
        path.withCString { pathPtr in
            guard let res = bad_query_list(UnsafeMutablePointer(mutating: pathPtr), maxInode) else {
                return
            }
            defer { free(res) }
            let string = String(cString: res)
            array = string.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        }
        return array
    }
}