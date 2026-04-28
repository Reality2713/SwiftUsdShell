import Foundation
import simd

/// Pure Swift handles and identifiers for APIs backed by SwiftUsd/OpenUSD.
///
/// This module must not import SwiftUsd, OpenUSD, or any C++ interop target.
/// Runtime packages own the mapping between these handles and native USD objects.
public struct USDStageURL: Hashable, Sendable, Codable, CustomStringConvertible {
    public let url: URL

    public init(_ url: URL) {
        self.url = url.standardizedFileURL
    }

    public var description: String {
        url.path
    }
}

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

public struct USDQuaternion: Hashable, Sendable, Codable {
    public var real: Double
    public var imaginary: USDVector3

    public init(real: Double, imaginary: USDVector3) {
        self.real = real
        self.imaginary = imaginary
    }

    public static var identity: Self {
        Self(real: 1, imaginary: USDVector3(x: 0, y: 0, z: 0))
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

public enum USDDiagnosticSeverity: String, Hashable, Sendable, Codable, CaseIterable {
    case info
    case warning
    case error
}

public struct USDDiagnostic: Hashable, Sendable, Codable {
    public var severity: USDDiagnosticSeverity
    public var code: String?
    public var message: String
    public var subjectPath: USDPath?

    public init(
        severity: USDDiagnosticSeverity = .info,
        code: String? = nil,
        message: String,
        subjectPath: USDPath? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.subjectPath = subjectPath
    }
}

public enum USDPrimSpecifier: String, Hashable, Sendable, Codable, CaseIterable {
    case def
    case over
    case class_ = "class"
    case unknown
}

public struct USDPrimSummary: Hashable, Sendable, Codable {
    public var path: USDPath
    public var name: USDToken
    public var typeName: USDToken?
    public var specifier: USDPrimSpecifier?
    public var isDefined: Bool?
    public var isActive: Bool
    public var isAbstract: Bool
    public var isInstanceable: Bool
    public var visibility: USDToken?
    public var purpose: USDToken?
    public var kind: USDToken?
    public var attributes: [USDAttributeSummary]
    public var relationships: [USDRelationshipSummary]

    public init(
        path: USDPath,
        name: USDToken,
        typeName: USDToken? = nil,
        specifier: USDPrimSpecifier? = nil,
        isDefined: Bool? = nil,
        isActive: Bool = true,
        isAbstract: Bool = false,
        isInstanceable: Bool = false,
        visibility: USDToken? = nil,
        purpose: USDToken? = nil,
        kind: USDToken? = nil,
        attributes: [USDAttributeSummary] = [],
        relationships: [USDRelationshipSummary] = []
    ) {
        self.path = path
        self.name = name
        self.typeName = typeName
        self.specifier = specifier
        self.isDefined = isDefined
        self.isActive = isActive
        self.isAbstract = isAbstract
        self.isInstanceable = isInstanceable
        self.visibility = visibility
        self.purpose = purpose
        self.kind = kind
        self.attributes = attributes
        self.relationships = relationships
    }
}

public extension USDPrimSummary {
    var typeNameText: String {
        typeName?.rawValue ?? ""
    }

    var visibilityText: String {
        visibility?.rawValue ?? "inherited"
    }

    var purposeText: String {
        purpose?.rawValue ?? "default"
    }

    var kindText: String {
        kind?.rawValue ?? ""
    }
}

public struct USDPrimTree: Hashable, Sendable, Codable, Identifiable {
    public var id: USDPath { path }
    public var path: USDPath
    public var name: USDToken
    public var typeName: USDToken?
    public var specifier: USDPrimSpecifier?
    public var isActive: Bool
    public var isInstanceable: Bool
    public var purpose: USDToken?
    public var children: [USDPrimTree]

    public init(
        path: USDPath,
        name: USDToken,
        typeName: USDToken? = nil,
        specifier: USDPrimSpecifier? = nil,
        isActive: Bool = true,
        isInstanceable: Bool = false,
        purpose: USDToken? = nil,
        children: [USDPrimTree] = []
    ) {
        self.path = path
        self.name = name
        self.typeName = typeName
        self.specifier = specifier
        self.isActive = isActive
        self.isInstanceable = isInstanceable
        self.purpose = purpose
        self.children = children
    }
}

public struct USDStageMetadata: Hashable, Sendable, Codable {
    public var upAxis: USDToken?
    public var metersPerUnit: Double?
    public var defaultPrimName: USDToken?
    public var autoPlay: Bool?
    public var playbackMode: String?
    public var timeCodesPerSecond: Double?
    public var startTimeCode: Double?
    public var endTimeCode: Double?
    public var animationTracks: [USDPath]
    public var availableCameras: [USDPath]

    public init(
        upAxis: USDToken? = nil,
        metersPerUnit: Double? = nil,
        defaultPrimName: USDToken? = nil,
        autoPlay: Bool? = nil,
        playbackMode: String? = nil,
        timeCodesPerSecond: Double? = nil,
        startTimeCode: Double? = nil,
        endTimeCode: Double? = nil,
        animationTracks: [USDPath] = [],
        availableCameras: [USDPath] = []
    ) {
        self.upAxis = upAxis
        self.metersPerUnit = metersPerUnit
        self.defaultPrimName = defaultPrimName
        self.autoPlay = autoPlay
        self.playbackMode = playbackMode
        self.timeCodesPerSecond = timeCodesPerSecond
        self.startTimeCode = startTimeCode
        self.endTimeCode = endTimeCode
        self.animationTracks = animationTracks
        self.availableCameras = availableCameras
    }
}

public extension USDStageMetadata {
    var hasAnimationTracks: Bool {
        animationTracks.isEmpty == false
    }

    var hasUsableTimelineRange: Bool {
        guard let startTimeCode, let endTimeCode else { return false }
        return endTimeCode > startTimeCode
    }
}

public extension USDPrimTree {
    var displayName: String {
        name.rawValue.isEmpty ? path.rawValue : name.rawValue
    }

    var typeNameText: String {
        typeName?.rawValue ?? ""
    }

    var purposeText: String {
        purpose?.rawValue ?? "default"
    }

    var nodeCount: Int {
        1 + children.reduce(0) { $0 + $1.nodeCount }
    }

    func first(path targetPath: USDPath) -> USDPrimTree? {
        if path == targetPath {
            return self
        }
        for child in children {
            if let match = child.first(path: targetPath) {
                return match
            }
        }
        return nil
    }
}

// MARK: - Material Inspection DTOs

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
    public var properties: [USDMaterialPropertySummary]

    public init(
        path: USDPath,
        name: String,
        materialType: USDMaterialSummaryType,
        properties: [USDMaterialPropertySummary] = []
    ) {
        self.path = path
        self.name = name
        self.materialType = materialType
        self.properties = properties
    }
}

public enum USDMaterialBindingStrength: String, Hashable, Sendable, Codable, CaseIterable {
    case fallbackStrength
    case weakerThanDescendants
    case strongerThanDescendants

    public var displayName: String {
        switch self {
        case .fallbackStrength: return "Default"
        case .weakerThanDescendants: return "Weaker"
        case .strongerThanDescendants: return "Stronger"
        }
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

// MARK: - Transform Inspection DTOs

public struct USDTransformData: Hashable, Sendable, Codable {
    public var position: SIMD3<Double>
    public var rotationDegrees: SIMD3<Double>
    public var orientation: USDQuaternion?
    public var scale: SIMD3<Double>

    public init(
        position: SIMD3<Double> = .zero,
        rotationDegrees: SIMD3<Double> = .zero,
        orientation: USDQuaternion? = nil,
        scale: SIMD3<Double> = SIMD3<Double>(repeating: 1)
    ) {
        self.position = position
        self.rotationDegrees = rotationDegrees
        self.orientation = orientation
        self.scale = scale
    }
}

public enum USDTransformEditCapability: String, Hashable, Sendable, Codable {
    case editableCommon
    case editablePivoted
    case editableSeparateEuler
    case readonlyAnimated
    case readonlyMatrix
    case readonlyOrient
    case readonlyUnsupportedCustomStack
    case notXformable

    public var isEditable: Bool {
        switch self {
        case .editableCommon, .editablePivoted, .editableSeparateEuler:
            true
        case .readonlyAnimated,
             .readonlyMatrix,
             .readonlyOrient,
             .readonlyUnsupportedCustomStack,
             .notXformable:
            false
        }
    }
}

public enum USDTransformEditRestriction: String, Hashable, Sendable, Codable {
    case animatedTransformOp
    case matrixTransformOp
    case orientTransformOp
    case partialEulerStack
    case customTransformStack
    case unsupportedPivotStack
    case unsupportedOp
    case nonXformablePrim
}

public enum USDAuthoredXformOpKind: Hashable, Sendable, Codable {
    case translate
    case rotateXYZ
    case rotateX
    case rotateY
    case rotateZ
    case scale
    case pivot
    case orient
    case transform
    case custom(token: String)
}

public enum USDAuthoredXformOpPrecision: String, Hashable, Sendable, Codable {
    case half
    case float
    case double
    case unknown
}

public enum USDAuthoredXformOpValue: Hashable, Sendable, Codable {
    case vector3(SIMD3<Double>)
    case quaternion(USDQuaternion)
    case scalar(Double)
    case text(String)
}

public struct USDAuthoredXformOp: Hashable, Sendable, Codable {
    public var token: String
    public var kind: USDAuthoredXformOpKind
    public var precision: USDAuthoredXformOpPrecision
    public var isInverseOp: Bool
    public var isAuthored: Bool
    public var isTimeSampled: Bool
    public var value: USDAuthoredXformOpValue?

    public init(
        token: String,
        kind: USDAuthoredXformOpKind,
        precision: USDAuthoredXformOpPrecision,
        isInverseOp: Bool = false,
        isAuthored: Bool = true,
        isTimeSampled: Bool = false,
        value: USDAuthoredXformOpValue? = nil
    ) {
        self.token = token
        self.kind = kind
        self.precision = precision
        self.isInverseOp = isInverseOp
        self.isAuthored = isAuthored
        self.isTimeSampled = isTimeSampled
        self.value = value
    }
}

public struct USDTransformInspection: Hashable, Sendable, Codable {
    public var localTransform: USDTransformData
    public var authoredOps: [USDAuthoredXformOp]
    public var editCapability: USDTransformEditCapability
    public var restrictionReason: USDTransformEditRestriction?
    public var isAnimated: Bool

    public init(
        localTransform: USDTransformData = .init(),
        authoredOps: [USDAuthoredXformOp] = [],
        editCapability: USDTransformEditCapability = .notXformable,
        restrictionReason: USDTransformEditRestriction? = nil,
        isAnimated: Bool = false
    ) {
        self.localTransform = localTransform
        self.authoredOps = authoredOps
        self.editCapability = editCapability
        self.restrictionReason = restrictionReason
        self.isAnimated = isAnimated
    }
}

public enum USDTransformAuthoringStyle: String, Hashable, Sendable, Codable {
    case runtimeDefault
    case preserveCompatibleAuthoredStack
    case commonTRSRotateXYZ
    case commonTRSOrient
}

public struct USDTransformEditOptions: Hashable, Sendable, Codable {
    public var authoringStyle: USDTransformAuthoringStyle
    public var timeCode: USDTimeCode
    public var allowCreatingMissingOps: Bool

    public init(
        authoringStyle: USDTransformAuthoringStyle = .runtimeDefault,
        timeCode: USDTimeCode = .default,
        allowCreatingMissingOps: Bool = true
    ) {
        self.authoringStyle = authoringStyle
        self.timeCode = timeCode
        self.allowCreatingMissingOps = allowCreatingMissingOps
    }
}

// MARK: - Statistics & Model Info DTOs

public struct USDSceneBounds: Hashable, Sendable, Codable {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>
    public var center: SIMD3<Float>
    public var maxExtent: Float

    public init(
        min: SIMD3<Float> = .zero,
        max: SIMD3<Float> = .zero,
        center: SIMD3<Float> = .zero,
        maxExtent: Float = 0
    ) {
        self.min = min
        self.max = max
        self.center = center
        self.maxExtent = maxExtent
    }
}

public struct USDGeometryStatistics: Hashable, Sendable, Codable {
    public var totalTriangles: Int
    public var totalVertices: Int
    public var meshCount: Int
    public var materialCount: Int
    public var textureCount: Int

    public init(
        totalTriangles: Int = 0,
        totalVertices: Int = 0,
        meshCount: Int = 0,
        materialCount: Int = 0,
        textureCount: Int = 0
    ) {
        self.totalTriangles = totalTriangles
        self.totalVertices = totalVertices
        self.meshCount = meshCount
        self.materialCount = materialCount
        self.textureCount = textureCount
    }
}

public enum USDAnimatableStatus: String, Hashable, Sendable, Codable {
    case animatable
    case static_
    case unknown
}

public struct USDBlendShapeInfo: Hashable, Sendable, Codable {
    public var path: String
    public var name: String
    public var weightCount: Int
    public var weightNames: [String]

    public init(
        path: String,
        name: String,
        weightCount: Int = 0,
        weightNames: [String] = []
    ) {
        self.path = path
        self.name = name
        self.weightCount = weightCount
        self.weightNames = weightNames
    }
}

public struct USDModelInfo: Hashable, Sendable, Codable {
    public var boundsExtent: SIMD3<Float>
    public var boundsCenter: SIMD3<Float>
    public var scale: SIMD3<Float>
    public var upAxis: String
    public var animationCount: Int
    public var animationNames: [String]
    public var metersPerUnit: Double
    public var autoPlay: Bool?
    public var playbackMode: String?
    public var animatableStatus: USDAnimatableStatus
    public var hasAnimationLibrary: Bool
    public var skeletonJointCount: Int
    public var maxJointInfluences: Int
    public var hasSkinnedMesh: Bool
    public var blendShapes: [USDBlendShapeInfo]

    public init(
        boundsExtent: SIMD3<Float> = .zero,
        boundsCenter: SIMD3<Float> = .zero,
        scale: SIMD3<Float> = .one,
        upAxis: String = "Unknown",
        animationCount: Int = 0,
        animationNames: [String] = [],
        metersPerUnit: Double = 1.0,
        autoPlay: Bool? = nil,
        playbackMode: String? = nil,
        animatableStatus: USDAnimatableStatus = .unknown,
        hasAnimationLibrary: Bool = false,
        skeletonJointCount: Int = 0,
        maxJointInfluences: Int = 0,
        hasSkinnedMesh: Bool = false,
        blendShapes: [USDBlendShapeInfo] = []
    ) {
        self.boundsExtent = boundsExtent
        self.boundsCenter = boundsCenter
        self.scale = scale
        self.upAxis = upAxis
        self.animationCount = animationCount
        self.animationNames = animationNames
        self.metersPerUnit = metersPerUnit
        self.autoPlay = autoPlay
        self.playbackMode = playbackMode
        self.animatableStatus = animatableStatus
        self.hasAnimationLibrary = hasAnimationLibrary
        self.skeletonJointCount = skeletonJointCount
        self.maxJointInfluences = maxJointInfluences
        self.hasSkinnedMesh = hasSkinnedMesh
        self.blendShapes = blendShapes
    }
}

// MARK: - Material Editing DTOs

public enum USDMaterialSurfaceOutputFamily: String, Hashable, Sendable, Codable, CaseIterable {
    case usdPreviewSurface
    case materialXPreviewSurface
    case openPBR
}

public enum USDMaterialAuthoringTarget: String, Hashable, Sendable, Codable {
    case usdPreviewSurface
    case materialXPreviewSurface
    case openPBR
}

public enum USDMaterialEditableChannelID: String, Hashable, Sendable, Codable, CaseIterable {
    case diffuseColor
    case metallic
    case roughness
    case normal
    case occlusion
    case opacity
    case emissiveColor
    case clearcoat
    case clearcoatRoughness
}

public enum USDMaterialEditableChannelOperation: String, Hashable, Sendable, Codable, CaseIterable {
    case setTexture
    case clearTexture
    case setScalar
    case setColor
    case clearValue
}

public enum USDMaterialSemanticValue: Hashable, Sendable, Codable {
    case bool(Bool)
    case scalar(Float)
    case integer(Int)
    case color3(red: Float, green: Float, blue: Float)
    case string(String)
    case token(USDToken)
}

public enum USDMaterialEditOperation: Hashable, Sendable, Codable {
    case setTexture(sourceURL: USDStageURL, authoredAssetPath: USDAssetPath?)
    case clearTexture
    case setValue(USDMaterialSemanticValue)
    case clearValue
}

public struct USDMaterialEditRequest: Hashable, Sendable, Codable {
    public var stageURL: USDStageURL
    public var materialPath: USDPath
    public var channel: USDMaterialEditableChannelID
    public var operation: USDMaterialEditOperation

    public init(
        stageURL: USDStageURL,
        materialPath: USDPath,
        channel: USDMaterialEditableChannelID,
        operation: USDMaterialEditOperation
    ) {
        self.stageURL = stageURL
        self.materialPath = materialPath
        self.channel = channel
        self.operation = operation
    }
}

public enum USDMaterialAuthoredMode: String, Hashable, Sendable, Codable {
    case usdPreviewSurface
    case materialXPreviewSurface
    case openPBR
    case mixed
    case unknown
}

public struct USDMaterialEditResult: Hashable, Sendable, Codable {
    public var resultingMode: USDMaterialAuthoredMode
    public var changedPrimPaths: [USDPath]
    public var changedAssetPaths: [USDAssetPath]
    public var warnings: [String]
    public var convertedTo: USDMaterialAuthoringTarget?

    public init(
        resultingMode: USDMaterialAuthoredMode,
        changedPrimPaths: [USDPath] = [],
        changedAssetPaths: [USDAssetPath] = [],
        warnings: [String] = [],
        convertedTo: USDMaterialAuthoringTarget? = nil
    ) {
        self.resultingMode = resultingMode
        self.changedPrimPaths = changedPrimPaths
        self.changedAssetPaths = changedAssetPaths
        self.warnings = warnings
        self.convertedTo = convertedTo
    }
}

// MARK: - Runtime Contracts

public struct USDStageInspectionOptions: Hashable, Sendable, Codable {
    public var loadPolicy: USDLoadPolicy
    public var includePrimTree: Bool
    public var includeStatistics: Bool
    public var includeBounds: Bool

    public init(
        loadPolicy: USDLoadPolicy = .loadAll,
        includePrimTree: Bool = true,
        includeStatistics: Bool = false,
        includeBounds: Bool = false
    ) {
        self.loadPolicy = loadPolicy
        self.includePrimTree = includePrimTree
        self.includeStatistics = includeStatistics
        self.includeBounds = includeBounds
    }
}

public struct USDStageInspectionRequest: Hashable, Sendable, Codable {
    public var stageURL: USDStageURL
    public var options: USDStageInspectionOptions

    public init(
        stageURL: USDStageURL,
        options: USDStageInspectionOptions = .init()
    ) {
        self.stageURL = stageURL
        self.options = options
    }
}

public struct USDStageInspection: Hashable, Sendable, Codable {
    public var stageURL: USDStageURL
    public var metadata: USDStageMetadata
    public var primTree: USDPrimTree?
    public var statistics: USDGeometryStatistics?
    public var bounds: USDSceneBounds?
    public var diagnostics: [USDDiagnostic]

    public init(
        stageURL: USDStageURL,
        metadata: USDStageMetadata = .init(),
        primTree: USDPrimTree? = nil,
        statistics: USDGeometryStatistics? = nil,
        bounds: USDSceneBounds? = nil,
        diagnostics: [USDDiagnostic] = []
    ) {
        self.stageURL = stageURL
        self.metadata = metadata
        self.primTree = primTree
        self.statistics = statistics
        self.bounds = bounds
        self.diagnostics = diagnostics
    }
}

public struct USDPrimInspectionOptions: Hashable, Sendable, Codable {
    public var timeCode: USDTimeCode
    public var includeAttributes: Bool
    public var includeRelationships: Bool
    public var includeCompositionArcs: Bool
    public var includeVariantSets: Bool
    public var includeTransform: Bool
    public var includeMaterialBinding: Bool
    public var includeBounds: Bool

    public init(
        timeCode: USDTimeCode = .default,
        includeAttributes: Bool = true,
        includeRelationships: Bool = true,
        includeCompositionArcs: Bool = true,
        includeVariantSets: Bool = true,
        includeTransform: Bool = true,
        includeMaterialBinding: Bool = false,
        includeBounds: Bool = false
    ) {
        self.timeCode = timeCode
        self.includeAttributes = includeAttributes
        self.includeRelationships = includeRelationships
        self.includeCompositionArcs = includeCompositionArcs
        self.includeVariantSets = includeVariantSets
        self.includeTransform = includeTransform
        self.includeMaterialBinding = includeMaterialBinding
        self.includeBounds = includeBounds
    }
}

public struct USDPrimInspectionRequest: Hashable, Sendable, Codable {
    public var stageURL: USDStageURL
    public var primPath: USDPath
    public var options: USDPrimInspectionOptions

    public init(
        stageURL: USDStageURL,
        primPath: USDPath,
        options: USDPrimInspectionOptions = .init()
    ) {
        self.stageURL = stageURL
        self.primPath = primPath
        self.options = options
    }
}

public enum USDCompositionArcKind: String, Hashable, Sendable, Codable, CaseIterable {
    case reference
    case payload
}

public struct USDLayerOffset: Hashable, Sendable, Codable {
    public var offset: Double
    public var scale: Double

    public init(offset: Double = 0, scale: Double = 1) {
        self.offset = offset
        self.scale = scale
    }
}

public struct USDCompositionArcSummary: Hashable, Sendable, Codable {
    public var kind: USDCompositionArcKind
    public var assetPath: USDAssetPath?
    public var primPath: USDPath?
    public var layerOffset: USDLayerOffset?
    public var isInternal: Bool

    public init(
        kind: USDCompositionArcKind,
        assetPath: USDAssetPath? = nil,
        primPath: USDPath? = nil,
        layerOffset: USDLayerOffset? = nil,
        isInternal: Bool = false
    ) {
        self.kind = kind
        self.assetPath = assetPath
        self.primPath = primPath
        self.layerOffset = layerOffset
        self.isInternal = isInternal
    }
}

public struct USDVariantSetSummary: Hashable, Sendable, Codable, Identifiable {
    public var id: USDToken { name }
    public var name: USDToken
    public var choices: [USDToken]
    public var selection: USDToken?
    public var hasAuthoredSelection: Bool

    public init(
        name: USDToken,
        choices: [USDToken] = [],
        selection: USDToken? = nil,
        hasAuthoredSelection: Bool = false
    ) {
        self.name = name
        self.choices = choices
        self.selection = selection
        self.hasAuthoredSelection = hasAuthoredSelection
    }
}

public struct USDPrimInspection: Hashable, Sendable, Codable {
    public var prim: USDPrimSummary
    public var compositionArcs: [USDCompositionArcSummary]
    public var variantSets: [USDVariantSetSummary]
    public var transform: USDTransformInspection?
    public var materialBinding: USDMaterialBindingInfo?
    public var bounds: USDSceneBounds?
    public var diagnostics: [USDDiagnostic]

    public init(
        prim: USDPrimSummary,
        compositionArcs: [USDCompositionArcSummary] = [],
        variantSets: [USDVariantSetSummary] = [],
        transform: USDTransformInspection? = nil,
        materialBinding: USDMaterialBindingInfo? = nil,
        bounds: USDSceneBounds? = nil,
        diagnostics: [USDDiagnostic] = []
    ) {
        self.prim = prim
        self.compositionArcs = compositionArcs
        self.variantSets = variantSets
        self.transform = transform
        self.materialBinding = materialBinding
        self.bounds = bounds
        self.diagnostics = diagnostics
    }
}

public struct USDEditRefreshHints: Hashable, Sendable, Codable {
    public var reloadViewport: Bool
    public var refreshSceneGraph: Bool
    public var refreshInspector: Bool
    public var invalidateThumbnails: Bool
    public var changedPrimPaths: [USDPath]
    public var changedAssetPaths: [USDAssetPath]
    public var selectionPath: USDPath?

    public init(
        reloadViewport: Bool = false,
        refreshSceneGraph: Bool = false,
        refreshInspector: Bool = true,
        invalidateThumbnails: Bool = false,
        changedPrimPaths: [USDPath] = [],
        changedAssetPaths: [USDAssetPath] = [],
        selectionPath: USDPath? = nil
    ) {
        self.reloadViewport = reloadViewport
        self.refreshSceneGraph = refreshSceneGraph
        self.refreshInspector = refreshInspector
        self.invalidateThumbnails = invalidateThumbnails
        self.changedPrimPaths = changedPrimPaths
        self.changedAssetPaths = changedAssetPaths
        self.selectionPath = selectionPath
    }
}

public enum USDEditRequest: Hashable, Sendable, Codable {
    case setDefaultPrim(stageURL: USDStageURL, primPath: USDPath)
    case setMetersPerUnit(stageURL: USDStageURL, value: Double)
    case setUpAxis(stageURL: USDStageURL, axis: USDToken)
    case setPrimTransform(
        stageURL: USDStageURL,
        primPath: USDPath,
        transform: USDTransformData,
        options: USDTransformEditOptions
    )
    case save(stageURL: USDStageURL)
}

public struct USDEditResult: Hashable, Sendable, Codable {
    public var refreshHints: USDEditRefreshHints
    public var diagnostics: [USDDiagnostic]

    public init(
        refreshHints: USDEditRefreshHints = .init(),
        diagnostics: [USDDiagnostic] = []
    ) {
        self.refreshHints = refreshHints
        self.diagnostics = diagnostics
    }
}

public protocol USDStageRuntime: Sendable {
    func inspectStage(_ request: USDStageInspectionRequest) async throws -> USDStageInspection
    func inspectPrim(_ request: USDPrimInspectionRequest) async throws -> USDPrimInspection
    func edit(_ request: USDEditRequest) async throws -> USDEditResult
}

public enum SwiftUsdShellError: Error, Equatable, Sendable, Codable {
    case fileNotFound(USDStageURL)
    case stageOpenFailed(USDStageURL, diagnostic: String?)
    case missingStage(USDStageHandle)
    case missingPrim(USDPrimHandle)
    case primNotFound(stageURL: USDStageURL, primPath: USDPath)
    case invalidPath(String)
    case unsupportedSchema(String)
    case invalidValue(String)
    case saveFailed(USDStageURL, diagnostic: String?)
    case runtimeUnavailable
    case underlyingDiagnostic(String)
}
