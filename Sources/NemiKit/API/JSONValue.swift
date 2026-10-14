import Foundation

/// Any JSON value. Used for sheet cells, form fields and the parts of a
/// response this SDK version does not model yet.
public enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            // Decoding a `[String: _]` dictionary keeps its keys verbatim, even
            // under `convertFromSnakeCase`, so user data like `"q_1"` survives.
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var stringValue: String? { if case .string(let v) = self { return v } else { return nil } }
    public var doubleValue: Double? { if case .number(let v) = self { return v } else { return nil } }
    public var boolValue: Bool? { if case .bool(let v) = self { return v } else { return nil } }
    public var arrayValue: [JSONValue]? { if case .array(let v) = self { return v } else { return nil } }
    public var objectValue: [String: JSONValue]? { if case .object(let v) = self { return v } else { return nil } }
    public var isNull: Bool { self == .null }

    public subscript(key: String) -> JSONValue? { objectValue?[key] }
    public subscript(index: Int) -> JSONValue? {
        guard let array = arrayValue, array.indices.contains(index) else { return nil }
        return array[index]
    }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

/// Decodes a list whose envelope the contract does not pin down: a bare array,
/// an object with one of the expected keys, or failing that the first array in the object.
struct FlexibleList<Element: Decodable>: Decodable {
    let items: [Element]

    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Set per call through `userInfo`.
    static var keysUserInfoKey: CodingUserInfoKey { CodingUserInfoKey(rawValue: "nemi.flexibleListKeys")! }

    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([Element].self) {
            items = array
            return
        }
        let container = try decoder.container(keyedBy: AnyKey.self)
        let preferred = decoder.userInfo[Self.keysUserInfoKey] as? [String] ?? []
        for key in preferred {
            if let array = try? container.decode([Element].self, forKey: AnyKey(stringValue: key)) {
                items = array
                return
            }
        }
        for key in container.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
            if let array = try? container.decode([Element].self, forKey: key) {
                items = array
                return
            }
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No list found in the response."))
    }
}
