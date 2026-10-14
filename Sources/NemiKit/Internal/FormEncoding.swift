import Foundation

/// `application/x-www-form-urlencoded` encoding that escapes everything outside
/// the RFC 3986 unreserved set. `URLComponents` leaves `+` alone, which a form
/// decoder reads as a space, so it is not used here.
enum FormEncoding {
    private static let unreserved: CharacterSet = {
        var set = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    static func encode(_ pairs: [(String, String)]) -> Data {
        let body = pairs.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&")
        return Data(body.utf8)
    }

    static func decode(_ data: Data) -> [String: String] {
        guard let string = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for pair in string.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(parts[0])
            let value = parts.count > 1
                ? (String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(parts[1]))
                : ""
            result[key] = value
        }
        return result
    }
}
