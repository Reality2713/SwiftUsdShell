/// A single validation issue produced by the OpenUSD validation registry.
public struct USDValidationIssue: Equatable, Hashable, Sendable, Codable {
    public var name: String
    public var identifier: String
    public var severity: USDValidationSeverity
    public var message: String
    public var validatorName: String
    public var sites: [USDValidationSite]

    public init(
        name: String,
        identifier: String,
        severity: USDValidationSeverity,
        message: String,
        validatorName: String,
        sites: [USDValidationSite] = []
    ) {
        self.name = name
        self.identifier = identifier
        self.severity = severity
        self.message = message
        self.validatorName = validatorName
        self.sites = sites
    }
}

public enum USDValidationSeverity: String, Equatable, Hashable, Sendable, Codable {
    case none
    case info
    case warning
    case error
}

public struct USDValidationSite: Equatable, Hashable, Sendable, Codable {
    public var kind: String
    public var objectPath: String
    public var layerIdentifier: String

    public init(kind: String, objectPath: String, layerIdentifier: String) {
        self.kind = kind
        self.objectPath = objectPath
        self.layerIdentifier = layerIdentifier
    }
}
