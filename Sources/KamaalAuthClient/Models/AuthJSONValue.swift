//
//  AuthJSONValue.swift
//  KamaalAuth
//

import Foundation

/// A decoded JSON value, used to carry app-specific user fields the package knows nothing about.
public enum AuthJSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AuthJSONValue])
    case array([AuthJSONValue])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AuthJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AuthJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
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

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }

        return value
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }

        return value
    }

    public var numberValue: Double? {
        guard case .number(let value) = self else { return nil }

        return value
    }
}
