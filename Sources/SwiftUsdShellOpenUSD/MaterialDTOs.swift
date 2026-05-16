// Material DTOs moved from SwiftUsdShell public API.
// ShellOpenUSD owns these C++ material interpretation types.
// Consumed by OpenUSDKitMaterialInspectionClientLive.

import SwiftUsdShell

public enum USDMaterialSummaryType: String, Hashable, Sendable, Codable {
    case usdPreviewSurface
    case materialX
    case unknown
}

public enum USDMaterialPropertyType: String, Hashable, Sendable, Codable {
    case bool
    case color
    case float
    case int
    case string
    case texture
    case token
    case unsupported
}

public enum USDMaterialPropertyInfo: Hashable, Sendable, Codable {
    case bool(Bool)
    case color(red: Float, green: Float, blue: Float)
    case float(Float)
    case int(Int)
    case string(String)
    case texture(url: String, resolvedPath: String?)
    case token(String)
    case unsupported(typeName: String, valueDescription: String)
}

public struct USDMaterialPropertySummary: Hashable, Sendable, Codable {
    public var name: String
    public var propertyType: USDMaterialPropertyType
    public var value: USDMaterialPropertyInfo

    public init(
        name: String,
        propertyType: USDMaterialPropertyType,
        value: USDMaterialPropertyInfo
    ) {
        self.name = name
        self.propertyType = propertyType
        self.value = value
    }
}

public struct USDMaterialSummary: Hashable, Sendable, Codable, Identifiable {
    public var id: USDPath { path }
    public var path: USDPath
    public var name: String
    public var materialType: USDMaterialSummaryType
    public var isInstanceable: Bool
    public var compositionArcs: [USDCompositionArcSummary]
    public var properties: [USDMaterialPropertySummary]

    public init(
        path: USDPath,
        name: String,
        materialType: USDMaterialSummaryType,
        isInstanceable: Bool = false,
        compositionArcs: [USDCompositionArcSummary] = [],
        properties: [USDMaterialPropertySummary] = []
    ) {
        self.path = path
        self.name = name
        self.materialType = materialType
        self.isInstanceable = isInstanceable
        self.compositionArcs = compositionArcs
        self.properties = properties
    }
}

public struct USDMaterialBindingInfo: Hashable, Sendable, Codable {
    public var selectedPrimPath: USDPath
    public var effectiveMaterialPath: USDPath?
    public var authoredMaterialPath: USDPath?
    public var bindingSourcePrimPath: USDPath?
    public var bindingStrength: USDMaterialBindingStrength?

    public init(
        selectedPrimPath: USDPath,
        effectiveMaterialPath: USDPath? = nil,
        authoredMaterialPath: USDPath? = nil,
        bindingSourcePrimPath: USDPath? = nil,
        bindingStrength: USDMaterialBindingStrength? = nil
    ) {
        self.selectedPrimPath = selectedPrimPath
        self.effectiveMaterialPath = effectiveMaterialPath
        self.authoredMaterialPath = authoredMaterialPath
        self.bindingSourcePrimPath = bindingSourcePrimPath
        self.bindingStrength = bindingStrength
    }
}
