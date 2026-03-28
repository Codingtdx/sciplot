import Foundation

enum SheetValue: Codable, Hashable, Sendable {
    case index(Int)
    case name(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let index = try? container.decode(Int.self) {
            self = .index(index)
        } else {
            self = .name(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .index(value):
            try container.encode(value)
        case let .name(value):
            try container.encode(value)
        }
    }

    var displayName: String {
        switch self {
        case let .index(value):
            return "Sheet \(value)"
        case let .name(value):
            return value
        }
    }

    var requestValue: String {
        switch self {
        case let .index(value):
            return String(value)
        case let .name(value):
            return value
        }
    }
}
