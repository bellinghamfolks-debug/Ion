import Foundation

struct AuthUser: Codable, Equatable, Identifiable {
    let id: Int
    let email: String?
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id, email, displayName
    }
}

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

struct GoogleSignInBody: Encodable {
    let idToken: String
    let displayName: String
}

struct MeResponse: Decodable {
    let user: AuthUser
}

struct ProgressPushBody: Encodable {
    let data: JSONValue
}

struct ProgressPushResponse: Decodable {
    let updatedAt: String?
}

struct ProgressPullResponse: Decodable {
    let data: JSONValue?
    let updatedAt: String?
}

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

    static func from(data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    func encodedData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
