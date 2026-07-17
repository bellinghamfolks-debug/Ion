import Foundation

/// A user account as returned by the server.
struct AuthUser: Codable, Equatable, Identifiable {
    let id: Int
    let email: String?
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id, email, displayName
    }
}

// MARK: - Auth request / response bodies

struct AuthResponse: Decodable {
    let token: String
    let user: AuthUser
}

struct RegisterBody: Encodable {
    let email: String
    let password: String
    let displayName: String
}

struct LoginBody: Encodable {
    let email: String
    let password: String
}

struct AppleSignInBody: Encodable {
    let identityToken: String
    let displayName: String
}

struct MeResponse: Decodable {
    let user: AuthUser
}

// MARK: - Progress sync bodies

struct ProgressPushBody: Encodable {
    let data: JSONValue
}

struct ProgressPushResponse: Decodable {
    // Server timestamp as a raw ISO string (Postgres includes fractional
    // seconds, which Swift's .iso8601 decoder rejects — so we keep it as text
    // and stamp the local sync time ourselves).
    let updatedAt: String?
}

struct ProgressPullResponse: Decodable {
    let data: JSONValue?
    let updatedAt: String?
}

/// A minimal, lossless representation of arbitrary JSON. Used to carry the
/// opaque progress backup blob to and from the server without modelling every
/// field. Round-trips through `JSONEncoder`/`JSONDecoder`.
indirect enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
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
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
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

    /// Decode raw JSON bytes (e.g. a backup blob) into a `JSONValue`.
    static func from(data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Re-encode this value back into raw JSON bytes.
    func encodedData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
