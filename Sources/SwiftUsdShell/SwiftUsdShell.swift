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

public enum SwiftUsdShellError: Error, Equatable, Sendable {
    case missingStage(USDStageHandle)
    case missingPrim(USDPrimHandle)
    case invalidPath(String)
    case runtimeUnavailable
}
