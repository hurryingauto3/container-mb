import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

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
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value.rounded() == value ? String(Int64(value)) : String(value)
        case .bool(let value):
            return String(value)
        case .object, .array, .null:
            return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            return Double(value)
        case .bool, .object, .array, .null:
            return nil
        }
    }

    public var uint64Value: UInt64? {
        switch self {
        case .number(let value) where value >= 0:
            return UInt64(value)
        case .string(let value):
            return UInt64(value)
        default:
            return nil
        }
    }

    public var intValue: Int? {
        switch self {
        case .number(let value):
            return Int(value)
        case .string(let value):
            return Int(value)
        default:
            return nil
        }
    }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    public func value(at path: [String]) -> JSONValue? {
        path.reduce(Optional(self)) { partial, key in
            partial?[key]
        }
    }

    public func firstValue(for keys: [String]) -> JSONValue? {
        guard let objectValue else { return nil }
        for key in keys {
            if let value = objectValue[key] {
                return value
            }
        }
        return nil
    }

    public func deepValues(named name: String) -> [JSONValue] {
        switch self {
        case .object(let object):
            return object.flatMap { key, value -> [JSONValue] in
                var values = value.deepValues(named: name)
                if key == name {
                    values.insert(value, at: 0)
                }
                return values
            }
        case .array(let array):
            return array.flatMap { $0.deepValues(named: name) }
        case .string, .number, .bool, .null:
            return []
        }
    }
}
