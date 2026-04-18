/// Pure Swift handles and identifiers for APIs backed by SwiftUsd/OpenUSD.
///
/// This module must not import SwiftUsd, OpenUSD, or any C++ interop target.
/// Runtime packages own the mapping between these handles and native USD objects.
public struct USDStageHandle: Hashable, Sendable, Codable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

public struct USDPrimHandle: Hashable, Sendable, Codable {
    public let stage: USDStageHandle
    public let path: USDPath

    public init(stage: USDStageHandle, path: USDPath) {
        self.stage = stage
        self.path = path
    }
}

public struct USDPath: Hashable, Sendable, Codable, ExpressibleByStringLiteral,
    CustomStringConvertible
{
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String {
        rawValue
    }
}

public struct USDAssetPath: Hashable, Sendable, Codable, ExpressibleByStringLiteral,
    CustomStringConvertible
{
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String {
        rawValue
    }
}

public struct USDToken: Hashable, Sendable, Codable, ExpressibleByStringLiteral,
    CustomStringConvertible
{
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String {
        rawValue
    }
}

public enum USDLoadPolicy: Hashable, Sendable, Codable {
    case loadAll
    case loadNone
}

public enum USDValue: Hashable, Sendable, Codable {
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case token(USDToken)
    case assetPath(USDAssetPath)
    case vector2(USDVector2)
    case vector3(USDVector3)
    case vector4(USDVector4)
    case matrix4x4(USDMatrix4x4)
    case array([USDValue])
    case unsupported(typeName: String, description: String)
}

public extension USDValue {
    var displayDescription: String {
        switch self {
        case .bool(let value):
            value ? "true" : "false"
        case .int(let value):
            String(value)
        case .double(let value):
            String(value)
        case .string(let value):
            value
        case .token(let value):
            value.rawValue
        case .assetPath(let value):
            value.rawValue
        case .vector2(let value):
            "(\(value.x), \(value.y))"
        case .vector3(let value):
            "(\(value.x), \(value.y), \(value.z))"
        case .vector4(let value):
            "(\(value.x), \(value.y), \(value.z), \(value.w))"
        case .matrix4x4(let value):
            value.values.map { String($0) }.joined(separator: ", ")
        case .array(let values):
            values.map(\.displayDescription).joined(separator: ", ")
        case .unsupported(_, let description):
            description
        }
    }
}

public struct USDVector2: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct USDVector3: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct USDVector4: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var w: Double

    public init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
}

public struct USDMatrix4x4: Hashable, Sendable, Codable {
    public var values: [Double]

    public init(values: [Double]) {
        self.values = values
    }
}

public struct USDTimeCode: Hashable, Sendable, Codable {
    public enum Kind: Hashable, Sendable, Codable {
        case `default`
        case earliest
        case numeric(Double)
    }

    public var kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public static var `default`: Self {
        Self(.default)
    }

    public static var earliest: Self {
        Self(.earliest)
    }

    public static func numeric(_ value: Double) -> Self {
        Self(.numeric(value))
    }
}

public struct USDAttributeSummary: Hashable, Sendable, Codable {
    public var name: USDToken
    public var typeName: String
    public var value: USDValue?
    public var isAuthored: Bool
    public var hasValue: Bool
    public var timeSampleCount: Int
    public var timeSamples: [USDTimeCode]

    public init(
        name: USDToken,
        typeName: String,
        value: USDValue? = nil,
        isAuthored: Bool = false,
        hasValue: Bool = false,
        timeSampleCount: Int = 0,
        timeSamples: [USDTimeCode] = []
    ) {
        self.name = name
        self.typeName = typeName
        self.value = value
        self.isAuthored = isAuthored
        self.hasValue = hasValue
        self.timeSampleCount = timeSampleCount
        self.timeSamples = timeSamples
    }
}

public struct USDRelationshipSummary: Hashable, Sendable, Codable {
    public var name: USDToken
    public var targets: [USDPath]

    public init(name: USDToken, targets: [USDPath] = []) {
        self.name = name
        self.targets = targets
    }
}

public struct USDPrimSummary: Hashable, Sendable, Codable {
    public var path: USDPath
    public var name: USDToken
    public var typeName: USDToken?
    public var isActive: Bool
    public var visibility: USDToken?
    public var purpose: USDToken?
    public var kind: USDToken?
    public var attributes: [USDAttributeSummary]
    public var relationships: [USDRelationshipSummary]

    public init(
        path: USDPath,
        name: USDToken,
        typeName: USDToken? = nil,
        isActive: Bool = true,
        visibility: USDToken? = nil,
        purpose: USDToken? = nil,
        kind: USDToken? = nil,
        attributes: [USDAttributeSummary] = [],
        relationships: [USDRelationshipSummary] = []
    ) {
        self.path = path
        self.name = name
        self.typeName = typeName
        self.isActive = isActive
        self.visibility = visibility
        self.purpose = purpose
        self.kind = kind
        self.attributes = attributes
        self.relationships = relationships
    }
}

public enum SwiftUsdShellError: Error, Equatable, Sendable {
    case missingStage(USDStageHandle)
    case missingPrim(USDPrimHandle)
    case invalidPath(String)
    case runtimeUnavailable
}
