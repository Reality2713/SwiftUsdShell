import CxxStdlib
import Foundation
import OpenUSD
import simd
import SwiftUsdShell

typealias USDOverlay = OpenUSD.Overlay
typealias pxr = pxrInternal_v0_26_3__pxrReserved__

typealias UsdStage = pxr.UsdStage
typealias UsdStageRefPtr = pxr.UsdStageRefPtr
typealias UsdPrim = pxr.UsdPrim
typealias UsdPrimRange = pxr.UsdPrimRange
typealias UsdRelationship = pxr.UsdRelationship
typealias UsdAttribute = pxr.UsdAttribute
typealias UsdTimeCode = pxr.UsdTimeCode
typealias UsdGeomImageable = pxr.UsdGeomImageable
typealias UsdGeomMesh = pxr.UsdGeomMesh
typealias UsdGeomXformCommonAPI = pxr.UsdGeomXformCommonAPI
typealias UsdShadeConnectableAPI = pxr.UsdShadeConnectableAPI
typealias SdfReference = pxr.SdfReference
typealias SdfLayerOffset = pxr.SdfLayerOffset
typealias SdfLayer = pxr.SdfLayer
typealias SdfPrimSpec = pxr.SdfPrimSpec
typealias SdfPrimSpecHandle = pxr.SdfPrimSpecHandle
typealias SdfAttributeSpec = pxr.SdfAttributeSpec
typealias SdfAttributeSpecHandle = pxr.SdfAttributeSpecHandle
typealias SdfVariability = pxr.SdfVariability
typealias VtDictionary = pxr.VtDictionary
typealias SdfChangeBlock = pxr.SdfChangeBlock
typealias UsdShadeInput = pxr.UsdShadeInput
typealias UsdShadeAttributeType = pxr.UsdShadeAttributeType
typealias UsdShadeMaterial = pxr.UsdShadeMaterial
typealias UsdShadeMaterialBindingAPI = pxr.UsdShadeMaterialBindingAPI
typealias UsdShadeShader = pxr.UsdShadeShader
typealias UsdModelAPI = pxr.UsdModelAPI
typealias TfToken = pxr.TfToken
typealias SdfPath = pxr.SdfPath
typealias SdfAssetPath = pxr.SdfAssetPath
typealias SdfPathVector = pxr.SdfPathVector
typealias SdfSpecifier = pxr.SdfSpecifier
typealias SdfValueTypeName = pxr.SdfValueTypeName
typealias GfVec2d = pxr.GfVec2d
typealias GfVec2f = pxr.GfVec2f
typealias GfVec2i = pxr.GfVec2i
typealias GfVec3d = pxr.GfVec3d
typealias GfVec3f = pxr.GfVec3f
typealias GfVec3h = pxr.GfVec3h
typealias GfVec3i = pxr.GfVec3i
typealias GfVec4d = pxr.GfVec4d
typealias GfVec4f = pxr.GfVec4f
typealias GfVec4i = pxr.GfVec4i
typealias GfQuatd = pxr.GfQuatd
typealias GfQuatf = pxr.GfQuatf
typealias GfQuath = pxr.GfQuath
typealias VtValue = pxr.VtValue
typealias VtIntArray = pxr.VtIntArray
typealias VtTokenArray = pxr.VtTokenArray
typealias VtVec3fArray = pxr.VtVec3fArray
typealias SdfZipFileWriter = pxr.SdfZipFileWriter
typealias SdfZipFile = pxr.SdfZipFile



private let nonXformableTypeNames: Set<String> = [
    "",
    "animation",
    "geomsubset",
    "material",
    "nodegraph",
    "scope",
    "shader",
    "skelanimation",
]

private struct SparsePrimNode {
    var name: String
    var specifier: USDSparsePrimSpecifier
    var metadata: [USDSparseMetadata]
    var attributes: [USDSparseAttributeOverride]
    var relationships: [USDSparseRelationship]
    var children: [SparsePrimNode]

    init(
        name: String,
        specifier: USDSparsePrimSpecifier,
        metadata: [USDSparseMetadata] = [],
        attributes: [USDSparseAttributeOverride] = [],
        relationships: [USDSparseRelationship] = [],
        children: [SparsePrimNode] = []
    ) {
        self.name = name
        self.specifier = specifier
        self.metadata = metadata
        self.attributes = attributes
        self.relationships = relationships
        self.children = children
    }
}

/// Mechanical runtime adapter that answers SwiftUsdShell requests with OpenUSD.
///
/// This target may import SwiftUsd/OpenUSD. The base SwiftUsdShell target must
/// remain independent from this adapter.
public final class OpenUSDStageRuntime: Sendable {

    public init() {}

    public func inspectStage(_ request: USDStageInspectionRequest) async throws -> USDStageInspection {
        let stage = try stage(for: request.stageURL, loadPolicy: request.options.loadPolicy)
        let metadata = stageMetadata(stage)
        let tree = request.options.includePrimTree ? primTree(stage.GetPseudoRoot()) : nil

        return USDStageInspection(
            stageURL: request.stageURL,
            metadata: metadata,
            primTree: tree,
            statistics: request.options.includeStatistics ? geometryStatistics(stage.GetPseudoRoot()) : nil,
            bounds: request.options.includeBounds ? sceneBounds(stage) : nil,
            diagnostics: collectDiagnostics {
                _ = stage.GetPseudoRoot()
            }
        )
    }

    public func inspectPrim(_ request: USDPrimInspectionRequest) async throws -> USDPrimInspection {
        let stage = try stage(for: request.stageURL, loadPolicy: .loadAll)
        let prim = stage.GetPrimAtPath(SdfPath(std.string(request.primPath.rawValue)))
        guard prim.IsValid() else {
            throw SwiftUsdShellError.primNotFound(stageURL: request.stageURL, primPath: request.primPath)
        }

        let diagnostics = collectDiagnostics {
            _ = prim.GetPath()
        }

        return USDPrimInspection(
            prim: primSummary(
                prim,
                includeAttributes: request.options.includeAttributes,
                includeRelationships: request.options.includeRelationships
            ),
            compositionArcs: request.options.includeCompositionArcs ? compositionArcs(prim) : [],
            variantSets: request.options.includeVariantSets ? variantSets(prim) : [],
            transform: request.options.includeTransform ? transformInspection(prim, timeCode: request.options.timeCode) : nil,
            statistics: request.options.includeStatistics ? geometryStatistics(prim) : nil,
            bounds: request.options.includeBounds
                ? sceneBounds(prim, timeCode: request.options.timeCode)
                : nil,
            diagnostics: diagnostics
        )
    }

    public func edit(_ request: USDEditRequest) async throws -> USDEditResult {
        switch request {
        case .setDefaultPrim(let stageURL, let primPath):
            let stage = try stage(for: stageURL, loadPolicy: .loadAll)
            let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
            guard prim.IsValid() else {
                throw SwiftUsdShellError.primNotFound(stageURL: stageURL, primPath: primPath)
            }
            stage.SetDefaultPrim(prim)
            return USDEditResult(
                refreshHints: USDEditRefreshHints(
                    refreshSceneGraph: true,
                    changedPrimPaths: [primPath],
                    selectionPath: primPath
                )
            )

        case .setMetersPerUnit(let stageURL, let value):
            let stage = try stage(for: stageURL, loadPolicy: .loadAll)
            let ok = pxr.UsdGeomSetStageMetersPerUnit(USDOverlay.TfWeakPtr(stage), value)
            guard ok else {
                throw SwiftUsdShellError.invalidValue("Unable to author metersPerUnit \(value)")
            }
            return USDEditResult(refreshHints: USDEditRefreshHints(refreshInspector: true))

        case .setUpAxis(let stageURL, let axis):
            let stage = try stage(for: stageURL, loadPolicy: .loadAll)
            let ok = pxr.UsdGeomSetStageUpAxis(
                USDOverlay.TfWeakPtr(stage),
                TfToken(std.string(axis.rawValue))
            )
            guard ok else {
                throw SwiftUsdShellError.invalidValue("Unable to author upAxis \(axis.rawValue)")
            }
            return USDEditResult(refreshHints: USDEditRefreshHints(refreshInspector: true))

        case .setPrimTransform(let stageURL, let primPath, let transform, let options):
            let stage = try stage(for: stageURL, loadPolicy: .loadAll)
            let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
            guard prim.IsValid() else {
                throw SwiftUsdShellError.primNotFound(stageURL: stageURL, primPath: primPath)
            }
            try setCommonTransform(transform, on: prim, options: options)
            return USDEditResult(
                refreshHints: USDEditRefreshHints(
                    reloadViewport: true,
                    refreshSceneGraph: false,
                    refreshInspector: true,
                    changedPrimPaths: [primPath],
                    selectionPath: primPath
                )
            )

        case .setDoubleSided(let stageURL, let primPath, let value):
            return try setDoubleSided(stageURL: stageURL, primPath: primPath, value: value)

        case .setSubdivisionScheme(let stageURL, let primPath, let scheme):
            let stage = try stage(for: stageURL, loadPolicy: .loadAll)
            let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
            guard prim.IsValid() else {
                throw SwiftUsdShellError.primNotFound(stageURL: stageURL, primPath: primPath)
            }
            let attr = prim.GetAttribute(TfToken("subdivisionScheme"))
            if attr.IsValid() {
                attr.Set(VtValue(TfToken(std.string(scheme.rawValue))), UsdTimeCode.Default())
            } else {
                let created = prim.CreateAttribute(
                    TfToken("subdivisionScheme"), SdfValueTypeName.Token, false,
                    SdfVariability.SdfVariabilityUniform
                )
                created.Set(VtValue(TfToken(std.string(scheme.rawValue))), UsdTimeCode.Default())
            }
            return USDEditResult(refreshHints: USDEditRefreshHints(refreshInspector: true))

        case .applySchema(let stageURL, let primPath, let schemaName):
            let stage = try stage(for: stageURL, loadPolicy: .loadAll)
            let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
            guard prim.IsValid() else {
                throw SwiftUsdShellError.primNotFound(stageURL: stageURL, primPath: primPath)
            }
            let schema = schemaName.rawValue
            if schema == "MaterialBindingAPI" {
                _ = UsdShadeMaterialBindingAPI.Apply(prim)
            } else if schema == "SkelBindingAPI" {
                _ = pxr.UsdSkelBindingAPI.Apply(prim)
            }
            return USDEditResult(refreshHints: USDEditRefreshHints(refreshInspector: true))

        case .removeSchema(let stageURL, let primPath, let schemaName):
            let stage = try stage(for: stageURL, loadPolicy: .loadAll)
            let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
            guard prim.IsValid() else {
                throw SwiftUsdShellError.primNotFound(stageURL: stageURL, primPath: primPath)
            }
            let schema = schemaName.rawValue
            if schema == "MaterialBindingAPI" {
                let bindingAPI = UsdShadeMaterialBindingAPI(prim)
                bindingAPI.UnbindAllBindings()
            } else if schema == "SkelBindingAPI" {
                _ = prim.RemoveAPI(TfToken("SkelBindingAPI"), TfToken(""))
            }
            return USDEditResult(refreshHints: USDEditRefreshHints(refreshInspector: true))

        case .setGeomSubsetFamilyName(let stageURL, let primPath, let familyName):
            let stage = try stage(for: stageURL, loadPolicy: .loadAll)
            let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
            guard prim.IsValid() else {
                throw SwiftUsdShellError.primNotFound(stageURL: stageURL, primPath: primPath)
            }
            let attr = prim.GetAttribute(TfToken("familyName"))
            if attr.IsValid() {
                attr.Set(VtValue(TfToken(std.string(familyName.rawValue))), UsdTimeCode.Default())
            } else {
                let created = prim.CreateAttribute(
                    TfToken("familyName"), SdfValueTypeName.Token, false,
                    SdfVariability.SdfVariabilityUniform
                )
                created.Set(VtValue(TfToken(std.string(familyName.rawValue))), UsdTimeCode.Default())
            }
            return USDEditResult(refreshHints: USDEditRefreshHints(refreshInspector: true))

        case .setGeomSubsetFamilyType(let stageURL, let primPath, let familyName, let familyType):
            let stage = try stage(for: stageURL, loadPolicy: .loadAll)
            let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
            guard prim.IsValid() else {
                throw SwiftUsdShellError.primNotFound(stageURL: stageURL, primPath: primPath)
            }
            let attrName = "subsetFamily:\(familyName.rawValue):familyType"
            let attr = prim.GetAttribute(TfToken(attrName))
            if attr.IsValid() {
                attr.Set(VtValue(TfToken(std.string(familyType.rawValue))), UsdTimeCode.Default())
            } else {
                let created = prim.CreateAttribute(
                    TfToken(attrName), SdfValueTypeName.Token, false,
                    SdfVariability.SdfVariabilityUniform
                )
                created.Set(VtValue(TfToken(std.string(familyType.rawValue))), UsdTimeCode.Default())
            }
            return USDEditResult(refreshHints: USDEditRefreshHints(refreshInspector: true))

        case .bindMaterial(let stageURL, let primPath, let materialPath, let strength):
            let stage = try stage(for: stageURL, loadPolicy: .loadAll)
            let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
            guard prim.IsValid() else {
                throw SwiftUsdShellError.primNotFound(stageURL: stageURL, primPath: primPath)
            }
            let matPrim = stage.GetPrimAtPath(SdfPath(std.string(materialPath.rawValue)))
            guard matPrim.IsValid() else {
                throw SwiftUsdShellError.primNotFound(stageURL: stageURL, primPath: materialPath)
            }
            let bindingAPI = UsdShadeMaterialBindingAPI.Apply(prim)
            let mat = UsdShadeMaterial(matPrim)
            let strengthToken = TfToken(std.string(strength == .fallbackStrength ? "fallbackStrength" : strength.rawValue))
            bindingAPI.Bind(mat, strengthToken, TfToken(""))
            return USDEditResult(
                refreshHints: USDEditRefreshHints(
                    refreshSceneGraph: true,
                    refreshInspector: true,
                    changedPrimPaths: [primPath]
                )
            )

        case .setMaterialBindingStrength(let stageURL, let primPath, let strength):
            let stage = try stage(for: stageURL, loadPolicy: .loadAll)
            let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
            guard prim.IsValid() else {
                throw SwiftUsdShellError.primNotFound(stageURL: stageURL, primPath: primPath)
            }
            let bindingAPI = UsdShadeMaterialBindingAPI(prim)
            let strengthToken = TfToken(std.string(strength == .fallbackStrength ? "fallbackStrength" : strength.rawValue))
            var bindingRel = bindingAPI.GetDirectBindingRel()
            guard bindingRel.IsValid() else {
                throw SwiftUsdShellError.invalidValue("Missing material binding relationship on \(primPath.rawValue)")
            }
            _ = UsdShadeMaterialBindingAPI.SetMaterialBindingStrength(bindingRel, strengthToken)
            return USDEditResult(
                refreshHints: USDEditRefreshHints(
                    refreshInspector: true,
                    changedPrimPaths: [primPath]
                )
            )

        case .setVariantSelection(let stageURL, let primPath, let setName, let selectionId):
            let stage = try stage(for: stageURL, loadPolicy: .loadAll)
            let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
            guard prim.IsValid() else {
                throw SwiftUsdShellError.primNotFound(stageURL: stageURL, primPath: primPath)
            }
            var variantSets = prim.GetVariantSets()
            var variantSet = variantSets.GetVariantSet(std.string(setName.rawValue))
            guard variantSet.IsValid() else {
                throw SwiftUsdShellError.invalidValue("Failed to access variant set \(setName.rawValue) on \(primPath.rawValue)")
            }
            let ok: Bool
            if let selectionId {
                ok = variantSet.SetVariantSelection(std.string(selectionId.rawValue))
            } else {
                variantSet.ClearVariantSelection()
                ok = true
            }
            guard ok else {
                throw SwiftUsdShellError.invalidValue("Failed to set variant \(setName.rawValue) = \(selectionId?.rawValue ?? "nil") on \(primPath.rawValue)")
            }
            return USDEditResult(
                refreshHints: USDEditRefreshHints(
                    refreshSceneGraph: true,
                    refreshInspector: true,
                    changedPrimPaths: [primPath]
                )
            )

        case .blockAttribute(let stageURL, let primPath, let attributeName):
            let stage = try self.stage(for: stageURL, loadPolicy: .loadAll)
            let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
            guard prim.IsValid() else {
                throw SwiftUsdShellError.primNotFound(stageURL: stageURL, primPath: primPath)
            }
            let attr = prim.GetAttribute(TfToken(std.string(attributeName.rawValue)))
            if attr.IsValid() {
                attr.Block()
            }
            return USDEditResult(refreshHints: USDEditRefreshHints(refreshInspector: true))

        case .setActive(let stageURL, let primPath, let active):
            let stage = try self.stage(for: stageURL, loadPolicy: .loadAll)
            let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
            guard prim.IsValid() else {
                throw SwiftUsdShellError.primNotFound(stageURL: stageURL, primPath: primPath)
            }
            prim.SetActive(active)
            return USDEditResult(refreshHints: USDEditRefreshHints(refreshInspector: true))

        case .setAssetPaths(let stageURL, let edits):
            return try setAssetPaths(stageURL: stageURL, edits: edits)

        case .save(let stageURL):
            let stage = try stage(for: stageURL, loadPolicy: .loadAll)
            stage.Save()
            return USDEditResult(refreshHints: USDEditRefreshHints(refreshInspector: false))
        }
    }

    public func setDoubleSided(
        stageURL: USDStageURL,
        primPath: USDPath,
        value: Bool
    ) throws -> USDEditResult {
        let stage = try stage(for: stageURL, loadPolicy: .loadAll)
        let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
        guard prim.IsValid() else {
            throw SwiftUsdShellError.primNotFound(stageURL: stageURL, primPath: primPath)
        }
        let attr = prim.GetAttribute(TfToken("doubleSided"))
        if attr.IsValid() {
            attr.Set(VtValue(value), UsdTimeCode.Default())
        } else {
            let created = prim.CreateAttribute(
                TfToken("doubleSided"), SdfValueTypeName.Bool, false,
                SdfVariability.SdfVariabilityUniform
            )
            created.Set(VtValue(value), UsdTimeCode.Default())
        }
        return USDEditResult(refreshHints: USDEditRefreshHints(refreshInspector: true))
    }

    public func setAssetPaths(
        stageURL: USDStageURL,
        edits: [USDAssetPathEdit]
    ) throws -> USDEditResult {
        guard !edits.isEmpty else {
            return USDEditResult(refreshHints: USDEditRefreshHints(refreshInspector: false))
        }
        let stage = try self.stage(for: stageURL, loadPolicy: .loadAll)
        var changedPaths = Set<USDPath>()
        for edit in edits {
            let prim = stage.GetPrimAtPath(SdfPath(std.string(edit.primPath.rawValue)))
            guard prim.IsValid() else { continue }
            let attr = prim.GetAttribute(TfToken(std.string(edit.attributeName.rawValue)))
            guard attr.IsValid() else { continue }
            var assetPath = SdfAssetPath(std.string(edit.assetPath))
            guard attr.Set(&assetPath, UsdTimeCode.Default()) else { continue }
            changedPaths.insert(edit.primPath)
        }
        stage.Save()
        return USDEditResult(
            refreshHints: USDEditRefreshHints(
                refreshInspector: true,
                changedPrimPaths: Array(changedPaths),
                changedAssetPaths: edits.map { USDAssetPath($0.assetPath) }
            )
        )
    }

    public func probeCapabilities() -> USDRuntimeCapabilities {
        #if canImport(SwiftUsd_PXR_ENABLE_IMAGING_SUPPORT)
        let hasImaging = true
        #else
        let hasImaging = false
        #endif

        #if canImport(SwiftUsd_PXR_ENABLE_USD_IMAGING_SUPPORT)
        let hasUsdImaging = true
        #else
        let hasUsdImaging = false
        #endif

        #if canImport(SwiftUsd_PXR_ENABLE_MATERIALX_SUPPORT)
        let hasMaterialX = true
        #else
        let hasMaterialX = false
        #endif

        #if canImport(SwiftUsd_PXR_ENABLE_OPENIMAGEIO_SUPPORT)
        let hasOpenImageIO = true
        #else
        let hasOpenImageIO = false
        #endif

        #if canImport(SwiftUsd_PXR_ENABLE_OPENVDB_SUPPORT)
        let hasOpenVDB = true
        #else
        let hasOpenVDB = false
        #endif

        #if canImport(SwiftUsd_PXR_ENABLE_PYTHON_SUPPORT)
        let hasPython = true
        #else
        let hasPython = false
        #endif

        #if canImport(SwiftUsd_PXR_ENABLE_OPENCOLORIO_SUPPORT)
        let hasOpenColorIO = true
        #else
        let hasOpenColorIO = false
        #endif

        #if canImport(SwiftUsd_PXR_ENABLE_IMAGEIO_SUPPORT)
        let hasImageIO = true
        #else
        let hasImageIO = false
        #endif

        #if canImport(SwiftUsd_PXR_ENABLE_EMBREE_SUPPORT)
        let hasEmbree = true
        #else
        let hasEmbree = false
        #endif

        #if canImport(SwiftUsd_PXR_ENABLE_DRACO_SUPPORT)
        let hasDraco = true
        #else
        let hasDraco = false
        #endif

        #if canImport(SwiftUsd_PXR_ENABLE_PTEX_SUPPORT)
        let hasPtex = true
        #else
        let hasPtex = false
        #endif

        #if canImport(SwiftUsd_PXR_ENABLE_PRMAN_SUPPORT)
        let hasPrman = true
        #else
        let hasPrman = false
        #endif

        let hasATC = probeAppleTextureConverter()

        return USDRuntimeCapabilities(
            hasImaging: hasImaging,
            hasUsdImaging: hasUsdImaging,
            hasMaterialX: hasMaterialX,
            hasOpenImageIO: hasOpenImageIO,
            hasOpenVDB: hasOpenVDB,
            hasPython: hasPython,
            hasOpenColorIO: hasOpenColorIO,
            hasImageIO: hasImageIO,
            hasEmbree: hasEmbree,
            hasDraco: hasDraco,
            hasPtex: hasPtex,
            hasPrman: hasPrman,
            hasAppleTextureConverter: hasATC,
            hasATCCompressToFormat: hasATC,
            hasATCCompressMemory: hasATC,
            hasATCDecompressFile: hasATC,
            hasATCCompareFiles: hasATC,
            hasATCConvertGamut: hasATC,
            hasATCGenerateMipmaps: hasATC,
            hasATCResizeWithFilter: hasATC
        )
    }

    private func probeAppleTextureConverter() -> Bool {
        #if os(macOS)
        let fm = FileManager.default
        var candidates: [URL] = []
        if let envDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"], !envDir.isEmpty {
            candidates.append(URL(fileURLWithPath: envDir))
        }
        candidates.append(URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer"))
        if let apps = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Applications"),
            includingPropertiesForKeys: nil
        ) {
            for app in apps where app.lastPathComponent.hasPrefix("Xcode") && app.pathExtension == "app" {
                candidates.append(app.appendingPathComponent("Contents/Developer"))
            }
        }
        for dir in candidates {
            let header = dir.appendingPathComponent("usr/include/AppleTextureConverter.h")
            let lib = dir.appendingPathComponent("usr/lib/libAppleTextureConverter.a")
            if fm.fileExists(atPath: header.path), fm.fileExists(atPath: lib.path) {
                return true
            }
        }
        return false
        #else
        return false
        #endif
    }

    public func registerPlugin(at url: USDStageURL) -> Bool {
        let pluginPath = std.string(url.url.path)
        let plugins = pxr.PlugRegistry.GetInstance().RegisterPlugins(pluginPath)
        return !plugins.empty()
    }

    public func remapSkeletonPaths(
        stage: USDStageURL,
        skeletonPath: USDPath,
        animationPath: USDPath,
        output: USDStageURL
    ) throws -> USDStageURL {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }

        let skelPrim = USDOverlay.Dereference(stagePtr).GetPrimAtPath(
            SdfPath(std.string(skeletonPath.rawValue))
        )
        let animPrim = USDOverlay.Dereference(stagePtr).GetPrimAtPath(
            SdfPath(std.string(animationPath.rawValue))
        )
        guard skelPrim.IsValid(), animPrim.IsValid() else {
            throw SwiftUsdShellError.primNotFound(stageURL: stage, primPath: skeletonPath)
        }

        let jointsAttr = skelPrim.GetAttribute(TfToken("joints"))
        var jointsValue = VtValue()
        guard jointsAttr.IsValid(), jointsAttr.Get(&jointsValue, UsdTimeCode.Default()) else {
            throw SwiftUsdShellError.invalidValue("Missing joints on skeleton \(skeletonPath.rawValue)")
        }
        let skelJoints: VtTokenArray = jointsValue.Get()

        let animJointsAttr = animPrim.GetAttribute(TfToken("joints"))
        var animJointsValue = VtValue()
        guard animJointsAttr.IsValid(), animJointsAttr.Get(&animJointsValue, UsdTimeCode.Default()) else {
            throw SwiftUsdShellError.invalidValue("Missing joints on animation \(animationPath.rawValue)")
        }
        let animJoints: VtTokenArray = animJointsValue.Get()

        if skelJoints.size() == animJoints.size() {
            animJointsAttr.Set(VtValue(skelJoints), UsdTimeCode.Default())
        } else {
            var newJoints: [TfToken] = []
            for i in 0..<animJoints.size() {
                let aj = animJoints[i]
                let ajStr = stableOwnedString(describing: aj.GetString())
                var matched: TfToken?
                for j in 0..<skelJoints.size() {
                    let sj = skelJoints[j]
                    let sjStr = stableOwnedString(describing: sj.GetString())
                    if sjStr.hasSuffix(ajStr) || ajStr.hasSuffix(sjStr) {
                        matched = sj
                        break
                    }
                }
                newJoints.append(matched ?? aj)
            }
            if newJoints.count == animJoints.size() {
                animJointsAttr.Set(VtValue(VtTokenArray(newJoints)), UsdTimeCode.Default())
            }
        }

        // Empty file-format arguments: let OpenUSD pick defaults from
        // the layer's own file-format.
        var args = pxr.SdfLayer.FileFormatArguments()
        USDOverlay.Dereference(stagePtr).Export(
            std.string(output.url.path), true, args
        )
        return output
    }

    public func makeRCPReady(stage: USDStageURL, primPath: USDPath) throws -> USDStageURL {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }

        let prim = USDOverlay.Dereference(stagePtr).GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
        guard prim.IsValid() else {
            throw SwiftUsdShellError.primNotFound(stageURL: stage, primPath: primPath)
        }

        let xform = UsdGeomXformCommonAPI(prim)
        var translation = GfVec3d(0, 0, 0)
        var rotation = GfVec3f(0, 0, 0)
        var scale = GfVec3f(1, 1, 1)
        var pivot = GfVec3f(0, 0, 0)
        var rotationOrder = UsdGeomXformCommonAPI.RotationOrder.RotationOrderXYZ

        _ = xform.GetXformVectors(
            &translation, &rotation, &scale, &pivot, &rotationOrder,
            UsdTimeCode.Default()
        )

        // Inject a 1.5-frame delta so Reality Composer Pro treats the prim
        // as animated.
        rotation[0] = rotation[0] + 0.001
        _ = xform.SetXformVectors(
            translation, rotation, scale, pivot, rotationOrder,
            UsdTimeCode(1.5)
        )

        USDOverlay.Dereference(stagePtr).Save()
        return stage
    }



    public func observeStageChanges(
        stage: USDStageURL
    ) -> AsyncStream<USDStageInspectionEvent> {
        AsyncStream { continuation in
            let url = stage.url
            let initialModificationDate = fileModificationDate(url)

            let task = Task { @Sendable in
                var lastMod = initialModificationDate
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    let current = fileModificationDate(url)
                    if current != lastMod {
                        lastMod = current
                        continuation.yield(
                            USDStageInspectionEvent(
                                kind: .stageContentsChanged,
                                observedAt: current ?? Date(),
                                samplePaths: [url.path]
                            )
                        )
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func sceneStatistics(stage: USDStageURL) throws -> USDGeometryStatistics {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        return geometryStatistics(USDOverlay.Dereference(stagePtr).GetPseudoRoot())
    }

    public func primStatistics(
        stage: USDStageURL, primPath: USDPath
    ) throws -> USDGeometryStatistics? {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        let prim = USDOverlay.Dereference(stagePtr).GetPrimAtPath(
            SdfPath(std.string(primPath.rawValue))
        )
        guard prim.IsValid() else { return nil }
        let typeName = stableOwnedString(describing: prim.GetTypeName().GetString())
        guard typeName == "Mesh" else { return nil }
        return geometryStatistics(prim)
    }

    /// Returns stage-level metadata: animation tracks, time codes, up-axis,
    /// meters-per-unit, and default-prim information.
    public func stageMetadata(stageURL: USDStageURL) throws -> USDStageMetadata {
        let stage = try self.stage(for: stageURL, loadPolicy: .loadAll)
        return stageMetadata(stage)
    }

    /// Returns a high-level model summary combining stage metadata, scene bounds,
    /// and geometry statistics into a single struct.
    public func modelInfo(stage: USDStageURL) throws -> USDModelInfo {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        let stage = USDOverlay.Dereference(stagePtr)
        let metadata = stageMetadata(stage)
        let bounds = sceneBounds(stage)
        let stats = geometryStatistics(stage.GetPseudoRoot())
        let animTrackNames = metadata.animationTracks.map(\.rawValue)
        let metersPerUnit = metadata.metersPerUnit ?? 1.0

        let extent: SIMD3<Float> = bounds.map { $0.max - $0.min } ?? .zero

        let defaultPrim: String = {
            let rootLayer = USDOverlay.Dereference(stage.GetRootLayer())
            if rootLayer.HasDefaultPrim() {
                let dp = rootLayer.GetDefaultPrim()
                let dpStr = stableOwnedString(describing: dp.GetString())
                return dpStr.isEmpty ? "" : dpStr
            }
            return ""
        }()

        return USDModelInfo(
            boundsExtent: extent,
            boundsCenter: bounds?.center ?? .zero,
            scale: .one,
            upAxis: metadata.upAxis?.rawValue ?? "Y",
            animationCount: metadata.animationTracks.count,
            animationNames: animTrackNames,
            metersPerUnit: metersPerUnit > 0 ? metersPerUnit : 1.0,
            autoPlay: nil,
            playbackMode: nil,
            animatableStatus: !metadata.animationTracks.isEmpty ? .animatable : .unknown,
            hasAnimationLibrary: !metadata.animationTracks.isEmpty,
            skeletonJointCount: 0,
            maxJointInfluences: 0,
            hasSkinnedMesh: stats.meshCount > 0,
            blendShapes: [],
            defaultPrim: defaultPrim
        )
    }

    public func variantDescriptors(
        stage: USDStageURL, primPath: USDPath
    ) throws -> [USDVariantSetSummary] {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        let prim = USDOverlay.Dereference(stagePtr).GetPrimAtPath(
            SdfPath(std.string(primPath.rawValue))
        )
        guard prim.IsValid() else { return [] }
        return variantSets(prim)
    }

    public func exportVariantCombination(
        stage: USDStageURL,
        selections: [String: USDToken],
        output: USDStageURL
    ) throws -> USDStageURL {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        let usdStage = USDOverlay.Dereference(stagePtr)
        let defaultPrimPath = usdStage.GetDefaultPrim().GetPath()
        if !defaultPrimPath.IsEmpty() {
            let prim = usdStage.GetPrimAtPath(defaultPrimPath)
            if prim.IsValid() {
                let sets = prim.GetVariantSets()
                for (setName, selectionToken) in selections {
                    var variantSet = sets.GetVariantSet(std.string(setName))
                    if variantSet.HasAuthoredVariantSelection() {
                        variantSet.SetVariantSelection(std.string(selectionToken.rawValue))
                    }
                }
            }
        }
        var exportArgs = pxr.SdfLayer.FileFormatArguments()
        usdStage.Export(std.string(output.url.path), true, exportArgs)
        return output
    }

    public func materialSummaries(stage: USDStageURL) throws -> [USDMaterialSummary] {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        return materialSummaries(USDOverlay.Dereference(stagePtr).GetPseudoRoot())
    }




    public func primHierarchy(stage: USDStageURL) throws -> USDPrimTree? {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        let pseudoRoot = USDOverlay.Dereference(stagePtr).GetPseudoRoot()
        for child in pseudoRoot.GetChildren().swiftSequence {
            return primTree(child)
        }
        return nil
    }

    public func primSummary(
        stage: USDStageURL, primPath: USDPath
    ) throws -> USDPrimSummary {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        let prim = USDOverlay.Dereference(stagePtr).GetPrimAtPath(
            SdfPath(std.string(primPath.rawValue))
        )
        guard prim.IsValid() else {
            throw SwiftUsdShellError.primNotFound(stageURL: stage, primPath: primPath)
        }
        return primSummary(prim, includeAttributes: true, includeRelationships: false)
    }

    public func primTransformData(
        stage: USDStageURL, primPath: USDPath
    ) throws -> USDTransformData? {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        let prim = USDOverlay.Dereference(stagePtr).GetPrimAtPath(
            SdfPath(std.string(primPath.rawValue))
        )
        guard prim.IsValid() else { return nil }

        // Try robust per-op reading first (handles orient-authored and
        // split-Euler prims that XformCommonAPI can't decompose).
        var position = authoredVector3Op(prim: prim, prefix: "xformOp:translate")
        var rotationDegrees = resolveRotationDegrees(prim: prim)
        var scale = authoredVector3Op(prim: prim, prefix: "xformOp:scale")

        // Fall back to XformCommonAPI for any component we could not resolve.
        if position == nil || rotationDegrees == nil || scale == nil {
            let xform = UsdGeomXformCommonAPI(prim)
            var t = GfVec3d(0, 0, 0)
            var r = GfVec3f(0, 0, 0)
            var s = GfVec3f(1, 1, 1)
            var p = GfVec3f(0, 0, 0)
            var ro = UsdGeomXformCommonAPI.RotationOrder.RotationOrderXYZ
            if xform.GetXformVectors(&t, &r, &s, &p, &ro, UsdTimeCode.Default()) {
                if position == nil {
                    position = SIMD3<Double>(t[0], t[1], t[2])
                }
                if rotationDegrees == nil {
                    rotationDegrees = SIMD3<Double>(Double(r[0]), Double(r[1]), Double(r[2]))
                }
                if scale == nil {
                    scale = SIMD3<Double>(Double(s[0]), Double(s[1]), Double(s[2]))
                }
            }
        }

        guard let pos = position, let rot = rotationDegrees, let scl = scale else {
            return nil
        }
        return USDTransformData(position: pos, rotationDegrees: rot, scale: scl)
    }

    // MARK: - Transform helpers

    private func resolveRotationDegrees(prim: UsdPrim) -> SIMD3<Double>? {
        // Prefer authored Euler hint metadata for stable inspector display.
        if let hint = rotationEulerHintDegrees(prim: prim) {
            return hint
        }
        if let rotateXYZ = authoredVector3Op(prim: prim, prefix: "xformOp:rotateXYZ") {
            return rotateXYZ
        }
        if let split = authoredSplitEulerDegrees(prim: prim) {
            return split
        }
        if let orient = authoredQuaternionOp(prim: prim, prefix: "xformOp:orient") {
            return quaternionToEulerDegrees(orient)
        }
        return nil
    }

    private func authoredVector3Op(prim: UsdPrim, prefix: String) -> SIMD3<Double>? {
        // Canonical OpenUSD: read typed authored vector via attribute typeName
        // dispatch. We deliberately do not fall back to debug-string parsing —
        // unsupported xformOp value types must surface as nil so callers route
        // through the next strategy in `resolveRotationDegrees`.
        let exact = prim.GetAttribute(TfToken(prefix))
        if exact.IsValid(), let triple = xformVector3Value(exact) {
            return triple
        }
        for attr in prim.GetAttributes() {
            let name = String(attr.GetName())
            guard name.hasPrefix(prefix) else { continue }
            if let triple = xformVector3Value(attr) {
                return triple
            }
        }
        return nil
    }

    private func authoredQuaternionOp(prim: UsdPrim, prefix: String) -> simd_quatd? {
        let exact = prim.GetAttribute(TfToken(prefix))
        if exact.IsValid(), let quat = typedQuaternionValue(exact) {
            return quat
        }
        for attr in prim.GetAttributes() {
            let name = String(attr.GetName())
            guard name.hasPrefix(prefix) else { continue }
            if let quat = typedQuaternionValue(attr) {
                return quat
            }
        }
        return nil
    }

    private func typedQuaternionValue(_ attr: UsdAttribute) -> simd_quatd? {
        let typeName = attr.GetTypeName()
        if typeName == SdfValueTypeName.Quatd {
            var value = GfQuatd()
            guard attr.Get(&value, UsdTimeCode.Default()) else { return nil }
            let imag = value.GetImaginary()
            return simd_quatd(
                ix: Double(imag[0]),
                iy: Double(imag[1]),
                iz: Double(imag[2]),
                r: Double(value.GetReal())
            )
        }
        if typeName == SdfValueTypeName.Quatf {
            var value = GfQuatf()
            guard attr.Get(&value, UsdTimeCode.Default()) else { return nil }
            let imag = value.GetImaginary()
            return simd_quatd(
                ix: Double(imag[0]),
                iy: Double(imag[1]),
                iz: Double(imag[2]),
                r: Double(value.GetReal())
            )
        }
        if typeName == SdfValueTypeName.Quath {
            var value = GfQuath()
            guard attr.Get(&value, UsdTimeCode.Default()) else { return nil }
            let imag = value.GetImaginary()
            return simd_quatd(
                ix: Double(Float(imag[0])),
                iy: Double(Float(imag[1])),
                iz: Double(Float(imag[2])),
                r: Double(Float(value.GetReal()))
            )
        }
        return nil
    }

    private func authoredSplitEulerDegrees(prim: UsdPrim) -> SIMD3<Double>? {
        let rx = prim.GetAttribute(TfToken("xformOp:rotateX"))
        let ry = prim.GetAttribute(TfToken("xformOp:rotateY"))
        let rz = prim.GetAttribute(TfToken("xformOp:rotateZ"))
        guard rx.IsValid() || ry.IsValid() || rz.IsValid() else { return nil }
        // Canonical OpenUSD: read each authored Euler scalar via typed
        // attribute Get. Unsupported precisions yield 0 for that axis (matches
        // prior behavior of leaving the component at its initialized zero).
        let x = rx.IsValid() ? (xformScalarValue(rx) ?? 0.0) : 0.0
        let y = ry.IsValid() ? (xformScalarValue(ry) ?? 0.0) : 0.0
        let z = rz.IsValid() ? (xformScalarValue(rz) ?? 0.0) : 0.0
        return SIMD3<Double>(x, y, z)
    }

    private func rotationEulerHintDegrees(prim: UsdPrim) -> SIMD3<Double>? {
        // Canonical OpenUSD: typed dict-key read on customData. The writer in
        // `setCommonTransform` stores `rotationEulerHint` as a GfVec3f in
        // radians; reads dispatch through `VtValue` typed `Get` for the
        // expected precisions.
        var hintValue = VtValue()
        guard prim.GetMetadataByDictKey(
            TfToken("customData"),
            TfToken("rotationEulerHint"),
            &hintValue
        ) else { return nil }
        let radToDeg = 180.0 / Double.pi
        if hintValue.IsHolding(GfVec3f.self) {
            let v = hintValue.Get() as GfVec3f
            return SIMD3<Double>(
                Double(v[0]) * radToDeg,
                Double(v[1]) * radToDeg,
                Double(v[2]) * radToDeg
            )
        }
        if hintValue.IsHolding(GfVec3d.self) {
            let v = hintValue.Get() as GfVec3d
            return SIMD3<Double>(v[0] * radToDeg, v[1] * radToDeg, v[2] * radToDeg)
        }
        if hintValue.IsHolding(GfVec3h.self) {
            let v = hintValue.Get() as GfVec3h
            return SIMD3<Double>(
                Double(Float(v[0])) * radToDeg,
                Double(Float(v[1])) * radToDeg,
                Double(Float(v[2])) * radToDeg
            )
        }
        return nil
    }

    public func primMaterialBinding(
        stage: USDStageURL, primPath: USDPath
    ) throws -> USDMaterialBindingInfo? {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        let prim = USDOverlay.Dereference(stagePtr).GetPrimAtPath(
            SdfPath(std.string(primPath.rawValue))
        )
        guard prim.IsValid() else { return nil }
        return materialBindingInfo(for: prim, selectedPath: primPath)
    }




    public func normalizeAssetPath(_ reference: String) -> String {
        reference.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    public func validateStage(
        stageURL: USDStageURL,
        keywords: [String]
    ) throws -> [USDValidationIssue] {
        #if canImport(SwiftUsd_PXR_ENABLE_USD_VALIDATION_SUPPORT)
        let stagePtr = UsdStage.Open(std.string(stageURL.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stageURL, diagnostic: nil)
        }
        let issues = try USDOverlay.UsdValidationWrapper.validateStage(
            stagePtr,
            keywords: keywords
        )
        return issues.map { issue in
            USDValidationIssue(
                name: issue.name,
                identifier: issue.identifier,
                severity: USDValidationSeverity(rawValue: issue.severity.rawValue) ?? .none,
                message: issue.message,
                validatorName: stableOwnedString(describing: issue.validatorName),
                sites: issue.sites.map {
                    USDValidationSite(kind: stableOwnedString(describing: $0.kind), objectPath: stableOwnedString(describing: $0.objectPath), layerIdentifier: stableOwnedString(describing: $0.layerIdentifier))
                }
            )
        }
        #else
        return []
        #endif
    }

    // MARK: - Reference operations

    private func openAndGetPrim(stage: USDStageURL, primPath: USDPath) throws -> UsdPrim {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        let prim = USDOverlay.Dereference(stagePtr).GetPrimAtPath(
            SdfPath(std.string(primPath.rawValue))
        )
        guard prim.IsValid() else {
            throw SwiftUsdShellError.primNotFound(stageURL: stage, primPath: primPath)
        }
        return prim
    }

    public func primReferences(
        stage: USDStageURL, primPath: USDPath
    ) throws -> [USDReference] {
        let prim = try openAndGetPrim(stage: stage, primPath: primPath)
        guard prim.HasAuthoredReferences() else { return [] }
        return typedAuthoredReferences(on: prim).map { typed in
            USDReference(assetPath: typed.assetPath, primPath: typed.primPath)
        }
    }

    /// Typed authored reference, preserving the authoring `SdfPrimSpec` and
    /// the original `SdfReference` so we can re-issue exact list-op edits.
    private struct AuthoredReference {
        let assetPath: String
        let primPath: String?
        let layerOffsetStart: Double
        let layerOffsetScale: Double
        /// Original `SdfReference` value, retained for typed list-op deletion.
        let sdfReference: SdfReference
    }

    /// Walks `UsdPrim.GetPrimStack()` and reads each authoring `SdfPrimSpec`'s
    /// reference list-op via `SdfPrimSpec.GetReferenceList()`. Preserves
    /// authoring-layer ownership, list-op ordering, prim path targets, and
    /// layer offsets without parsing stringified `VtValue` debug dumps.
    private func typedAuthoredReferences(on prim: UsdPrim) -> [AuthoredReference] {
        var items: [AuthoredReference] = []
        var seen = Set<String>()
        for specHandle in prim.GetPrimStack() {
            let primSpec = specHandle.pointee
            let refList = primSpec.GetReferenceList()
            // Prefer added-or-explicit so we cover both the modern prepend/append
            // case and explicit-list authoring without re-emitting deletions.
            let sdfRefs = refList.GetAddedOrExplicitItems()
            for index in 0..<sdfRefs.size() {
                let sdfRef = sdfRefs[index]
                let assetPath = stableOwnedString(describing: sdfRef.GetAssetPath())
                let primPathStr = stableOwnedString(describing: sdfRef.GetPrimPath().GetAsString())
                let normalizedPrimPath: String? = primPathStr.isEmpty ? nil : primPathStr
                let offset = sdfRef.GetLayerOffset()
                let key = "\(assetPath)|\(normalizedPrimPath ?? "")"
                guard seen.insert(key).inserted else { continue }
                items.append(AuthoredReference(
                    assetPath: assetPath,
                    primPath: normalizedPrimPath,
                    layerOffsetStart: offset.GetOffset(),
                    layerOffsetScale: offset.GetScale(),
                    sdfReference: sdfRef
                ))
            }
        }
        return items
    }

    public func addReference(
        stage: USDStageURL, primPath: USDPath, reference: USDReference
    ) throws {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        let deref = USDOverlay.Dereference(stagePtr)
        let prim = deref.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
        guard prim.IsValid() else {
            throw SwiftUsdShellError.primNotFound(stageURL: stage, primPath: primPath)
        }

        let ok = USDOverlay.withUsdEditContext(deref, deref.GetEditTarget()) {
            var refs = prim.GetReferences()
            let sdfPath = if let pp = reference.primPath, !pp.isEmpty {
                SdfPath(std.string(pp))
            } else { SdfPath() }
            let sdfRef = SdfReference(
                std.string(reference.assetPath),
                sdfPath,
                SdfLayerOffset(0.0, 1.0),
                VtDictionary()
            )
            return refs.AddReference(sdfRef, pxr.UsdListPosition.UsdListPositionBackOfPrependList)
        }
        guard ok else {
            throw SwiftUsdShellError.referenceEditFailed(
                operation: "add", stageURL: stage, primPath: primPath,
                assetPath: reference.assetPath, targetPrimPath: reference.primPath
            )
        }
        USDOverlay.Dereference(deref.GetRootLayer()).Save(false)
    }

    public func removeReference(
        stage: USDStageURL, primPath: USDPath, reference: USDReference
    ) throws {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        let deref = USDOverlay.Dereference(stagePtr)
        let prim = deref.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
        guard prim.IsValid() else {
            throw SwiftUsdShellError.primNotFound(stageURL: stage, primPath: primPath)
        }

        // Locate the exact authored `SdfReference` via the typed prim stack so
        // we can pass it back through `UsdReferences.RemoveReference` and let
        // OpenUSD perform the typed list-op deletion. This preserves the
        // list-op (prepend/append/explicit) and the other authored entries —
        // we never rebuild the list, so layer offsets and ordering on
        // surviving references are untouched.
        let authored = typedAuthoredReferences(on: prim)
        let matches = authored.filter { item in
            item.assetPath == reference.assetPath
                && (item.primPath ?? "") == (reference.primPath ?? "")
        }
        let ok = USDOverlay.withUsdEditContext(deref, deref.GetEditTarget()) {
            var refs = prim.GetReferences()
            if matches.isEmpty {
                // Nothing authored matches; surface no-op as failure so callers
                // can distinguish from a successful canonical deletion.
                return false
            }
            var allOk = true
            for match in matches {
                if !refs.RemoveReference(match.sdfReference) {
                    allOk = false
                }
            }
            return allOk
        }
        guard ok else {
            throw SwiftUsdShellError.referenceEditFailed(
                operation: "remove", stageURL: stage, primPath: primPath,
                assetPath: reference.assetPath, targetPrimPath: reference.primPath
            )
        }
        USDOverlay.Dereference(deref.GetRootLayer()).Save(false)
    }

    // MARK: - Session layer / packaging

    public func writeSessionLayer(
        to outputURL: USDStageURL,
        stageMetadata: [String: String],
        subLayers: [String],
        docComment: String,
        footerComment: String?
    ) throws {
        var lines: [String] = []
        lines.append("#usda 1.0")
        lines.append("(")
        if !docComment.isEmpty {
            lines.append("    doc = \"\"\"\(docComment)\"\"\"")
        }
        for (key, value) in stageMetadata.sorted(by: { $0.key < $1.key }) {
            if let doubleValue = Double(value) {
                lines.append("    \(key) = \(doubleValue)")
            } else {
                lines.append("    \(key) = \"\(value)\"")
            }
        }
        if !subLayers.isEmpty {
            lines.append("    subLayers = [")
            for subLayer in subLayers {
                lines.append("        @\(subLayer)@,")
            }
            lines.append("    ]")
        }
        if let footer = footerComment, !footer.isEmpty {
            lines.append("    // \(footer)")
        }
        lines.append(")")
        lines.append("")
        let content = lines.joined(separator: "\n")
        try content.write(to: outputURL.url, atomically: true, encoding: .utf8)
    }

    public func exportFlattenedLayer(
        sessionLayerURL: USDStageURL,
        outputURL: USDStageURL,
        isUsdz: Bool
    ) throws {
        let stagePtr = UsdStage.Open(std.string(sessionLayerURL.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(sessionLayerURL, diagnostic: nil)
        }
        let stage = USDOverlay.Dereference(stagePtr)
        let flattenedLayerPtr = stage.Flatten(true)
        guard flattenedLayerPtr._isNonnull() else {
            throw SwiftUsdShellError.invalidValue("Flatten failed for \(sessionLayerURL.url.lastPathComponent)")
        }
        let flattened = USDOverlay.Dereference(flattenedLayerPtr)

        if isUsdz {
            let tempDir = FileManager.default.temporaryDirectory
            let tempUsda = tempDir.appendingPathComponent(UUID().uuidString + ".usda")
            guard flattened.Export(std.string(tempUsda.path), std.string(), SdfLayer.FileFormatArguments()) else {
                throw SwiftUsdShellError.invalidValue("Export failed for \(tempUsda.lastPathComponent)")
            }
            // USDZ packaging requires UsdUtils.CreateNewUsdzPackage which is
            // not yet exposed through the Shell adapter. Defer to the
            // platform-specific backend.
            throw SwiftUsdShellError.unsupportedSchema("USDZ packaging requires platform backend; export flattened USDC/USDA instead")
        } else {
            guard flattened.Export(std.string(outputURL.url.path), std.string(), SdfLayer.FileFormatArguments()) else {
                throw SwiftUsdShellError.invalidValue("Export failed for \(outputURL.url.lastPathComponent)")
            }
        }
    }

    public func createVerbatimUSDZPackage(
        currentDirectory: USDStageURL,
        inputs: [String],
        outputURL: USDStageURL
    ) throws {
        let fileManager = FileManager.default
        var writer = SdfZipFileWriter.CreateNew(std.string(outputURL.url.path))

        for input in inputs {
            let sourceURL = currentDirectory.url.appendingPathComponent(input)
            try addPathToUSDZPackage(
                sourceURL: sourceURL,
                archivePath: input,
                outputURL: outputURL,
                writer: &writer,
                fileManager: fileManager
            )
        }

        guard writer.Save() else {
            throw SwiftUsdShellError.invalidValue("Failed to write USDZ archive at \(outputURL.url.lastPathComponent)")
        }
    }

    private func addPathToUSDZPackage(
        sourceURL: URL,
        archivePath: String,
        outputURL: USDStageURL,
        writer: inout SdfZipFileWriter,
        fileManager: FileManager
    ) throws {
        let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])

        if values.isDirectory == true {
            let childURLs = try fileManager.contentsOfDirectory(
                at: sourceURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: []
            ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            for childURL in childURLs {
                let childArchivePath = archivePath + "/" + childURL.lastPathComponent
                try addPathToUSDZPackage(
                    sourceURL: childURL,
                    archivePath: childArchivePath,
                    outputURL: outputURL,
                    writer: &writer,
                    fileManager: fileManager
                )
            }
            return
        }

        guard values.isRegularFile == true else {
            throw SwiftUsdShellError.invalidValue("Unsupported package item at \(sourceURL.lastPathComponent)")
        }

        let archivedPath = String(
            writer.AddFile(
                std.string(sourceURL.path),
                std.string(archivePath)
            )
        )
        guard !archivedPath.isEmpty else {
            throw SwiftUsdShellError.invalidValue("Failed to add \(archivePath) to USDZ archive")
        }
    }

    // MARK: - Import / arbitrary-source flatten

    public func flattenAndExport(
        sourceURL: USDStageURL,
        outputURL: USDStageURL,
        assetsDirectoryURL: USDStageURL?
    ) throws {
        let stagePath: std.string
        if let assetsDir = assetsDirectoryURL {
            stagePath = std.string("\(sourceURL.url.path):SDF_FORMAT_ARGS:assetsPath=\(assetsDir.url.path)")
        } else {
            stagePath = std.string(sourceURL.url.path)
        }

        var stagePtr = UsdStage.Open(stagePath, UsdStage.InitialLoadSet.LoadAll)
        if stagePtr._isNonnull() == false, assetsDirectoryURL != nil {
            // Fallback: try opening without the assetsPath argument.
            stagePtr = UsdStage.Open(std.string(sourceURL.url.path), UsdStage.InitialLoadSet.LoadAll)
        }
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(sourceURL, diagnostic: "Unable to open source for flatten/export")
        }
        let stage = USDOverlay.Dereference(stagePtr)

        let flattenedLayerPtr = stage.Flatten(true)
        guard flattenedLayerPtr._isNonnull() else {
            throw SwiftUsdShellError.invalidValue("Flatten failed for \(sourceURL.url.lastPathComponent)")
        }
        let flattened = USDOverlay.Dereference(flattenedLayerPtr)

        guard flattened.Export(std.string(outputURL.url.path), std.string(), SdfLayer.FileFormatArguments()) else {
            throw SwiftUsdShellError.invalidValue("Export failed for \(outputURL.url.lastPathComponent)")
        }
    }

    // MARK: - Texture extraction

    public func extractPackagedTextures(
        packageURL: USDStageURL,
        outputDirectory: URL,
        refresh: Bool
    ) throws -> Int {
        let fileManager = FileManager.default
        if refresh, fileManager.fileExists(atPath: outputDirectory.path) {
            try fileManager.removeItem(at: outputDirectory)
        }
        guard packageURL.url.pathExtension.lowercased() == "usdz" else {
            return 0
        }

        let zipFile = SdfZipFile.Open(std.string(packageURL.url.path))
        guard Bool(zipFile) else {
            throw SwiftUsdShellError.invalidValue("Failed to open USDZ: \(packageURL.url.lastPathComponent)")
        }

        let imageExtensions = Set(["jpg", "jpeg", "png", "exr", "hdr", "tif", "tiff", "bmp"])
        var writtenCount = 0

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for entry in zipFile.swiftSequence {
            let filename = String(entry.pointee)
            let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }

            // Reject entries with path traversal to keep output within outputDirectory.
            guard let relativePath = normalizedPackagedTexturePath(filename) else { continue }

            let fileInfo = entry.GetFileInfo()
            guard fileInfo.compressionMethod == 0, let dataPtr = entry.GetFile() else { continue }

            let data = Data(bytes: dataPtr, count: Int(fileInfo.size))
            let outputURL = outputDirectory.appendingPathComponent(relativePath).standardizedFileURL
            // Verify the resolved URL is still within the output directory.
            guard outputURL.path.hasPrefix(outputDirectory.path + "/") || outputURL.path == outputDirectory.path else { continue }
            try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: outputURL, options: Data.WritingOptions.atomic)
            writtenCount += 1
        }
        return writtenCount
    }
    public func rootPrimPaths(stage: USDStageURL) throws -> [USDPath] {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadNone)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        let pseudoRoot = USDOverlay.Dereference(stagePtr).GetPseudoRoot()
        var paths: [USDPath] = []
        for child in pseudoRoot.GetChildren().swiftSequence {
            guard child.IsValid() else { continue }
            let pathStr = String(child.GetPath().GetAsString())
            guard !pathStr.isEmpty else { continue }
            paths.append(USDPath(pathStr))
        }
        return paths
    }

    public func unresolvedDependencies(stage: USDStageURL) throws -> [String] {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        let pxrStage = USDOverlay.Dereference(stagePtr)
        let fileManager = FileManager.default
        var unresolved: [String] = []
        var seen = Set<String>()
        let dir = stage.url.deletingLastPathComponent()
        for prim in pxrStage.Traverse().swiftSequence {
            guard prim.IsValid(), prim.HasAuthoredReferences() else { continue }
            for ref in typedAuthoredReferences(on: prim) {
                let key = ref.assetPath
                guard seen.insert(key).inserted else { continue }
                guard !ref.assetPath.isEmpty else { continue }
                let resolved = dir.appendingPathComponent(ref.assetPath)
                if !fileManager.fileExists(atPath: resolved.path) {
                    unresolved.append(ref.assetPath)
                }
            }
        }
        return unresolved
    }

}

/// Sanitize a USDZ archive member path: reject traversal (`..`)
/// and strip leading slashes / current-directory components.
private func normalizedPackagedTexturePath(_ archiveMemberPath: String) -> String? {
    let rawComponents = archiveMemberPath
        .replacingOccurrences(of: "\\", with: "/")
        .split(separator: "/")
    var sanitized: [String] = []
    for component in rawComponents {
        let value = String(component)
        if value.isEmpty || value == "." { continue }
        guard value != ".." else { return nil }
        sanitized.append(value)
    }
    guard !sanitized.isEmpty else { return nil }
    return sanitized.joined(separator: "/")
}

private func fileModificationDate(_ url: URL) -> Date? {
    try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
}

/// Groups authored `Sdf` edits so notices and invalidations are emitted
/// coherently after the block completes.
@inline(__always)
private func withSdfChangeBlock<T>(_ body: () throws -> T) rethrows -> T {
    let block = SdfChangeBlock()
    defer { _ = block }
    return try body()
}

private extension OpenUSDStageRuntime {
    func stage(for stageURL: USDStageURL, loadPolicy: USDLoadPolicy) throws -> UsdStage {
        let stageRef = UsdStage.Open(std.string(stageURL.url.path), openUSDLoadPolicy(loadPolicy))
        guard stageRef._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stageURL, diagnostic: nil)
        }
        return USDOverlay.Dereference(stageRef)
    }

    func stageMetadata(_ stage: UsdStage) -> USDStageMetadata {
        let defaultPrim = stage.GetDefaultPrim()
        let animationTracks = stageAnimationTracks(stage)
        let availableCameras = stageCameras(stage)
        let authoredStartTimeCode = stage.GetStartTimeCode()
        let authoredEndTimeCode = stage.GetEndTimeCode()
        let sampledTimeRange = authoredEndTimeCode > authoredStartTimeCode || animationTracks.isEmpty
            ? nil
            : stageTimeSampleRange(stage)

        return USDStageMetadata(
            upAxis: tokenOrNil(pxr.UsdGeomGetStageUpAxis(USDOverlay.TfWeakPtr(stage))),
            metersPerUnit: pxr.UsdGeomGetStageMetersPerUnit(USDOverlay.TfWeakPtr(stage)),
            defaultPrimName: defaultPrim.IsValid()
                ? USDToken(stableOwnedString(describing: defaultPrim.GetName().GetString()))
                : nil,
            timeCodesPerSecond: stage.GetTimeCodesPerSecond(),
            startTimeCode: sampledTimeRange?.start ?? authoredStartTimeCode,
            endTimeCode: sampledTimeRange?.end ?? authoredEndTimeCode,
            animationTracks: animationTracks,
            availableCameras: availableCameras
        )
    }

    func stageTimeSampleRange(_ stage: UsdStage) -> (start: Double, end: Double)? {
        var start: Double?
        var end: Double?

        for prim in stage.Traverse().swiftSequence {
            for attribute in prim.GetAttributes() {
                guard attribute.GetNumTimeSamples() > 0 else { continue }

                guard let attributeRange = attributeTimeSampleRange(attribute) else { continue }
                start = start.map { Swift.min($0, attributeRange.start) } ?? attributeRange.start
                end = end.map { Swift.max($0, attributeRange.end) } ?? attributeRange.end
            }
        }

        guard let start, let end, end > start else { return nil }
        return (start, end)
    }

    func attributeTimeSampleRange(_ attribute: UsdAttribute) -> (start: Double, end: Double)? {
        var lower = 0.0
        var upper = 0.0
        var hasTimeSamples = false
        guard attribute.GetBracketingTimeSamples(
            -Double.greatestFiniteMagnitude,
            &lower,
            &upper,
            &hasTimeSamples
        ), hasTimeSamples else { return nil }
        let firstSample = Swift.min(lower, upper)

        lower = 0.0
        upper = 0.0
        hasTimeSamples = false
        guard attribute.GetBracketingTimeSamples(
            Double.greatestFiniteMagnitude,
            &lower,
            &upper,
            &hasTimeSamples
        ), hasTimeSamples else { return nil }
        let lastSample = Swift.max(lower, upper)

        guard lastSample > firstSample else { return nil }
        return (firstSample, lastSample)
    }

    func stageAnimationTracks(_ stage: UsdStage) -> [USDPath] {
        var tracks: [USDPath] = []
        for prim in stage.Traverse().swiftSequence {
            let typeName = stableOwnedString(describing: prim.GetTypeName().GetString()).lowercased()
            guard typeName == "skelanimation"
                || typeName == "animation"
                || typeName == "realitykittimeline"
            else { continue }
            tracks.append(USDPath(stableOwnedString(describing: prim.GetPath().GetAsString())))
        }
        return tracks
    }

    func stageCameras(_ stage: UsdStage) -> [USDPath] {
        var cameras: [USDPath] = []
        for prim in stage.Traverse().swiftSequence {
            guard stableOwnedString(describing: prim.GetTypeName().GetString()) == "Camera" else { continue }
            cameras.append(USDPath(stableOwnedString(describing: prim.GetPath().GetAsString())))
        }
        return cameras
    }

    func primTree(_ prim: UsdPrim) -> USDPrimTree {
        USDPrimTree(
            path: USDPath(stableOwnedString(describing: prim.GetPath().GetAsString())),
            name: USDToken(stableOwnedString(describing: prim.GetName().GetString())),
            typeName: tokenOrNil(prim.GetTypeName()),
            specifier: primSpecifier(prim.GetSpecifier()),
            isActive: prim.IsActive(),
            isInstanceable: prim.IsInstanceable(),
            purpose: purpose(prim),
            children: prim.GetChildren().swiftSequence.map { primTree($0) }
        )
    }

    func geometryStatistics(_ root: UsdPrim) -> USDGeometryStatistics {
        var totalTriangles = 0
        var totalVertices = 0
        var meshCount = 0
        var materialCount = 0
        var textureCount = 0

        func visit(_ prim: UsdPrim) {
            switch stableOwnedString(describing: prim.GetTypeName().GetString()) {
            case "Mesh":
                meshCount += 1
                let meshCounts = meshGeometryCounts(prim)
                totalTriangles += meshCounts.triangles
                totalVertices += meshCounts.vertices

            case "Material":
                materialCount += 1

            case "Shader":
                if shaderIdentifier(prim)?.contains("UsdUVTexture") == true {
                    textureCount += 1
                }

            default:
                break
            }

            for child in prim.GetChildren().swiftSequence {
                visit(child)
            }
        }

        visit(root)

        return USDGeometryStatistics(
            totalTriangles: totalTriangles,
            totalVertices: totalVertices,
            meshCount: meshCount,
            materialCount: materialCount,
            textureCount: textureCount
        )
    }

    func sceneBounds(_ stage: UsdStage) -> USDSceneBounds? {
        let defaultPrim = stage.GetDefaultPrim()
        if defaultPrim.IsValid(), let bounds = sceneBounds(defaultPrim, timeCode: .default) {
            return bounds
        }
        return combinedChildBounds(stage.GetPseudoRoot(), timeCode: .default)
    }

    func sceneBounds(_ prim: UsdPrim, timeCode: USDTimeCode) -> USDSceneBounds? {
        let imageable = UsdGeomImageable(prim)
        if USDOverlay.GetPrim(imageable).IsValid(),
           let bounds = sceneBounds(imageable, timeCode: timeCode) {
            return bounds
        }
        return combinedChildBounds(prim, timeCode: timeCode)
    }

    func sceneBounds(_ imageable: UsdGeomImageable, timeCode: USDTimeCode) -> USDSceneBounds? {
        let box = imageable.ComputeWorldBound(
            openUSDTimeCode(timeCode),
            TfToken(std.string("default")),
            TfToken(std.string("render")),
            TfToken(),
            TfToken()
        )
        let range = box.GetRange()
        let min = range.GetMin()
        let max = range.GetMax()
        guard min[0] <= max[0], min[1] <= max[1], min[2] <= max[2] else {
            return nil
        }
        return sceneBounds(
            min: SIMD3<Float>(Float(min[0]), Float(min[1]), Float(min[2])),
            max: SIMD3<Float>(Float(max[0]), Float(max[1]), Float(max[2]))
        )
    }

    func combinedChildBounds(_ prim: UsdPrim, timeCode: USDTimeCode) -> USDSceneBounds? {
        var combined: USDSceneBounds?
        for child in prim.GetChildren().swiftSequence {
            guard let childBounds = sceneBounds(child, timeCode: timeCode) else {
                continue
            }
            combined = combined.map { union($0, childBounds) } ?? childBounds
        }
        return combined
    }

    func sceneBounds(min: SIMD3<Float>, max: SIMD3<Float>) -> USDSceneBounds {
        let center = (min + max) / 2
        let extent = max - min
        return USDSceneBounds(
            min: min,
            max: max,
            center: center,
            maxExtent: Swift.max(extent.x, Swift.max(extent.y, extent.z))
        )
    }

    func union(_ lhs: USDSceneBounds, _ rhs: USDSceneBounds) -> USDSceneBounds {
        sceneBounds(
            min: SIMD3<Float>(
                Swift.min(lhs.min.x, rhs.min.x),
                Swift.min(lhs.min.y, rhs.min.y),
                Swift.min(lhs.min.z, rhs.min.z)
            ),
            max: SIMD3<Float>(
                Swift.max(lhs.max.x, rhs.max.x),
                Swift.max(lhs.max.y, rhs.max.y),
                Swift.max(lhs.max.z, rhs.max.z)
            )
        )
    }

    func meshGeometryCounts(_ prim: UsdPrim) -> (triangles: Int, vertices: Int) {
        let mesh = UsdGeomMesh(prim)
        guard USDOverlay.GetPrim(mesh).IsValid() else {
            return (0, 0)
        }

        var vertexCount = 0
        var points = VtVec3fArray()
        let pointsAttr = mesh.GetPointsAttr()
        if pointsAttr.IsValid(), pointsAttr.Get(&points, UsdTimeCode.Default()) {
            vertexCount = Int(points.size())
        }

        var triangleCount = 0
        var faceVertexCounts = VtIntArray()
        let faceCountsAttr = mesh.GetFaceVertexCountsAttr()
        if faceCountsAttr.IsValid(), faceCountsAttr.Get(&faceVertexCounts, UsdTimeCode.Default()) {
            for index in 0..<faceVertexCounts.size() {
                let faceVertexCount = Int(faceVertexCounts[index])
                if faceVertexCount >= 3 {
                    triangleCount += faceVertexCount - 2
                }
            }
        }

        return (triangleCount, vertexCount)
    }

    func shaderIdentifier(_ prim: UsdPrim) -> String? {
        let idAttr = prim.GetAttribute(TfToken(std.string("info:id")))
        guard idAttr.IsValid() else { return nil }

        var token = TfToken()
        if idAttr.Get(&token, UsdTimeCode.Default()) {
            let value = stableOwnedString(describing: token.GetString())
            if !value.isEmpty {
                return value
            }
        }

        var stringValue = std.string()
        if idAttr.Get(&stringValue, UsdTimeCode.Default()) {
            let value = stableOwnedString(describing: stringValue)
            if !value.isEmpty {
                return value
            }
        }

        return nil
    }

    func primSummary(
        _ prim: UsdPrim,
        includeAttributes: Bool,
        includeRelationships: Bool
    ) -> USDPrimSummary {
        USDPrimSummary(
            path: USDPath(stableOwnedString(describing: prim.GetPath().GetAsString())),
            name: USDToken(stableOwnedString(describing: prim.GetName().GetString())),
            typeName: tokenOrNil(prim.GetTypeName()),
            specifier: primSpecifier(prim.GetSpecifier()),
            isDefined: prim.IsDefined(),
            isActive: prim.IsActive(),
            isAbstract: prim.IsAbstract(),
            isInstanceable: prim.IsInstanceable(),
            visibility: visibility(prim),
            purpose: purpose(prim),
            kind: modelKind(prim),
            attributes: includeAttributes ? attributes(prim) : [],
            relationships: includeRelationships ? relationships(prim) : []
        )
    }

    func attributes(_ prim: UsdPrim) -> [USDAttributeSummary] {
        prim.GetAttributes().map { attribute in
            USDAttributeSummary(
                name: USDToken(stableOwnedString(describing: attribute.GetName().GetString())),
                typeName: stableOwnedString(describing: attribute.GetTypeName().GetAsToken().GetString()),
                isAuthored: attribute.HasAuthoredValue(),
                hasValue: attribute.HasValue(),
                timeSampleCount: Int(attribute.GetNumTimeSamples())
            )
        }
    }

    func relationships(_ prim: UsdPrim) -> [USDRelationshipSummary] {
        prim.GetRelationships().map { relationship in
            var targets = SdfPathVector()
            _ = relationship.GetTargets(&targets)
            return USDRelationshipSummary(
                name: USDToken(stableOwnedString(describing: relationship.GetName().GetString())),
                targets: targets.map { USDPath(stableOwnedString(describing: $0.GetAsString())) }
            )
        }
    }

    func compositionArcs(_ prim: UsdPrim) -> [USDCompositionArcSummary] {
        var arcs: [USDCompositionArcSummary] = []
        for spec in prim.GetPrimStack() {
            let primSpec = spec.pointee
            arcs.append(contentsOf: primSpec.GetReferenceList().GetAddedOrExplicitItems().map {
                _ in USDCompositionArcSummary(kind: .reference)
            })
            arcs.append(contentsOf: primSpec.GetPayloadList().GetAddedOrExplicitItems().map {
                _ in USDCompositionArcSummary(kind: .payload)
            })
        }
        return arcs
    }

    func variantSets(_ prim: UsdPrim) -> [USDVariantSetSummary] {
        let sets = prim.GetVariantSets()
        return sets.GetNames().map { name in
            let nameString = stableOwnedString(describing: name)
            let variantSet = sets.GetVariantSet(std.string(nameString))
            let hasAuthored = variantSet.HasAuthoredVariantSelection()
            let selection = stableOwnedString(describing: variantSet.GetVariantSelection())
            return USDVariantSetSummary(
                name: USDToken(nameString),
                choices: variantSet.GetVariantNames().map {
                    USDToken(stableOwnedString(describing: $0))
                },
                selection: selection.isEmpty ? nil : USDToken(selection),
                hasAuthoredSelection: hasAuthored
            )
        }
    }

    func transformInspection(_ prim: UsdPrim, timeCode: USDTimeCode) -> USDTransformInspection? {
        let xform = UsdGeomXformCommonAPI(prim)
        var translation = GfVec3d(0, 0, 0)
        var rotation = GfVec3f(0, 0, 0)
        var scale = GfVec3f(1, 1, 1)
        var pivot = GfVec3f(0, 0, 0)
        var rotationOrder = UsdGeomXformCommonAPI.RotationOrder.RotationOrderXYZ

        guard xform.GetXformVectors(
            &translation,
            &rotation,
            &scale,
            &pivot,
            &rotationOrder,
            openUSDTimeCode(timeCode)
        ) else {
            return authoredTransformInspection(prim, localTransform: .init())
        }

        let localTransform = USDTransformData(
            position: SIMD3<Double>(translation[0], translation[1], translation[2]),
            rotationDegrees: SIMD3<Double>(Double(rotation[0]), Double(rotation[1]), Double(rotation[2])),
            scale: SIMD3<Double>(Double(scale[0]), Double(scale[1]), Double(scale[2]))
        )
        let authoredInspection = authoredTransformInspection(prim, localTransform: localTransform)

        return USDTransformInspection(
            localTransform: localTransform,
            authoredOps: authoredInspection.authoredOps,
            editCapability: authoredInspection.editCapability,
            restrictionReason: authoredInspection.restrictionReason,
            isAnimated: authoredInspection.isAnimated
        )
    }

    func authoredTransformInspection(
        _ prim: UsdPrim,
        localTransform: USDTransformData
    ) -> USDTransformInspection {
        let typeName = stableOwnedString(describing: prim.GetTypeName().GetString())
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let authoredOps = collectAuthoredOps(for: prim)
        let isAnimated = authoredOps.contains(where: \.isTimeSampled)

        if nonXformableTypeNames.contains(typeName) {
            return USDTransformInspection(
                localTransform: localTransform,
                authoredOps: authoredOps,
                editCapability: .notXformable,
                restrictionReason: .nonXformablePrim,
                isAnimated: isAnimated
            )
        }

        if isAnimated {
            return USDTransformInspection(
                localTransform: localTransform,
                authoredOps: authoredOps,
                editCapability: .readonlyAnimated,
                restrictionReason: .animatedTransformOp,
                isAnimated: true
            )
        }

        if authoredOps.contains(where: { $0.kind == .orient }) {
            return USDTransformInspection(
                localTransform: localTransform,
                authoredOps: authoredOps,
                editCapability: .readonlyOrient,
                restrictionReason: .orientTransformOp
            )
        }

        if authoredOps.contains(where: { $0.kind == .transform }) {
            return USDTransformInspection(
                localTransform: localTransform,
                authoredOps: authoredOps,
                editCapability: .readonlyMatrix,
                restrictionReason: .matrixTransformOp
            )
        }

        if authoredOps.contains(where: { if case .custom = $0.kind { true } else { false } }) {
            return USDTransformInspection(
                localTransform: localTransform,
                authoredOps: authoredOps,
                editCapability: .readonlyUnsupportedCustomStack,
                restrictionReason: .unsupportedOp
            )
        }

        let order = authoredOps.map(\.token)
        let hasRotateXYZ = authoredOps.contains(where: { $0.kind == .rotateXYZ })
        let scalarRotationKinds = Set(
            authoredOps.compactMap { op -> USDAuthoredXformOpKind? in
                switch op.kind {
                case .rotateX, .rotateY, .rotateZ:
                    op.kind
                default:
                    nil
                }
            }
        )

        if hasRotateXYZ && !scalarRotationKinds.isEmpty {
            return USDTransformInspection(
                localTransform: localTransform,
                authoredOps: authoredOps,
                editCapability: .readonlyUnsupportedCustomStack,
                restrictionReason: .customTransformStack
            )
        }

        if !scalarRotationKinds.isEmpty && scalarRotationKinds != Set([.rotateX, .rotateY, .rotateZ]) {
            return USDTransformInspection(
                localTransform: localTransform,
                authoredOps: authoredOps,
                editCapability: .readonlyUnsupportedCustomStack,
                restrictionReason: .partialEulerStack
            )
        }

        let pivotCount = order.filter(isPivotStartToken).count
        let inversePivotCount = order.filter(isInversePivotToken).count
        if pivotCount != inversePivotCount || pivotCount > 1 {
            return USDTransformInspection(
                localTransform: localTransform,
                authoredOps: authoredOps,
                editCapability: .readonlyUnsupportedCustomStack,
                restrictionReason: .unsupportedPivotStack
            )
        }

        if !order.allSatisfy(isSupportedXformToken) {
            return USDTransformInspection(
                localTransform: localTransform,
                authoredOps: authoredOps,
                editCapability: .readonlyUnsupportedCustomStack,
                restrictionReason: .customTransformStack
            )
        }

        let capability: USDTransformEditCapability
        if scalarRotationKinds == Set([.rotateX, .rotateY, .rotateZ]) {
            capability = .editableSeparateEuler
        } else if pivotCount == 1 {
            capability = .editablePivoted
        } else {
            capability = .editableCommon
        }

        return USDTransformInspection(
            localTransform: localTransform,
            authoredOps: authoredOps,
            editCapability: capability
        )
    }

    func collectAuthoredOps(for prim: UsdPrim) -> [USDAuthoredXformOp] {
        let order = xformOpOrder(prim)
        var seen = Set<String>()
        var ops: [USDAuthoredXformOp] = []

        for rawToken in order {
            let isInverse = rawToken.hasPrefix("!invert!")
            let token = isInverse ? String(rawToken.dropFirst("!invert!".count)) : rawToken
            let attr = prim.GetAttribute(TfToken(std.string(token)))
            guard let authoredOp = authoredOp(for: attr, token: rawToken, isInverse: isInverse) else {
                continue
            }
            seen.insert(rawToken)
            ops.append(authoredOp)
        }

        for attr in prim.GetAttributes() {
            let token = stableOwnedString(describing: attr.GetName().GetString())
            guard token.hasPrefix("xformOp:"), !seen.contains(token) else {
                continue
            }
            guard let authoredOp = authoredOp(for: attr, token: token, isInverse: false) else {
                continue
            }
            seen.insert(token)
            ops.append(authoredOp)
        }

        return ops
    }

    func xformOpOrder(_ prim: UsdPrim) -> [String] {
        let attr = prim.GetAttribute(TfToken(std.string("xformOpOrder")))
        guard attr.IsValid() else { return [] }

        var tokens = VtTokenArray()
        guard attr.Get(&tokens, UsdTimeCode.Default()) else { return [] }

        var order: [String] = []
        for index in 0..<tokens.size() {
            order.append(stableOwnedString(describing: tokens[index].GetString()))
        }
        return order
    }

    func authoredOp(
        for attr: UsdAttribute,
        token: String,
        isInverse: Bool
    ) -> USDAuthoredXformOp? {
        guard attr.IsValid() else { return nil }

        let normalizedToken = isInverse ? String(token.dropFirst("!invert!".count)) : token
        let kind = xformOpKind(for: normalizedToken)
        let precision = xformOpPrecision(for: attr)

        return USDAuthoredXformOp(
            token: token,
            kind: kind,
            precision: precision,
            isInverseOp: isInverse,
            isAuthored: attr.IsAuthored(),
            isTimeSampled: attr.GetNumTimeSamples() > 1,
            value: authoredXformValue(for: attr, kind: kind)
        )
    }

    func authoredXformValue(
        for attr: UsdAttribute,
        kind: USDAuthoredXformOpKind
    ) -> USDAuthoredXformOpValue? {
        switch kind {
        case .translate, .rotateXYZ, .scale, .pivot:
            return xformVector3Value(attr).map(USDAuthoredXformOpValue.vector3)
        case .rotateX, .rotateY, .rotateZ:
            return xformScalarValue(attr).map(USDAuthoredXformOpValue.scalar)
        case .orient, .transform, .custom:
            return .text(stableOwnedString(describing: attr.GetTypeName().GetAsToken().GetString()))
        }
    }

    func xformVector3Value(_ attr: UsdAttribute) -> SIMD3<Double>? {
        let typeName = attr.GetTypeName()
        if typeName == SdfValueTypeName.Double3
            || typeName == SdfValueTypeName.Point3d
            || typeName == SdfValueTypeName.Vector3d {
            var value = GfVec3d(0, 0, 0)
            guard attr.Get(&value, UsdTimeCode.Default()) else { return nil }
            return SIMD3<Double>(value[0], value[1], value[2])
        }

        if typeName == SdfValueTypeName.Float3
            || typeName == SdfValueTypeName.Point3f
            || typeName == SdfValueTypeName.Vector3f {
            var value = GfVec3f(0, 0, 0)
            guard attr.Get(&value, UsdTimeCode.Default()) else { return nil }
            return SIMD3<Double>(Double(value[0]), Double(value[1]), Double(value[2]))
        }

        return nil
    }

    func xformScalarValue(_ attr: UsdAttribute) -> Double? {
        let typeName = attr.GetTypeName()
        if typeName == SdfValueTypeName.Double {
            var value = 0.0
            guard attr.Get(&value, UsdTimeCode.Default()) else { return nil }
            return value
        }

        if typeName == SdfValueTypeName.Float {
            var value: Float = 0
            guard attr.Get(&value, UsdTimeCode.Default()) else { return nil }
            return Double(value)
        }

        return nil
    }

    func setCommonTransform(
        _ transform: USDTransformData,
        on prim: UsdPrim,
        options: USDTransformEditOptions
    ) throws {
        let xform = UsdGeomXformCommonAPI(prim)
        var ok = xform.SetTranslate(
            GfVec3d(transform.position.x, transform.position.y, transform.position.z),
            openUSDTimeCode(options.timeCode)
        )
        guard ok else {
            throw SwiftUsdShellError.invalidValue("Unable to author translate on prim")
        }
        // Rotate may fail on orient-authored prims (XformCommonAPI rejects
        // SetRotate when the prim uses xformOp:orient). Keep translate/scale
        // edits working instead of failing the whole transform write.
        _ = xform.SetRotate(
            GfVec3f(Float(transform.rotationDegrees.x), Float(transform.rotationDegrees.y), Float(transform.rotationDegrees.z)),
            .RotationOrderXYZ,
            openUSDTimeCode(options.timeCode)
        )
        ok = xform.SetScale(
            GfVec3f(Float(transform.scale.x), Float(transform.scale.y), Float(transform.scale.z)),
            openUSDTimeCode(options.timeCode)
        )
        guard ok else {
            throw SwiftUsdShellError.invalidValue("Unable to author scale on prim")
        }
        // Persist Euler hint in radians so subsequent reads can present
        // a stable rotation display without recomputing from quaternion.
        let degToRad = Float.pi / 180.0
        let eulerHintRadians = GfVec3f(
            Float(transform.rotationDegrees.x) * degToRad,
            Float(transform.rotationDegrees.y) * degToRad,
            Float(transform.rotationDegrees.z) * degToRad
        )
        _ = prim.SetMetadataByDictKey(
            TfToken("customData"),
            TfToken("rotationEulerHint"),
            VtValue(eulerHintRadians)
        )
    }

    func materialBindingInfo(
        for prim: UsdPrim,
        selectedPath: USDPath
    ) -> USDMaterialBindingInfo {
        let selectedPrimPath = selectedPath.rawValue
        let primTypeName = stableOwnedString(describing: prim.GetTypeName().GetString())

        if primTypeName == "Material" {
            return USDMaterialBindingInfo(
                selectedPrimPath: selectedPath,
                effectiveMaterialPath: selectedPath,
                authoredMaterialPath: selectedPath,
                bindingSourcePrimPath: selectedPath
            )
        }

        let effectiveMaterialPath = effectiveMaterialPath(for: prim).map { USDPath($0) }
        let selectedSdfPath = prim.GetPath()
        let purposeToken = TfToken("")

        var authoredMaterialPath: USDPath?
        var bindingSourcePrimPath: USDPath?
        var bindingStrength: USDMaterialBindingStrength?
        var currentPrim = prim

        while currentPrim.IsValid() {
            let authoredBinding = directBindingDetails(for: currentPrim, purposeToken: purposeToken)
            if let targetPath = authoredBinding.targetPath {
                let isInherited = currentPrim.GetPath() != selectedSdfPath
                authoredMaterialPath = USDPath(targetPath)
                bindingSourcePrimPath = USDPath(
                    stableOwnedString(describing: currentPrim.GetPath().GetAsString())
                )
                bindingStrength = authoredBinding.strength
                if isInherited, bindingStrength == .fallbackStrength {
                    bindingStrength = .weakerThanDescendants
                }
                break
            }

            currentPrim = currentPrim.GetParent()
        }

        return USDMaterialBindingInfo(
            selectedPrimPath: USDPath(selectedPrimPath),
            effectiveMaterialPath: effectiveMaterialPath,
            authoredMaterialPath: authoredMaterialPath,
            bindingSourcePrimPath: bindingSourcePrimPath,
            bindingStrength: bindingStrength
        )
    }

    func materialSummaries(_ root: UsdPrim) -> [USDMaterialSummary] {
        var summaries: [USDMaterialSummary] = []

        func visit(_ prim: UsdPrim) {
            if stableOwnedString(describing: prim.GetTypeName().GetString()) == "Material",
               let summary = materialSummary(prim) {
                summaries.append(summary)
            }

            for child in prim.GetChildren().swiftSequence {
                visit(child)
            }
        }

        visit(root)
        return summaries
    }

    func materialSummary(for prim: UsdPrim, stage: UsdStage) -> USDMaterialSummary? {
        if stableOwnedString(describing: prim.GetTypeName().GetString()) == "Material" {
            return materialSummary(prim)
        }

        guard let materialPath = effectiveMaterialPath(for: prim) else {
            return nil
        }
        let materialPrim = stage.GetPrimAtPath(SdfPath(std.string(materialPath)))
        guard materialPrim.IsValid() else {
            return nil
        }
        return materialSummary(materialPrim)
    }

    func materialSummary(_ materialPrim: UsdPrim) -> USDMaterialSummary? {
        let material = UsdShadeMaterial(materialPrim)
        guard material.GetPrim().IsValid() else {
            return nil
        }

        return USDMaterialSummary(
            path: USDPath(stableOwnedString(describing: materialPrim.GetPath().GetAsString())),
            name: stableOwnedString(describing: materialPrim.GetName().GetString()),
            materialType: materialSummaryType(material),
            isInstanceable: materialPrim.IsInstanceable(),
            compositionArcs: compositionArcs(materialPrim),
            properties: materialProperties(material)
        )
    }

    func materialSummaryType(_ material: UsdShadeMaterial) -> USDMaterialSummaryType {
        let surfaceShader = material.ComputeSurfaceSource(TfToken(), nil, nil)
        guard surfaceShader.GetPrim().IsValid() else {
            return .unknown
        }

        let identifier = shaderIdentifier(surfaceShader.GetPrim()) ?? ""
        if identifier.contains("UsdPreviewSurface") {
            return .usdPreviewSurface
        }
        if identifier.contains("ND_") {
            return .materialX
        }
        return .unknown
    }

    func materialProperties(_ material: UsdShadeMaterial) -> [USDMaterialPropertySummary] {
        let surfaceShader = material.ComputeSurfaceSource(TfToken(), nil, nil)
        guard surfaceShader.GetPrim().IsValid() else {
            return []
        }

        let inputs = surfaceShader.GetInputs(true)
        var properties: [USDMaterialPropertySummary] = []
        for index in 0..<inputs.size() {
            let input = inputs[index]
            let name = stableOwnedString(describing: input.GetBaseName().GetString())

            if let property = materialProperty(input) {
                properties.append(property)
                continue
            }

            if let texture = textureProperty(input, depth: 0) {
                properties.append(
                    USDMaterialPropertySummary(
                        name: name,
                        propertyType: .texture,
                        value: texture
                    )
                )
                continue
            }

        }
        return properties
    }

    func materialProperty(_ input: UsdShadeInput) -> USDMaterialPropertySummary? {
        let attr = input.GetAttr()
        guard attr.IsValid(), attr.GetResolveInfo().ValueIsBlocked() == false else {
            return nil
        }
        guard attr.HasAuthoredValueOpinion() || attr.HasValue() else {
            return nil
        }

        let name = stableOwnedString(describing: input.GetBaseName().GetString())
        let typeName = attr.GetTypeName()

        if typeName == SdfValueTypeName.Bool {
            var value = false
            guard attr.Get(&value, UsdTimeCode.Default()) else { return nil }
            return USDMaterialPropertySummary(name: name, propertyType: .bool, value: .bool(value))
        }

        if typeName == SdfValueTypeName.Int {
            var value: Int32 = 0
            guard attr.Get(&value, UsdTimeCode.Default()) else { return nil }
            return USDMaterialPropertySummary(name: name, propertyType: .int, value: .int(Int(value)))
        }

        if typeName == SdfValueTypeName.Float {
            var value: Float = 0
            guard attr.Get(&value, UsdTimeCode.Default()) else { return nil }
            return USDMaterialPropertySummary(name: name, propertyType: .float, value: .float(value))
        }

        if typeName == SdfValueTypeName.Double {
            var value: Double = 0
            guard attr.Get(&value, UsdTimeCode.Default()) else { return nil }
            return USDMaterialPropertySummary(name: name, propertyType: .float, value: .float(Float(value)))
        }

        if typeName == SdfValueTypeName.Color3f || typeName == SdfValueTypeName.Float3 {
            var value = GfVec3f(0, 0, 0)
            guard attr.Get(&value, UsdTimeCode.Default()) else { return nil }
            return USDMaterialPropertySummary(
                name: name,
                propertyType: .color,
                value: .color(red: value[0], green: value[1], blue: value[2])
            )
        }

        if typeName == SdfValueTypeName.Token {
            var value = TfToken()
            guard attr.Get(&value, UsdTimeCode.Default()) else { return nil }
            return USDMaterialPropertySummary(
                name: name,
                propertyType: .token,
                value: .token(stableOwnedString(describing: value.GetString()))
            )
        }

        if typeName == SdfValueTypeName.String {
            var value = std.string()
            guard attr.Get(&value, UsdTimeCode.Default()) else { return nil }
            return USDMaterialPropertySummary(
                name: name,
                propertyType: .string,
                value: .string(stableOwnedString(describing: value))
            )
        }

        if typeName == SdfValueTypeName.Asset {
            guard let texture = textureValue(attr) else { return nil }
            return USDMaterialPropertySummary(name: name, propertyType: .texture, value: texture)
        }

        return USDMaterialPropertySummary(
            name: name,
            propertyType: .unsupported,
            value: .unsupported(
                typeName: stableOwnedString(describing: typeName.GetAsToken().GetString()),
                valueDescription: stableOwnedString(describing: attr.GetTypeName().GetAsToken().GetString())
            )
        )
    }

    func textureProperty(_ input: UsdShadeInput, depth: Int) -> USDMaterialPropertyInfo? {
        guard depth < 5 else { return nil }

        let attr = input.GetAttr()
        if attr.IsValid(), attr.GetResolveInfo().ValueIsBlocked() {
            return nil
        }

        if input.HasConnectedSource() {
            let sources = input.GetConnectedSources(nil)
            if sources.size() > 0 {
                let sourceInfo = sources[0]
                if let connected = textureProperty(
                    source: sourceInfo.source,
                    sourceName: stableOwnedString(describing: sourceInfo.sourceName.GetString()),
                    depth: depth + 1
                ) {
                    return connected
                }
            }
        }

        return textureValue(attr)
    }

    func textureProperty(
        source: UsdShadeConnectableAPI,
        sourceName: String,
        depth: Int
    ) -> USDMaterialPropertyInfo? {
        guard depth < 5 else { return nil }

        let prim = source.GetPrim()
        guard prim.IsValid() else {
            return nil
        }

        let connectable = UsdShadeConnectableAPI(prim)
        if !sourceName.isEmpty {
            let output = connectable.GetOutput(TfToken(std.string(sourceName)))
            if output.GetAttr().IsValid() {
                if output.GetAttr().GetResolveInfo().ValueIsBlocked() {
                    return nil
                }

                if output.HasConnectedSource() {
                    let sources = output.GetConnectedSources(nil)
                    if sources.size() > 0 {
                        let info = sources[0]
                        return textureProperty(
                            source: info.source,
                            sourceName: stableOwnedString(describing: info.sourceName.GetString()),
                            depth: depth + 1
                        )
                    }
                }
            }

            let input = connectable.GetInput(TfToken(std.string(sourceName)))
            if input.GetAttr().IsValid(),
               let texture = textureProperty(input, depth: depth + 1) {
                return texture
            }
        }

        let shader = UsdShadeShader(prim)
        guard shader.GetPrim().IsValid() else {
            return nil
        }

        let fileInput = shader.GetInput(TfToken(std.string("file")))
        if fileInput.GetAttr().IsValid() {
            return textureProperty(fileInput, depth: depth + 1)
        }

        let fileAttr = prim.GetAttribute(TfToken(std.string("inputs:file")))
        return textureValue(fileAttr)
    }

    func textureValue(_ attr: UsdAttribute) -> USDMaterialPropertyInfo? {
        guard attr.IsValid() else {
            return nil
        }

        var value = SdfAssetPath()
        guard attr.Get(&value, UsdTimeCode.Default()) else {
            return nil
        }

        let authored = stableOwnedString(describing: value.GetAssetPath())
        let resolved = stableOwnedString(describing: value.GetResolvedPath())
        if authored.isEmpty, resolved.isEmpty {
            return nil
        }

        return .texture(
            url: authored.isEmpty ? resolved : authored,
            resolvedPath: resolved.isEmpty ? nil : resolved
        )
    }

    func effectiveMaterialPath(for prim: UsdPrim) -> String? {
        let bindingAPI = UsdShadeMaterialBindingAPI(prim)
        let material = bindingAPI.ComputeBoundMaterial()
        if material.GetPrim().IsValid() {
            return stableOwnedString(describing: material.GetPath().GetAsString())
        }

        let directRel = prim.GetRelationship(TfToken(std.string("material:binding")))
        if directRel.IsValid(), let target = firstBindingTarget(from: directRel) {
            return target
        }

        if stableOwnedString(describing: prim.GetTypeName().GetString()) == "Mesh" {
            var subsetTargets: Set<String> = []
            for child in prim.GetChildren().swiftSequence {
                if stableOwnedString(describing: child.GetTypeName().GetString()) != "GeomSubset" {
                    continue
                }
                let subsetRel = child.GetRelationship(TfToken(std.string("material:binding")))
                if subsetRel.IsValid(), let target = firstBindingTarget(from: subsetRel) {
                    subsetTargets.insert(target)
                }
            }
            if subsetTargets.count == 1 {
                return subsetTargets.first
            }
        }

        return nil
    }

    func directBindingDetails(
        for prim: UsdPrim,
        purposeToken: TfToken
    ) -> (targetPath: String?, strength: USDMaterialBindingStrength?) {
        let bindingAPI = UsdShadeMaterialBindingAPI(prim)
        let rel = bindingAPI.GetDirectBindingRel(purposeToken)
        if rel.IsValid(), let directTarget = firstBindingTarget(from: rel) {
            let token = UsdShadeMaterialBindingAPI.GetMaterialBindingStrength(rel)
            let raw = stableOwnedString(describing: token.GetString())
            return (directTarget, USDMaterialBindingStrength(rawValue: raw) ?? .fallbackStrength)
        }

        let fallbackRel = prim.GetRelationship(TfToken(std.string("material:binding")))
        if fallbackRel.IsValid(), let directTarget = firstBindingTarget(from: fallbackRel) {
            return (directTarget, .fallbackStrength)
        }

        return (nil, nil)
    }

    func firstBindingTarget(from relationship: UsdRelationship) -> String? {
        var targets = SdfPathVector()
        _ = relationship.GetTargets(&targets)
        guard !targets.empty() else { return nil }
        return stableOwnedString(describing: targets[0].GetAsString())
    }

    // MARK: - Sparse layer authoring

    public func writeSparseLayer(
        request: USDSparseLayerRequest,
        outputURL: USDStageURL
    ) throws {
        let usda = generateSparseUSDA(request)
        if FileManager.default.fileExists(atPath: outputURL.url.path) {
            try FileManager.default.removeItem(at: outputURL.url)
        }
        try usda.write(to: outputURL.url, atomically: true, encoding: .utf8)
    }

    public func validatePrimExistence(
        stageURL: USDStageURL,
        primPath: USDPath
    ) throws -> (exists: Bool, warnings: [String]) {
        let stage = try self.stage(for: stageURL, loadPolicy: .loadNone)
        let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
        if prim.IsValid() {
            return (true, [])
        }
        return (false, ["Prim not found at path '\(primPath.rawValue)'"])
    }

    public func shaderInputSource(
        _ query: USDShaderInputSourceQuery
    ) throws -> USDShaderInputSource? {
        let stage = try self.stage(for: query.stageURL, loadPolicy: .loadNone)
        let prim = stage.GetPrimAtPath(SdfPath(std.string(query.shaderPath.rawValue)))
        guard prim.IsValid() else { return nil }

        let shader = UsdShadeShader(prim)
        guard shader.GetPrim().IsValid() else { return nil }

        let inputName = query.inputName
            .replacingOccurrences(of: "inputs:", with: "")
        let input = shader.GetInput(TfToken(std.string(inputName)))
        guard input.GetAttr().IsValid(), input.HasConnectedSource() else {
            return nil
        }

        let sources = input.GetConnectedSources(nil)
        guard sources.size() > 0 else { return nil }

        let sourceInfo = sources[0]
        let sourcePrim = sourceInfo.source.GetPrim()
        guard sourcePrim.IsValid() else { return nil }

        return USDShaderInputSource(
            sourcePrimPath: USDPath(
                stableOwnedString(describing: sourcePrim.GetPath().GetAsString())
            ),
            sourceName: stableOwnedString(describing: sourceInfo.sourceName.GetString()),
            sourceShaderIdentifier: shaderIdentifier(sourcePrim)
        )
    }

    /// Finds prims in the stage that carry composition-arc references to
    /// `assetPath` and writes a sparse override layer that removes those
    /// references. The output contains only `delete references` metadata
    /// opinions — no source-stage content is copied.
    public func removeAssetReferences(
        stageURL: USDStageURL,
        assetPath: String,
        outputURL: USDStageURL
    ) throws -> (changedPrimPaths: [String], warnings: [String]) {
        let stage = try self.stage(for: stageURL, loadPolicy: .loadAll)
        var overrides: [USDSparseOverride] = []
        var warnings: [String] = []

        let missingBasename = (assetPath as NSString).lastPathComponent
        for prim in stage.Traverse().swiftSequence {
            guard prim.IsValid() else { continue }
            guard prim.HasAuthoredReferences() else { continue }
            let primPath = stableOwnedString(describing: prim.GetPath().GetAsString())
            let authored = typedAuthoredReferences(on: prim)
            let matchingAssetPaths: [String] = authored.compactMap { ref in
                guard !ref.assetPath.isEmpty else { return nil }
                if ref.assetPath == assetPath { return ref.assetPath }
                if !missingBasename.isEmpty {
                    let refBasename = (ref.assetPath as NSString).lastPathComponent
                    if refBasename == missingBasename { return ref.assetPath }
                }
                return nil
            }
            guard !matchingAssetPaths.isEmpty else { continue }

            // Emit one typed `delete` list-op opinion per distinct matching
            // authored asset path. Using the authored value ensures the
            // sparse override targets the exact `SdfReference` already on
            // the prim instead of a heuristic substring guess.
            var seenAssets = Set<String>()
            let deleteItems: [USDListOpItem] = matchingAssetPaths.compactMap { authoredAsset in
                guard seenAssets.insert(authoredAsset).inserted else { return nil }
                return .asset(USDPath(authoredAsset))
            }
            overrides.append(USDSparseOverride(
                primPath: USDPath(primPath),
                metadata: [
                    USDSparseMetadata(
                        key: .references,
                        opinion: .delete(deleteItems)
                    )
                ]
            ))
        }

        let request = USDSparseLayerRequest(overrides: overrides)
        try writeSparseLayer(request: request, outputURL: outputURL)

        return (
            changedPrimPaths: overrides.map(\.primPath.rawValue),
            warnings: warnings
        )
    }

    /// Builds typed sparse overrides that remove every composition-arc
    /// `references` opinion targeting the supplied missing asset path, plus
    /// every authored asset/string/token attribute value that resolves to
    /// the same missing path. The result is written as a single sparse
    /// override layer with no source-stage content copied.
    ///
    /// This is the composed replacement for USDTools `cleanupReferences`,
    /// split internally into two typed passes:
    /// - composition reference list-op deletion via typed `SdfReference`
    /// - authored attribute clearing via typed `SdfValueTypeName` dispatch
    public func cleanupMissingAssetDependencies(
        stageURL: USDStageURL,
        missingFilePath: String,
        outputURL: USDStageURL
    ) throws -> (changedPrimPaths: [String], clearedAttributeCount: Int, warnings: [String]) {
        let stage = try self.stage(for: stageURL, loadPolicy: .loadAll)
        var primOverrides: [USDPath: USDSparseOverride] = [:]
        var orderedPaths: [USDPath] = []
        var warnings: [String] = []
        var clearedCount = 0
        let missingBasename = (missingFilePath as NSString).lastPathComponent

        func matches(_ candidate: String) -> Bool {
            guard !candidate.isEmpty else { return false }
            if candidate == missingFilePath { return true }
            if candidate.hasSuffix(missingFilePath) { return true }
            if !missingBasename.isEmpty {
                let candidateBasename = (candidate as NSString).lastPathComponent
                if candidateBasename == missingBasename { return true }
            }
            return false
        }

        func merge(
            primPath: USDPath,
            metadata: [USDSparseMetadata] = [],
            attributes: [USDSparseAttributeOverride] = []
        ) {
            if var existing = primOverrides[primPath] {
                existing.metadata.append(contentsOf: metadata)
                existing.attributes.append(contentsOf: attributes)
                primOverrides[primPath] = existing
            } else {
                primOverrides[primPath] = USDSparseOverride(
                    primPath: primPath,
                    metadata: metadata,
                    attributes: attributes
                )
                orderedPaths.append(primPath)
            }
        }

        for prim in stage.Traverse().swiftSequence {
            guard prim.IsValid() else { continue }
            let primPathString = stableOwnedString(describing: prim.GetPath().GetAsString())
            let primPath = USDPath(primPathString)

            // Pass 1: composition references via typed SdfReference walk.
            if prim.HasAuthoredReferences() {
                let authored = typedAuthoredReferences(on: prim)
                var seenAssets = Set<String>()
                let deleteItems: [USDListOpItem] = authored.compactMap { ref in
                    guard !ref.assetPath.isEmpty, matches(ref.assetPath) else { return nil }
                    guard seenAssets.insert(ref.assetPath).inserted else { return nil }
                    return .asset(USDPath(ref.assetPath))
                }
                if !deleteItems.isEmpty {
                    merge(
                        primPath: primPath,
                        metadata: [USDSparseMetadata(key: .references, opinion: .delete(deleteItems))]
                    )
                }
            }

            // Pass 2: authored asset / string / token attribute clearing.
            var attrOverrides: [USDSparseAttributeOverride] = []
            for attr in prim.GetAttributes() {
                guard attr.IsAuthored() else { continue }
                let typeName = attr.GetTypeName()
                let attrName = stableOwnedString(describing: attr.GetName().GetString())
                if typeName == SdfValueTypeName.Asset {
                    var assetValue = SdfAssetPath()
                    guard attr.Get(&assetValue, UsdTimeCode.Default()) else { continue }
                    let authored = stableOwnedString(describing: assetValue.GetAssetPath())
                    let resolved = stableOwnedString(describing: assetValue.GetResolvedPath())
                    guard matches(authored) || matches(resolved) else { continue }
                    attrOverrides.append(USDSparseAttributeOverride(
                        name: attrName,
                        opinion: .value(.assetPath(USDAssetPath(""))),
                        usdTypeName: "asset"
                    ))
                    clearedCount += 1
                } else if typeName == SdfValueTypeName.String {
                    var value = std.string()
                    guard attr.Get(&value, UsdTimeCode.Default()) else { continue }
                    let authored = stableOwnedString(describing: value)
                    guard matches(authored) else { continue }
                    attrOverrides.append(USDSparseAttributeOverride(
                        name: attrName,
                        opinion: .value(.string("")),
                        usdTypeName: "string"
                    ))
                    clearedCount += 1
                } else if typeName == SdfValueTypeName.Token {
                    var token = TfToken()
                    guard attr.Get(&token, UsdTimeCode.Default()) else { continue }
                    let authored = stableOwnedString(describing: token.GetString())
                    guard matches(authored) else { continue }
                    attrOverrides.append(USDSparseAttributeOverride(
                        name: attrName,
                        opinion: .value(.token(USDToken(""))),
                        usdTypeName: "token"
                    ))
                    clearedCount += 1
                }
            }
            if !attrOverrides.isEmpty {
                merge(primPath: primPath, attributes: attrOverrides)
            }
        }

        let overrides = orderedPaths.compactMap { primOverrides[$0] }
        let request = USDSparseLayerRequest(overrides: overrides)
        try writeSparseLayer(request: request, outputURL: outputURL)

        return (
            changedPrimPaths: overrides.map(\.primPath.rawValue),
            clearedAttributeCount: clearedCount,
            warnings: warnings
        )
    }

    /// Clears authored asset / string / token attribute values that point at
    /// a missing file path, by writing a sparse override layer with the
    /// matching attributes cleared to an empty typed value.
    ///
    /// This is the attribute-side companion to ``removeAssetReferences``:
    /// the former removes composition-arc `references` list-op opinions; this
    /// removes scene-referenced texture/file dependencies authored as
    /// attribute values. No stringified `VtValue` parsing is used — the
    /// attribute's typed `SdfValueTypeName` and the typed authored value
    /// (`SdfAssetPath.GetAssetPath()`, `std.string`, `TfToken.GetString()`)
    /// drive both the detection and the cleared replacement.
    public func cleanupReferencingAttributes(
        stageURL: USDStageURL,
        missingFilePath: String,
        outputURL: USDStageURL
    ) throws -> (changedPrimPaths: [String], clearedAttributeCount: Int, warnings: [String]) {
        let stage = try self.stage(for: stageURL, loadPolicy: .loadAll)
        var overrides: [USDSparseOverride] = []
        var warnings: [String] = []
        var clearedCount = 0
        let missingBasename = (missingFilePath as NSString).lastPathComponent

        func matches(_ candidate: String) -> Bool {
            guard !candidate.isEmpty else { return false }
            if candidate == missingFilePath { return true }
            if candidate.hasSuffix(missingFilePath) { return true }
            if !missingBasename.isEmpty {
                let candidateBasename = (candidate as NSString).lastPathComponent
                if candidateBasename == missingBasename { return true }
            }
            return false
        }

        for prim in stage.Traverse().swiftSequence {
            guard prim.IsValid() else { continue }
            let primPath = stableOwnedString(describing: prim.GetPath().GetAsString())
            var attrOverrides: [USDSparseAttributeOverride] = []
            for attr in prim.GetAttributes() {
                guard attr.IsAuthored() else { continue }
                let typeName = attr.GetTypeName()
                let attrName = stableOwnedString(describing: attr.GetName().GetString())
                if typeName == SdfValueTypeName.Asset {
                    var assetValue = SdfAssetPath()
                    guard attr.Get(&assetValue, UsdTimeCode.Default()) else { continue }
                    let authored = stableOwnedString(describing: assetValue.GetAssetPath())
                    let resolved = stableOwnedString(describing: assetValue.GetResolvedPath())
                    guard matches(authored) || matches(resolved) else { continue }
                    attrOverrides.append(USDSparseAttributeOverride(
                        name: attrName,
                        opinion: .value(.assetPath(USDAssetPath(""))),
                        usdTypeName: "asset"
                    ))
                    clearedCount += 1
                } else if typeName == SdfValueTypeName.String {
                    var value = std.string()
                    guard attr.Get(&value, UsdTimeCode.Default()) else { continue }
                    let authored = stableOwnedString(describing: value)
                    guard matches(authored) else { continue }
                    attrOverrides.append(USDSparseAttributeOverride(
                        name: attrName,
                        opinion: .value(.string("")),
                        usdTypeName: "string"
                    ))
                    clearedCount += 1
                } else if typeName == SdfValueTypeName.Token {
                    var token = TfToken()
                    guard attr.Get(&token, UsdTimeCode.Default()) else { continue }
                    let authored = stableOwnedString(describing: token.GetString())
                    guard matches(authored) else { continue }
                    attrOverrides.append(USDSparseAttributeOverride(
                        name: attrName,
                        opinion: .value(.token(USDToken(""))),
                        usdTypeName: "token"
                    ))
                    clearedCount += 1
                }
            }
            guard !attrOverrides.isEmpty else { continue }
            overrides.append(USDSparseOverride(
                primPath: USDPath(primPath),
                attributes: attrOverrides
            ))
        }

        let request = USDSparseLayerRequest(overrides: overrides)
        try writeSparseLayer(request: request, outputURL: outputURL)

        return (
            changedPrimPaths: overrides.map(\.primPath.rawValue),
            clearedAttributeCount: clearedCount,
            warnings: warnings
        )
    }

    /// Validates material binding conformance on Mesh and GeomSubset prims.
    /// Returns diagnostics for prims with missing bindings or missing
    /// Returns whether a prim has the named API schema applied.
    public func primHasAppliedSchema(
        stageURL: USDStageURL,
        primPath: USDPath,
        schemaName: String
    ) throws -> Bool {
        let stage = try self.stage(for: stageURL, loadPolicy: .loadNone)
        let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
        guard prim.IsValid() else { return false }
        if prim.HasAPI(TfToken(std.string(schemaName))) {
            return true
        }
        let target = schemaName.lowercased()
        let appliedSchemas = prim.GetAppliedSchemas()
        for index in 0..<appliedSchemas.size() {
            let schema = appliedSchemas[index]
            if stableOwnedString(describing: schema.GetString()).lowercased() == target {
                return true
            }
        }
        return false
    }

    /// Reads the authored default value of a single attribute on a prim.
    /// Returns `nil` when the attribute does not exist or has no value.
    public func attributeValue(_ query: USDAttributeValueQuery) throws -> USDValue? {
        let stage = try self.stage(for: query.stageURL, loadPolicy: .loadNone)
        let prim = stage.GetPrimAtPath(SdfPath(std.string(query.primPath.rawValue)))
        guard prim.IsValid() else { return nil }
        let attr = prim.GetAttribute(TfToken(std.string(query.attributeName)))
        guard attr.IsValid() else { return nil }

        let typeName = String(attr.GetTypeName().GetAsToken().GetString())
        if typeName == "asset" {
            var assetPath = SdfAssetPath()
            guard attr.Get(&assetPath, UsdTimeCode.Default()) else { return nil }
            let authored = stableOwnedString(describing: assetPath.GetAssetPath())
            if authored.isEmpty {
                let resolved = stableOwnedString(describing: assetPath.GetResolvedPath())
                return resolved.isEmpty ? nil : .assetPath(USDAssetPath(resolved))
            }
            return .assetPath(USDAssetPath(authored))
        }

        var vtValue = VtValue()
        guard attr.Get(&vtValue, UsdTimeCode.Default()) else { return nil }
        return convertVtValueToUSDValue(vtValue)
    }

    /// Rewrites the declared USD type of attributes on prims and writes a
    /// sparse override layer containing only the new typed attribute opinions.
    public func rewriteAttributeTypes(
        _ request: USDAttributeTypeRewriteRequest
    ) throws -> USDAttributeTypeRewriteResult {
        let stage = try self.stage(for: request.stageURL, loadPolicy: .loadNone)

        var changedPrimPaths: [String] = []
        var warnings: [String] = []
        var overrides: [USDSparseOverride] = []

        for rewrite in request.rewrites {
            let prim = stage.GetPrimAtPath(SdfPath(std.string(rewrite.primPath)))
            guard prim.IsValid() else {
                warnings.append("Prim not found at '\(rewrite.primPath)'")
                continue
            }

            let attr = prim.GetAttribute(TfToken(std.string(rewrite.attributeName)))
            guard attr.IsValid() else {
                warnings.append("Attribute '\(rewrite.attributeName)' not found on '\(rewrite.primPath)'")
                continue
            }

            // Validate the target type name before modifying the layer.
            guard let targetTypeName = sdfValueTypeName(named: rewrite.targetTypeName) else {
                warnings.append("Unknown type name '\(rewrite.targetTypeName)' for attribute '\(rewrite.attributeName)' on '\(rewrite.primPath)'")
                continue
            }

            let sourceTypeName = attr.GetTypeName()
            let rewrittenValue = rewrittenAttributeUSDValue(
                from: attr,
                sourceTypeName: sourceTypeName,
                targetTypeName: targetTypeName
            )
            let opinion: USDSparseAttributeOpinion = rewrittenValue.map {
                .value($0)
            } ?? .declare
            let override = USDSparseOverride(
                primPath: USDPath(rewrite.primPath),
                attributes: [
                    USDSparseAttributeOverride(
                        name: rewrite.attributeName,
                        opinion: opinion,
                        usdTypeName: rewrite.targetTypeName
                    )
                ]
            )
            overrides.append(override)

            changedPrimPaths.append(rewrite.primPath)
        }

        try writeSparseLayer(
            request: USDSparseLayerRequest(overrides: overrides),
            outputURL: request.outputURL
        )

        return USDAttributeTypeRewriteResult(
            changedPrimPaths: changedPrimPaths,
            warnings: warnings
        )
    }

    /// Rewrites the declared USD type of attributes on prims, preserving the
    /// complete source layer content in the output.
    ///
    /// Use this for flattened-source rebases where `outputURL` is expected to
    /// replace the full source baseline. Use ``rewriteAttributeTypes(_:)`` for
    /// sparse edit layers.
    public func rewriteAttributeTypesInLayer(
        _ request: USDAttributeTypeRewriteRequest
    ) throws -> USDAttributeTypeRewriteResult {
        let stage = try self.stage(for: request.stageURL, loadPolicy: .loadAll)
        let rootLayerHandle = stage.GetRootLayer()
        let rootLayer = USDOverlay.Dereference(rootLayerHandle)

        var changedPrimPaths: [String] = []
        var warnings: [String] = []

        for rewrite in request.rewrites {
            let attrPath = SdfPath(std.string("\(rewrite.primPath).\(rewrite.attributeName)"))
            let attrSpec = rootLayer.GetAttributeAtPath(attrPath)
            guard Bool(attrSpec) else {
                warnings.append("Attribute spec '\(rewrite.attributeName)' not found on '\(rewrite.primPath)'")
                continue
            }

            guard let targetTypeName = sdfValueTypeName(named: rewrite.targetTypeName) else {
                warnings.append("Unknown type name '\(rewrite.targetTypeName)' for attribute '\(rewrite.attributeName)' on '\(rewrite.primPath)'")
                continue
            }

            guard rewriteAttributeSpecType(attrSpec, in: rootLayer, targetTypeName: targetTypeName) else {
                warnings.append("Failed rewriting attribute spec '\(rewrite.primPath).\(rewrite.attributeName)'")
                continue
            }

            changedPrimPaths.append(rewrite.primPath)
        }

        guard rootLayer.Export(std.string(request.outputURL.url.path), std.string(), SdfLayer.FileFormatArguments()) else {
            throw SwiftUsdShellError.invalidValue("Failed to export layer to \(request.outputURL.url.lastPathComponent)")
        }

        return USDAttributeTypeRewriteResult(
            changedPrimPaths: changedPrimPaths,
            warnings: warnings
        )
    }

    /// Finds shader inputs whose authored type matches `currentTypeName` and
    /// returns explicit attribute rewrite specs for them.
    public func shaderInputTypeRewrites(
        _ query: USDShaderInputTypeRewriteQuery
    ) throws -> [USDAttributeTypeRewrite] {
        let stage = try self.stage(for: query.stageURL, loadPolicy: .loadAll)
        guard let currentTypeName = sdfValueTypeName(named: query.currentTypeName) else {
            throw SwiftUsdShellError.invalidValue("Unknown current type name '\(query.currentTypeName)'")
        }
        guard sdfValueTypeName(named: query.targetTypeName) != nil else {
            throw SwiftUsdShellError.invalidValue("Unknown target type name '\(query.targetTypeName)'")
        }

        let inputBaseName = shaderInputBaseName(query.inputName)
        let inputAttrName = "inputs:\(inputBaseName)"
        var rewrites: [USDAttributeTypeRewrite] = []

        let rootLayer = USDOverlay.Dereference(stage.GetRootLayer())
        collectShaderInputTypeRewrites(
            primSpec: rootLayer.GetPseudoRoot(),
            inputAttrName: inputAttrName,
            currentTypeName: currentTypeName,
            targetTypeName: query.targetTypeName,
            shaderIdentifierPrefix: query.shaderIdentifierPrefix,
            rewrites: &rewrites
        )

        return rewrites
    }

    /// Flattens a nested shader by copying the child shader prim spec to a
    /// new sibling path, marks the old child as inactive, and exports a
    /// sparse override layer. Returns the new destination prim path.
    public func flattenNestedShaderPrim(
        stageURL: USDStageURL,
        parentPath: USDPath,
        childPath: USDPath,
        outputURL: USDStageURL
    ) throws -> USDPath {
        let stage = try self.stage(for: stageURL, loadPolicy: .loadAll)
        let oldSdfPath = SdfPath(std.string(childPath.rawValue))
        let parentSdfPath = SdfPath(std.string(parentPath.rawValue))
        let destinationParent = parentSdfPath.GetParentPath()

        let shaderName = childPath.rawValue.components(separatedBy: "/").last ?? "Shader"
        // Compute destination path: sibling of parent, dedup naming
        var newSdfPath = destinationParent.AppendChild(TfToken(std.string(shaderName)))
        for index in 1... {
            let testPrim = stage.GetPrimAtPath(newSdfPath)
            guard testPrim.IsValid() else { break }
            newSdfPath = destinationParent.AppendChild(
                TfToken(std.string("\(shaderName)_\(index)"))
            )
        }

        let editStagePtr = UsdStage.CreateInMemory(
            std.string("flatten_shader_edit.usda"),
            UsdStage.InitialLoadSet.LoadAll
        )
        guard editStagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(outputURL, diagnostic: "in-memory-stage")
        }
        let editStage = USDOverlay.Dereference(editStagePtr)
        let editLayer = editStage.GetRootLayer()

        _ = editStage.OverridePrim(destinationParent)
        let sourceLayer = stage.GetRootLayer()
        guard pxr.SdfCopySpec(sourceLayer, oldSdfPath, editLayer, newSdfPath) else {
            throw SwiftUsdShellError.invalidValue(
                "Failed to copy spec from \(childPath.rawValue) to \(newSdfPath.GetAsString())"
            )
        }

        let oldPrim = editStage.OverridePrim(oldSdfPath)
        _ = oldPrim.SetActive(false)

        guard editStage.Export(std.string(outputURL.url.path), false, SdfLayer.FileFormatArguments()) else {
            throw SwiftUsdShellError.invalidValue(
                "Failed to export flatten layer to \(outputURL.url.lastPathComponent)"
            )
        }

        return USDPath(stableOwnedString(describing: newSdfPath.GetAsString()))
    }

    /// Authors a sparse material-binding edit layer using `UsdShadeMaterialBindingAPI`.
    ///
    /// This intentionally goes through OpenUSD's schema API instead of hand-emitting
    /// `material:binding` USDA. `Bind` owns the exact relationship name, purpose, and
    /// binding-strength metadata semantics for the active OpenUSD version.
    public func writeMaterialBindingLayer(
        outputURL: USDStageURL,
        primPath: USDPath,
        materialPath: USDPath,
        strength: USDMaterialBindingStrength = .fallbackStrength
    ) throws {
        let editStagePtr = UsdStage.CreateInMemory(
            std.string("material_binding_edit.usda"),
            UsdStage.InitialLoadSet.LoadAll
        )
        guard editStagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(outputURL, diagnostic: "in-memory-stage")
        }
        let editStage = USDOverlay.Dereference(editStagePtr)
        let prim = editStage.OverridePrim(SdfPath(std.string(primPath.rawValue)))
        let materialPrim = editStage.OverridePrim(SdfPath(std.string(materialPath.rawValue)))

        let bindingAPI = UsdShadeMaterialBindingAPI.Apply(prim)
        let material = UsdShadeMaterial(materialPrim)
        let strengthToken = TfToken(
            std.string(strength == .fallbackStrength ? "fallbackStrength" : strength.rawValue)
        )
        guard bindingAPI.Bind(material, strengthToken, TfToken("")) else {
            throw SwiftUsdShellError.invalidValue(
                "Failed to bind material \(materialPath.rawValue) to \(primPath.rawValue)"
            )
        }

        guard editStage.Export(std.string(outputURL.url.path), false, SdfLayer.FileFormatArguments()) else {
            throw SwiftUsdShellError.invalidValue(
                "Failed to export material binding layer to \(outputURL.url.lastPathComponent)"
            )
        }
    }

    /// Authors a sparse material-unbinding edit layer using `UsdShadeMaterialBindingAPI`.
    ///
    /// `UnbindDirectBinding` blocks the direct binding relationship targets using
    /// OpenUSD's schema-owned semantics instead of hand-emitting relationship USDA.
    public func writeMaterialUnbindingLayer(
        outputURL: USDStageURL,
        primPath: USDPath
    ) throws {
        let editStagePtr = UsdStage.CreateInMemory(
            std.string("material_unbinding_edit.usda"),
            UsdStage.InitialLoadSet.LoadAll
        )
        guard editStagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(outputURL, diagnostic: "in-memory-stage")
        }
        let editStage = USDOverlay.Dereference(editStagePtr)
        let prim = editStage.OverridePrim(SdfPath(std.string(primPath.rawValue)))
        let bindingAPI = UsdShadeMaterialBindingAPI(prim)
        guard bindingAPI.UnbindDirectBinding(TfToken("")) else {
            throw SwiftUsdShellError.invalidValue(
                "Failed to clear material binding on \(primPath.rawValue)"
            )
        }

        guard editStage.Export(std.string(outputURL.url.path), false, SdfLayer.FileFormatArguments()) else {
            throw SwiftUsdShellError.invalidValue(
                "Failed to export material unbinding layer to \(outputURL.url.lastPathComponent)"
            )
        }
    }

    public func materialSurfaceShader(
        _ query: USDMaterialSurfaceShaderQuery
    ) throws -> USDMaterialSurfaceShader? {
        let stage = try self.stage(for: query.stageURL, loadPolicy: .loadNone)
        let prim = stage.GetPrimAtPath(SdfPath(std.string(query.materialPath.rawValue)))
        guard prim.IsValid() else { return nil }

        let material = UsdShadeMaterial(prim)
        guard material.GetPrim().IsValid() else { return nil }

        let shader = material.ComputeSurfaceSource(
            TfToken(std.string(query.renderContext.rawValue)),
            nil as UnsafeMutablePointer<TfToken>?,
            nil as UnsafeMutablePointer<UsdShadeAttributeType>?
        )
        let shaderPrim = shader.GetPrim()
        guard shaderPrim.IsValid() else { return nil }

        return USDMaterialSurfaceShader(
            shaderPath: USDPath(
                stableOwnedString(describing: shaderPrim.GetPath().GetAsString())
            ),
            shaderIdentifier: shaderIdentifier(shaderPrim)
        )
    }

    private func generateSparseUSDA(_ request: USDSparseLayerRequest) -> String {
        var lines: [String] = ["#usda 1.0"]
        if let doc = request.documentation, !doc.isEmpty {
            lines.append("# \(doc)")
        }
        let roots = sparsePrimTree(for: request.overrides)
        if !roots.isEmpty {
            lines.append("")
        }
        for root in roots {
            emitSparsePrimNode(root, indentLevel: 0, into: &lines)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func sparsePrimTree(for overrides: [USDSparseOverride]) -> [SparsePrimNode] {
        var roots: [SparsePrimNode] = []
        for override in overrides {
            let components = override.primPath.rawValue
                .split(separator: "/")
                .map(String.init)
                .filter { !$0.isEmpty }
            guard !components.isEmpty else { continue }
            insertSparseOverride(
                override,
                components: components,
                componentIndex: 0,
                into: &roots
            )
        }
        return roots
    }

    private func insertSparseOverride(
        _ override: USDSparseOverride,
        components: [String],
        componentIndex: Int,
        into nodes: inout [SparsePrimNode]
    ) {
        let component = components[componentIndex]
        let isTerminal = componentIndex == components.count - 1
        let specifier: USDSparsePrimSpecifier = isTerminal ? override.specifier : .over
        let nodeIndex = sparseNodeIndex(named: component, in: nodes)
        if let nodeIndex {
            nodes[nodeIndex].specifier = mergedSparseSpecifier(
                existing: nodes[nodeIndex].specifier,
                incoming: specifier
            )
            if isTerminal {
                nodes[nodeIndex].metadata.append(contentsOf: override.metadata)
                nodes[nodeIndex].attributes.append(contentsOf: override.attributes)
                nodes[nodeIndex].relationships.append(contentsOf: override.relationships)
                mergeSparseChildren(override.children, into: &nodes[nodeIndex].children)
            } else {
                insertSparseOverride(
                    override,
                    components: components,
                    componentIndex: componentIndex + 1,
                    into: &nodes[nodeIndex].children
                )
            }
        } else {
            var node = SparsePrimNode(name: component, specifier: specifier)
            if isTerminal {
                node.metadata = override.metadata
                node.attributes = override.attributes
                node.relationships = override.relationships
                node.children = sparseChildNodes(from: override.children)
            } else {
                insertSparseOverride(
                    override,
                    components: components,
                    componentIndex: componentIndex + 1,
                    into: &node.children
                )
            }
            nodes.append(node)
        }
    }

    private func sparseChildNodes(from children: [USDSparseChildPrim]) -> [SparsePrimNode] {
        var nodes: [SparsePrimNode] = []
        mergeSparseChildren(children, into: &nodes)
        return nodes
    }

    private func mergeSparseChildren(
        _ children: [USDSparseChildPrim],
        into nodes: inout [SparsePrimNode]
    ) {
        for child in children {
            if let nodeIndex = sparseNodeIndex(named: child.name, in: nodes) {
                nodes[nodeIndex].specifier = mergedSparseSpecifier(
                    existing: nodes[nodeIndex].specifier,
                    incoming: child.specifier
                )
                nodes[nodeIndex].metadata.append(contentsOf: child.metadata)
                nodes[nodeIndex].attributes.append(contentsOf: child.attributes)
                nodes[nodeIndex].relationships.append(contentsOf: child.relationships)
                mergeSparseChildren(child.children, into: &nodes[nodeIndex].children)
            } else {
                nodes.append(
                    SparsePrimNode(
                        name: child.name,
                        specifier: child.specifier,
                        metadata: child.metadata,
                        attributes: child.attributes,
                        relationships: child.relationships,
                        children: sparseChildNodes(from: child.children)
                    )
                )
            }
        }
    }

    private func sparseNodeIndex(named name: String, in nodes: [SparsePrimNode]) -> Int? {
        nodes.firstIndex { $0.name == name }
    }

    private func mergedSparseSpecifier(
        existing: USDSparsePrimSpecifier,
        incoming: USDSparsePrimSpecifier
    ) -> USDSparsePrimSpecifier {
        switch (existing, incoming) {
        case (.over, .over):
            return .over
        case (.def, .over):
            return existing
        case (.over, .def):
            return incoming
        case (.def(let existingType), .def(let incomingType)):
            return .def(typeName: existingType ?? incomingType)
        }
    }

    private func emitSparsePrimNode(
        _ node: SparsePrimNode,
        indentLevel: Int,
        into lines: inout [String]
    ) {
        let indent = String(repeating: "    ", count: indentLevel)
        lines.append(
            "\(indent)\(sparseSpecifierKeyword(node.specifier)) \"\(escapeUSDAPathComponent(node.name))\""
        )
        emitSparsePrimMetadata(node.metadata, indent: indent, into: &lines)
        lines.append("\(indent){")
        emitSparsePrimBody(
            attributes: node.attributes,
            relationships: node.relationships,
            children: node.children,
            indent: indent + "    ",
            into: &lines
        )
        lines.append("\(indent)}")
    }

    private func emitSparsePrimMetadata(
        _ metadata: [USDSparseMetadata],
        indent: String,
        into lines: inout [String]
    ) {
        guard !metadata.isEmpty else { return }
        lines.append("\(indent)(")
        for entry in metadata {
            lines.append("\(indent)    \(formatSparseMetadataEntry(entry))")
        }
        lines.append("\(indent))")
    }

    private func formatSparseMetadataEntry(_ entry: USDSparseMetadata) -> String {
        let key = entry.key.rawValue
        switch entry.opinion {
        case .value(let v):
            return "\(key) = \(formatMetadataAtomicValue(v))"
        case .prepend(let items):
            return "prepend \(key) = \(formatListOpItems(items))"
        case .append(let items):
            return "append \(key) = \(formatListOpItems(items))"
        case .delete(let items):
            return "delete \(key) = \(formatListOpItems(items))"
        case .explicitList(let items):
            return "\(key) = \(formatListOpItems(items))"
        }
    }

    private func formatMetadataAtomicValue(_ value: USDMetadataValue) -> String {
        switch value {
        case .bool(let b):
            return b ? "true" : "false"
        case .string(let s):
            return "\"\(escapeUSDAStringLiteral(s))\""
        case .token(let t):
            return "\"\(t.rawValue)\""
        case .asset(let p):
            return "@\(p.rawValue)@"
        case .variantSelection(let entries):
            if entries.isEmpty { return "{}" }
            let parts = entries.map { entry -> String in
                if let sel = entry.selection {
                    return "string \(entry.variantSet) = \"\(escapeUSDAStringLiteral(sel))\""
                } else {
                    return "string \(entry.variantSet) = \"\""
                }
            }
            return "{ " + parts.joined(separator: "; ") + " }"
        }
    }

    private func formatListOpItems(_ items: [USDListOpItem]) -> String {
        let parts = items.map(formatListOpItem)
        return "[" + parts.joined(separator: ", ") + "]"
    }

    private func formatListOpItem(_ item: USDListOpItem) -> String {
        switch item {
        case .token(let t):     return "\"\(t.rawValue)\""
        case .property(let s):  return "\"\(s)\""
        case .asset(let p):     return "@\(p.rawValue)@"
        case .path(let p):      return "<\(p.rawValue)>"
        }
    }

    private func escapeUSDAStringLiteral(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func emitSparsePrimBody(
        attributes: [USDSparseAttributeOverride],
        relationships: [USDSparseRelationship],
        children: [SparsePrimNode],
        indent: String,
        into lines: inout [String]
    ) {
        for attr in attributes {
            switch attr.opinion {
            case .clear:
                lines.append("\(indent)\(attr.usdTypeName) \(attr.name) = None")
                lines.append("\(indent)\(attr.usdTypeName) \(attr.name).connect = None")
            case .value(let value):
                lines.append("\(indent)\(attr.usdTypeName) \(attr.name) = \(value.usdaLiteral)")
            case .valueClearingConnections(let value):
                lines.append("\(indent)\(attr.usdTypeName) \(attr.name) = \(value.usdaLiteral)")
                lines.append("\(indent)\(attr.usdTypeName) \(attr.name).connect = None")
            case .connection(let target):
                lines.append(
                    "\(indent)\(attr.usdTypeName) \(attr.name).connect = <\(target.rawValue)>"
                )
            case .declare:
                lines.append("\(indent)\(attr.usdTypeName) \(attr.name)")
            }
        }
        for rel in relationships {
            if let targets = rel.targets {
                let targetList = targets.map { "<\($0.rawValue)>" }.joined(separator: ", ")
                if targets.count == 1 {
                    lines.append("\(indent)rel \(rel.name) = \(targetList)")
                } else {
                    lines.append("\(indent)rel \(rel.name) = [\(targetList)]")
                }
            } else {
                lines.append("\(indent)rel \(rel.name) = []")
            }
        }
        for child in children {
            emitSparsePrimNode(child, indentLevel: indent.count / 4, into: &lines)
        }
    }

    private func sparseSpecifierKeyword(_ specifier: USDSparsePrimSpecifier) -> String {
        switch specifier {
        case .over:
            return "over"
        case .def(let typeName):
            if let typeName, !typeName.isEmpty {
                return "def \(typeName)"
            }
            return "def"
        }
    }

    private func escapeUSDAPathComponent(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Blocks MaterialX outputs and deactivates MaterialX helper shaders on
    /// every `Material` prim in the stage, then saves the root layer in place.
    ///
    /// This is the canonical replacement for the legacy USDTools viewport
    /// stage preparation that prevented MaterialX outputs from masking
    /// `UsdPreviewSurface` outputs and stripped helper shaders that
    /// RealityKit cannot consume. The operation uses canonical UsdShade
    /// semantics — `UsdAttribute.Block()` on `outputs:mtlx:*` and
    /// `inputs:*:varname` attributes, and `UsdPrim.SetActive(false)` on
    /// `Lookup_st`/`*_mtlx` helper shader children.
    ///
    /// The stage is opened with `loadAll` so MaterialX prims resolved through
    /// payloads are visible to the typed traversal. Opinions are authored on
    /// the root layer (the stage's default edit target) and then saved.
    public func prepareViewportMaterialXBlocking(
        stageURL: USDStageURL
    ) throws -> USDViewportMaterialXBlockingResult {
        let stage = try self.stage(for: stageURL, loadPolicy: .loadAll)

        let mtlxOutputNames: [String] = [
            "outputs:mtlx:surface",
            "outputs:mtlx:displacement",
            "outputs:mtlx:volume",
        ]

        var blockedOutputCount = 0
        var blockedMaterialInputCount = 0
        var deactivatedShaderCount = 0

        for prim in stage.Traverse().swiftSequence {
            guard stableOwnedString(describing: prim.GetTypeName().GetString()) == "Material" else {
                continue
            }

            let hasMaterialXOutputs = mtlxOutputNames.contains { outputName in
                prim.GetAttribute(TfToken(std.string(outputName))).IsValid()
            }
            let hasMaterialXChildren = prim.GetChildren().swiftSequence.contains { child in
                guard stableOwnedString(describing: child.GetTypeName().GetString()) == "Shader" else {
                    return false
                }
                let childName = stableOwnedString(describing: child.GetName().GetString())
                return childName == "Lookup_st" || childName.contains("_mtlx")
            }
            guard hasMaterialXOutputs || hasMaterialXChildren else { continue }

            for outputName in mtlxOutputNames {
                let attr = prim.GetAttribute(TfToken(std.string(outputName)))
                guard attr.IsValid() else { continue }
                attr.Block()
                blockedOutputCount += 1
            }

            for attr in prim.GetAttributes() {
                let attrName = stableOwnedString(describing: attr.GetName().GetString())
                guard attrName.hasPrefix("inputs:"),
                      attrName.hasSuffix(":varname")
                else { continue }
                attr.Block()
                blockedMaterialInputCount += 1
            }

            for child in prim.GetChildren().swiftSequence {
                guard stableOwnedString(describing: child.GetTypeName().GetString()) == "Shader" else {
                    continue
                }
                let childName = stableOwnedString(describing: child.GetName().GetString())
                guard childName == "Lookup_st" || childName.contains("_mtlx") else { continue }
                var mutableChild = child
                _ = mutableChild.SetActive(false)
                deactivatedShaderCount += 1
            }
        }

        let rootLayerHandle = stage.GetRootLayer()
        guard Bool(rootLayerHandle) else {
            throw SwiftUsdShellError.invalidValue(
                "MaterialX blocking: root layer is not accessible for \(stageURL.url.lastPathComponent)"
            )
        }
        let rootLayer = USDOverlay.Dereference(rootLayerHandle)
        guard rootLayer.Save(false) else {
            throw SwiftUsdShellError.invalidValue(
                "MaterialX blocking: failed to save root layer for \(stageURL.url.lastPathComponent)"
            )
        }

        return USDViewportMaterialXBlockingResult(
            blockedOutputCount: blockedOutputCount,
            blockedMaterialInputCount: blockedMaterialInputCount,
            deactivatedShaderCount: deactivatedShaderCount
        )
    }

    /// Authors missing `UsdUVTexture` defaults required for normal-map
    /// behavior. For each `UsdUVTexture` shader spec whose `outputs:rgb` is
    /// declared as `normal3f`, the helper authors any of the missing
    /// canonical defaults — `inputs:sourceColorSpace = "raw"`,
    /// `inputs:bias = (-1,-1,-1,0)`, and `inputs:scale = (2,2,2,1)` — using
    /// typed `SdfAttributeSpec.New` + `SetDefaultValue` calls on the root
    /// layer. Existing authored values are not overwritten.
    public func authorUsdUVTextureNormalMapDefaults(
        stageURL: USDStageURL
    ) throws -> USDViewportNormalMapNormalizationResult {
        let stage = try self.stage(for: stageURL, loadPolicy: .loadAll)
        let rootLayerHandle = stage.GetRootLayer()
        guard Bool(rootLayerHandle) else {
            throw SwiftUsdShellError.invalidValue(
                "Normal-map normalization: root layer is not accessible for \(stageURL.url.lastPathComponent)"
            )
        }
        let rootLayer = USDOverlay.Dereference(rootLayerHandle)

        var normalizedShaderCount = 0
        authorNormalMapDefaults(
            primSpec: rootLayer.GetPseudoRoot(),
            normalizedShaderCount: &normalizedShaderCount
        )

        if normalizedShaderCount > 0 {
            guard rootLayer.Save(false) else {
                throw SwiftUsdShellError.invalidValue(
                    "Normal-map normalization: failed to save root layer for \(stageURL.url.lastPathComponent)"
                )
            }
        }

        return USDViewportNormalMapNormalizationResult(
            normalizedShaderCount: normalizedShaderCount
        )
    }

}

/// Walks `SdfPrimSpec` children recursively and authors missing
/// `UsdUVTexture` normal-map defaults on layer specs whose authored
/// `outputs:rgb` is `normal3f`. Existing authored opinions are preserved.
///
/// Canonical OpenUSD: traversal uses `SdfPrimSpec.GetNameChildren()`, shader
/// identification uses the typed `info:id` attribute spec, and the three
/// defaults are authored via typed `SdfAttributeSpec.New` +
/// `SetDefaultValue`. No string or composed-stage parsing.
private func authorNormalMapDefaults(
    primSpec handle: SdfPrimSpecHandle,
    normalizedShaderCount: inout Int
) {
    guard Bool(handle) else { return }
    let primSpec = handle.pointee

    if isShaderPrimSpec(primSpec),
       let identifier = shaderIdentifier(primSpec),
       identifier == "UsdUVTexture",
       let rgbOutput = attributeSpec(named: "outputs:rgb", on: primSpec),
       rgbOutput.GetTypeName() == SdfValueTypeName.Normal3f {

        var authoredAny = false

        if attributeSpec(named: "inputs:sourceColorSpace", on: primSpec) == nil {
            let newSpec = SdfAttributeSpec.New(
                handle,
                std.string("inputs:sourceColorSpace"),
                SdfValueTypeName.Token,
                SdfVariability.SdfVariabilityUniform,
                false
            )
            if Bool(newSpec) {
                _ = newSpec.pointee.SetDefaultValue(VtValue(TfToken(std.string("raw"))))
                authoredAny = true
            }
        }

        if attributeSpec(named: "inputs:bias", on: primSpec) == nil {
            let newSpec = SdfAttributeSpec.New(
                handle,
                std.string("inputs:bias"),
                SdfValueTypeName.Float4,
                SdfVariability.SdfVariabilityVarying,
                false
            )
            if Bool(newSpec) {
                _ = newSpec.pointee.SetDefaultValue(VtValue(pxr.GfVec4f(-1, -1, -1, 0)))
                authoredAny = true
            }
        }

        if attributeSpec(named: "inputs:scale", on: primSpec) == nil {
            let newSpec = SdfAttributeSpec.New(
                handle,
                std.string("inputs:scale"),
                SdfValueTypeName.Float4,
                SdfVariability.SdfVariabilityVarying,
                false
            )
            if Bool(newSpec) {
                _ = newSpec.pointee.SetDefaultValue(VtValue(pxr.GfVec4f(2, 2, 2, 1)))
                authoredAny = true
            }
        }

        if authoredAny {
            normalizedShaderCount += 1
        }
    }

    for child in primSpec.GetNameChildren() {
        authorNormalMapDefaults(
            primSpec: child,
            normalizedShaderCount: &normalizedShaderCount
        )
    }
}

private func collectDiagnostics(_ body: () -> Void) -> [USDDiagnostic] {
    USDOverlay.withTfErrorMark { mark in
        body()
        return mark.errors.map {
            USDDiagnostic(
                severity: .error,
                code: "",
                message: String($0.GetCommentary())
            )
        }
    }
}

private func openUSDLoadPolicy(_ policy: USDLoadPolicy) -> UsdStage.InitialLoadSet {
    switch policy {
    case .loadAll:
        .LoadAll
    case .loadNone:
        .LoadNone
    }
}

private func openUSDTimeCode(_ timeCode: USDTimeCode) -> UsdTimeCode {
    switch timeCode.kind {
    case .default:
        UsdTimeCode.Default()
    case .earliest:
        UsdTimeCode.EarliestTime()
    case .numeric(let value):
        UsdTimeCode(value)
    }
}

private func tokenOrNil(_ token: TfToken) -> USDToken? {
    let value = stableOwnedString(describing: token.GetString())
    return value.isEmpty ? nil : USDToken(value)
}

private func primSpecifier(_ specifier: SdfSpecifier) -> USDPrimSpecifier {
    switch specifier {
    case .SdfSpecifierDef:
        .def
    case .SdfSpecifierOver:
        .over
    case .SdfSpecifierClass:
        .class_
    default:
        .unknown
    }
}

private func visibility(_ prim: UsdPrim) -> USDToken? {
    let imageable = UsdGeomImageable(prim)
    guard USDOverlay.GetPrim(imageable).IsValid() else { return nil }
    var value = VtValue()
    guard imageable.GetVisibilityAttr().Get(&value) else { return nil }
    let token: TfToken = value.Get()
    return tokenOrNil(token)
}

private func purpose(_ prim: UsdPrim) -> USDToken? {
    let imageable = UsdGeomImageable(prim)
    guard USDOverlay.GetPrim(imageable).IsValid() else { return nil }
    var value = VtValue()
    guard imageable.GetPurposeAttr().Get(&value) else { return nil }
    let token: TfToken = value.Get()
    return tokenOrNil(token)
}

private func modelKind(_ prim: UsdPrim) -> USDToken? {
    var kind = TfToken()
    guard UsdModelAPI(prim).GetKind(&kind) else { return nil }
    return tokenOrNil(kind)
}

private func xformOpKind(for token: String) -> USDAuthoredXformOpKind {
    switch token {
    case "xformOp:translate":
        .translate
    case "xformOp:rotateXYZ":
        .rotateXYZ
    case "xformOp:rotateX":
        .rotateX
    case "xformOp:rotateY":
        .rotateY
    case "xformOp:rotateZ":
        .rotateZ
    case "xformOp:scale":
        .scale
    case "xformOp:translate:pivot":
        .pivot
    case "xformOp:orient":
        .orient
    case "xformOp:transform":
        .transform
    default:
        .custom(token: token)
    }
}

private func sdfValueTypeName(named name: String) -> SdfValueTypeName? {
    switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "bool":
        SdfValueTypeName.Bool
    case "uchar":
        SdfValueTypeName.UChar
    case "int":
        SdfValueTypeName.Int
    case "uint":
        SdfValueTypeName.UInt
    case "int64":
        SdfValueTypeName.Int64
    case "uint64":
        SdfValueTypeName.UInt64
    case "half":
        SdfValueTypeName.Half
    case "float":
        SdfValueTypeName.Float
    case "double":
        SdfValueTypeName.Double
    case "timecode":
        SdfValueTypeName.TimeCode
    case "string":
        SdfValueTypeName.String
    case "token":
        SdfValueTypeName.Token
    case "asset":
        SdfValueTypeName.Asset
    case "float2":
        SdfValueTypeName.Float2
    case "float3":
        SdfValueTypeName.Float3
    case "float4":
        SdfValueTypeName.Float4
    case "double2":
        SdfValueTypeName.Double2
    case "double3":
        SdfValueTypeName.Double3
    case "double4":
        SdfValueTypeName.Double4
    case "point3f":
        SdfValueTypeName.Point3f
    case "point3d":
        SdfValueTypeName.Point3d
    case "vector3f":
        SdfValueTypeName.Vector3f
    case "vector3d":
        SdfValueTypeName.Vector3d
    case "normal3f":
        SdfValueTypeName.Normal3f
    case "normal3d":
        SdfValueTypeName.Normal3d
    case "color3f":
        SdfValueTypeName.Color3f
    case "color3d":
        SdfValueTypeName.Color3d
    case "color4f":
        SdfValueTypeName.Color4f
    case "color4d":
        SdfValueTypeName.Color4d
    case "matrix4d":
        SdfValueTypeName.Matrix4d
    default:
        nil
    }
}

private func xformOpPrecision(for attr: UsdAttribute) -> USDAuthoredXformOpPrecision {
    let typeName = attr.GetTypeName()
    if typeName == SdfValueTypeName.Double
        || typeName == SdfValueTypeName.Double3
        || typeName == SdfValueTypeName.Point3d
        || typeName == SdfValueTypeName.Vector3d
        || typeName == SdfValueTypeName.Quatd
        || typeName == SdfValueTypeName.Matrix4d {
        return .double
    }

    if typeName == SdfValueTypeName.Half
        || typeName == SdfValueTypeName.Half3
        || typeName == SdfValueTypeName.Point3h
        || typeName == SdfValueTypeName.Vector3h
        || typeName == SdfValueTypeName.Quath {
        return .half
    }

    if typeName == SdfValueTypeName.Float
        || typeName == SdfValueTypeName.Float3
        || typeName == SdfValueTypeName.Point3f
        || typeName == SdfValueTypeName.Vector3f
        || typeName == SdfValueTypeName.Quatf {
        return .float
    }

    return .unknown
}

private func isSupportedXformToken(_ token: String) -> Bool {
    switch token {
    case "xformOp:translate",
         "xformOp:rotateXYZ",
         "xformOp:rotateX",
         "xformOp:rotateY",
         "xformOp:rotateZ",
         "xformOp:scale",
         "xformOp:translate:pivot",
         "!invert!xformOp:translate:pivot":
        true
    default:
        false
    }
}

private func isPivotStartToken(_ token: String) -> Bool {
    token == "xformOp:translate:pivot"
}

private func isInversePivotToken(_ token: String) -> Bool {
    token == "!invert!xformOp:translate:pivot"
}

private func compositionArc(
    kind: USDCompositionArcKind,
    assetPath: String,
    primPath: String,
    layerOffset: SdfLayerOffset
) -> USDCompositionArcSummary {
    USDCompositionArcSummary(
        kind: kind,
        assetPath: assetPath.isEmpty ? nil : USDAssetPath(assetPath),
        primPath: primPath.isEmpty ? nil : USDPath(primPath),
        layerOffset: USDLayerOffset(
            offset: layerOffset.GetOffset(),
            scale: layerOffset.GetScale()
        ),
        isInternal: assetPath.isEmpty
    )
}

private func rewrittenAttributeUSDValue(
    from attr: UsdAttribute,
    sourceTypeName: SdfValueTypeName,
    targetTypeName: SdfValueTypeName
) -> USDValue? {
    if sourceTypeName == SdfValueTypeName.Token, targetTypeName == SdfValueTypeName.String {
        var token = TfToken()
        guard attr.Get(&token, UsdTimeCode.Default()) else { return nil }
        return .string(stableOwnedString(describing: token.GetString()))
    }

    if sourceTypeName == SdfValueTypeName.String, targetTypeName == SdfValueTypeName.Token {
        var stringValue = std.string()
        guard attr.Get(&stringValue, UsdTimeCode.Default()) else { return nil }
        return .token(USDToken(stableOwnedString(describing: stringValue)))
    }

    var value = VtValue()
    guard attr.Get(&value, UsdTimeCode.Default()) else { return nil }
    return convertVtValueToUSDValue(value)
}

private func rewrittenAttributeValue(
    from attr: UsdAttribute,
    sourceTypeName: SdfValueTypeName,
    targetTypeName: SdfValueTypeName
) -> VtValue? {
    if sourceTypeName == SdfValueTypeName.Token, targetTypeName == SdfValueTypeName.String {
        var token = TfToken()
        guard attr.Get(&token, UsdTimeCode.Default()) else { return nil }
        return VtValue(token.GetString())
    }

    if sourceTypeName == SdfValueTypeName.String, targetTypeName == SdfValueTypeName.Token {
        var stringValue = std.string()
        guard attr.Get(&stringValue, UsdTimeCode.Default()) else { return nil }
        return VtValue(TfToken(stringValue))
    }

    return nil
}

private func collectShaderInputTypeRewrites(
    primSpec handle: SdfPrimSpecHandle,
    inputAttrName: String,
    currentTypeName: SdfValueTypeName,
    targetTypeName: String,
    shaderIdentifierPrefix: String,
    rewrites: inout [USDAttributeTypeRewrite]
) {
    guard Bool(handle) else { return }
    let primSpec = handle.pointee

    if isShaderPrimSpec(primSpec),
       let identifier = shaderIdentifier(primSpec),
       identifier.hasPrefix(shaderIdentifierPrefix) {
        if let attrSpec = attributeSpec(named: inputAttrName, on: primSpec),
           attrSpec.GetTypeName() == currentTypeName {
            rewrites.append(
                USDAttributeTypeRewrite(
                    primPath: stableOwnedString(describing: primSpec.GetPath().GetAsString()),
                    attributeName: inputAttrName,
                    targetTypeName: targetTypeName
                )
            )
        }
    }

    for child in primSpec.GetNameChildren() {
        collectShaderInputTypeRewrites(
            primSpec: child,
            inputAttrName: inputAttrName,
            currentTypeName: currentTypeName,
            targetTypeName: targetTypeName,
            shaderIdentifierPrefix: shaderIdentifierPrefix,
            rewrites: &rewrites
        )
    }
}

private func isShaderPrimSpec(_ primSpec: SdfPrimSpec) -> Bool {
    stableOwnedString(describing: primSpec.GetTypeName()) == "Shader"
}

private func attributeSpec(named name: String, on primSpec: SdfPrimSpec) -> SdfAttributeSpec? {
    for attrSpecHandle in primSpec.GetAttributes() {
        let attrSpec = attrSpecHandle.pointee
        if stableOwnedString(describing: attrSpec.GetName()) == name {
            return attrSpec
        }
    }
    return nil
}

private func shaderIdentifier(_ primSpec: SdfPrimSpec) -> String? {
    guard let attr = attributeSpec(named: "info:id", on: primSpec) else { return nil }
    guard attr.HasDefaultValue() else { return nil }
    var value = attr.GetDefaultValue()

    if attr.GetTypeName() == SdfValueTypeName.Token {
        let token = value.Get() as TfToken
        let raw = stableOwnedString(describing: token.GetString())
        return raw.isEmpty ? nil : raw
    }

    if attr.GetTypeName() == SdfValueTypeName.String {
        let raw = stableOwnedString(describing: value.Get() as std.string)
        return raw.isEmpty ? nil : raw
    }

    return nil
}

private func rewriteAttributeSpecType(
    _ handle: SdfAttributeSpecHandle,
    in layer: SdfLayer,
    targetTypeName: SdfValueTypeName
) -> Bool {
    guard Bool(handle) else { return false }
    let attrSpec = handle.pointee
    let owner = layer.GetPrimAtPath(attrSpec.GetPath().GetPrimPath())
    guard Bool(owner) else { return false }

    let sourceTypeName = attrSpec.GetTypeName()
    let variability = attrSpec.GetVariability()
    let isCustom = attrSpec.IsCustom()
    let name = stableOwnedString(describing: attrSpec.GetName())
    let rewrittenDefault = rewrittenAttributeSpecDefaultValue(
        attrSpec,
        sourceTypeName: sourceTypeName,
        targetTypeName: targetTypeName
    )
    let fallbackDefault = attrSpec.HasDefaultValue() ? attrSpec.GetDefaultValue() : nil

    owner.pointee.RemoveProperty(handle)

    let rewritten = SdfAttributeSpec.New(
        owner,
        std.string(name),
        targetTypeName,
        variability,
        isCustom
    )
    guard Bool(rewritten) else { return false }

    if let rewrittenDefault {
        return rewritten.pointee.SetDefaultValue(rewrittenDefault)
    }
    if let fallbackDefault {
        return rewritten.pointee.SetDefaultValue(fallbackDefault)
    }
    return true
}

private func rewrittenAttributeSpecDefaultValue(
    _ attrSpec: SdfAttributeSpec,
    sourceTypeName: SdfValueTypeName,
    targetTypeName: SdfValueTypeName
) -> VtValue? {
    guard attrSpec.HasDefaultValue() else { return nil }
    var value = attrSpec.GetDefaultValue()

    if sourceTypeName == SdfValueTypeName.Token, targetTypeName == SdfValueTypeName.String {
        let token = value.Get() as TfToken
        return VtValue(token.GetString())
    }

    if sourceTypeName == SdfValueTypeName.String, targetTypeName == SdfValueTypeName.Token {
        let stringValue = value.Get() as std.string
        return VtValue(TfToken(stringValue))
    }

    return nil
}

private func shaderInputBaseName(_ inputName: String) -> String {
    if inputName.hasPrefix("inputs:") {
        return String(inputName.dropFirst("inputs:".count))
    }
    return inputName
}

private func convertVtValueToUSDValue(_ value: VtValue) -> USDValue? {
    if value.IsHolding(Bool.self) {
        return .bool(value.Get() as Bool)
    }

    if value.IsHolding(Double.self) {
        return .double(value.Get() as Double)
    }
    if value.IsHolding(Float.self) {
        return .double(Double(value.Get() as Float))
    }

    if value.IsHolding(Int.self) {
        return .int(Int64(value.Get() as Int))
    }
    if value.IsHolding(Int64.self) {
        return .int(value.Get() as Int64)
    }
    if value.IsHolding(Int32.self) {
        return .int(Int64(value.Get() as Int32))
    }

    if value.IsHolding(TfToken.self) {
        let token = value.Get() as TfToken
        return .token(USDToken(String(token.GetString())))
    }
    if value.IsHolding(std.string.self) {
        return .string(String(value.Get() as std.string))
    }
    if value.IsHolding(SdfAssetPath.self) {
        let assetPath = value.Get() as SdfAssetPath
        let authored = String(assetPath.GetAssetPath())
        if authored.isEmpty {
            let resolved = String(assetPath.GetResolvedPath())
            return resolved.isEmpty ? nil : .assetPath(USDAssetPath(resolved))
        }
        return .assetPath(USDAssetPath(authored))
    }

    if value.IsHolding(GfVec2d.self) {
        let v = value.Get() as GfVec2d
        return .vector2(USDVector2(x: v[0], y: v[1]))
    }
    if value.IsHolding(GfVec2f.self) {
        let v = value.Get() as GfVec2f
        return .vector2(USDVector2(x: Double(v[0]), y: Double(v[1])))
    }
    if value.IsHolding(GfVec2i.self) {
        let v = value.Get() as GfVec2i
        return .vector2(USDVector2(x: Double(v[0]), y: Double(v[1])))
    }

    if value.IsHolding(GfVec3d.self) {
        let v = value.Get() as GfVec3d
        return .vector3(USDVector3(x: v[0], y: v[1], z: v[2]))
    }
    if value.IsHolding(GfVec3f.self) {
        let v = value.Get() as GfVec3f
        return .vector3(USDVector3(x: Double(v[0]), y: Double(v[1]), z: Double(v[2])))
    }
    if value.IsHolding(GfVec3i.self) {
        let v = value.Get() as GfVec3i
        return .vector3(USDVector3(x: Double(v[0]), y: Double(v[1]), z: Double(v[2])))
    }

    if value.IsHolding(GfVec4d.self) {
        let v = value.Get() as GfVec4d
        return .vector4(USDVector4(x: v[0], y: v[1], z: v[2], w: v[3]))
    }
    if value.IsHolding(GfVec4f.self) {
        let v = value.Get() as GfVec4f
        return .vector4(USDVector4(x: Double(v[0]), y: Double(v[1]), z: Double(v[2]), w: Double(v[3])))
    }
    if value.IsHolding(GfVec4i.self) {
        let v = value.Get() as GfVec4i
        return .vector4(USDVector4(x: Double(v[0]), y: Double(v[1]), z: Double(v[2]), w: Double(v[3])))
    }

    return nil
}

private func stableOwnedString<T>(describing value: T) -> String {
    String(describing: value)
}

// MARK: - Canonical material binding cleanup and append

public extension OpenUSDStageRuntime {
    /// Returns the names of authored properties on `primPath` that are invalid
    /// `material:binding` opinions (i.e. authored as attributes rather than
    /// relationships).
    ///
    /// Canonical OpenUSD: enumerates `UsdPrim.GetAttributes()` and matches the
    /// exact authored name `material:binding` or any namespaced descendant
    /// `material:binding:*`. Valid material bindings are relationships, never
    /// attributes; anything matching this filter is an authoring mistake and
    /// safe to delete. This restores parity with the legacy USDTools cleanup
    /// which deleted both `material:binding` and `material:binding:*`
    /// attributes.
    func discoverInvalidMaterialBindingPropertyNames(
        stageURL: USDStageURL,
        primPath: USDPath
    ) throws -> [String] {
        let stagePtr = UsdStage.Open(
            std.string(stageURL.url.path),
            UsdStage.InitialLoadSet.LoadNone
        )
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stageURL, diagnostic: "discover-invalid-binding")
        }
        let stage = USDOverlay.Dereference(stagePtr)
        let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
        guard prim.IsValid() else { return [] }
        var names: [String] = []
        for attr in prim.GetAttributes() {
            let raw = stableOwnedString(describing: attr.GetName().GetString())
            if raw == "material:binding" || raw.hasPrefix("material:binding:") {
                names.append(raw)
            }
        }
        return names.sorted()
    }

    /// Appends a canonical `UsdShadeMaterialBindingAPI.Bind` opinion onto an
    /// existing exported sparse layer file at `layerURL`.
    ///
    /// This is intended for compositional flows (for example OpenUSDKit
    /// material authoring) where a sparse layer that defines a `Material` has
    /// already been written and the caller now needs to author the binding
    /// relationship using the canonical schema API instead of hand-authoring
    /// raw `material:binding` sparse relationships. The binding
    /// relationship name, purpose, and binding-strength metadata semantics are
    /// owned by OpenUSD's `UsdShadeMaterialBindingAPI`.
    func appendCanonicalMaterialBindingToLayer(
        layerURL: USDStageURL,
        primPath: USDPath,
        materialPath: USDPath,
        strength: USDMaterialBindingStrength = .fallbackStrength
    ) throws {
        let stagePtr = UsdStage.Open(
            std.string(layerURL.url.path),
            UsdStage.InitialLoadSet.LoadAll
        )
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(layerURL, diagnostic: "append-binding")
        }
        let stage = USDOverlay.Dereference(stagePtr)
        let prim = stage.OverridePrim(SdfPath(std.string(primPath.rawValue)))
        let materialPrim = stage.OverridePrim(SdfPath(std.string(materialPath.rawValue)))

        let bindingAPI = UsdShadeMaterialBindingAPI.Apply(prim)
        let material = UsdShadeMaterial(materialPrim)
        let strengthToken = TfToken(
            std.string(strength == .fallbackStrength ? "fallbackStrength" : strength.rawValue)
        )
        guard bindingAPI.Bind(material, strengthToken, TfToken("")) else {
            throw SwiftUsdShellError.invalidValue(
                "Failed to bind material \(materialPath.rawValue) to \(primPath.rawValue)"
            )
        }

        guard stage.Export(std.string(layerURL.url.path), false, SdfLayer.FileFormatArguments()) else {
            throw SwiftUsdShellError.invalidValue(
                "Failed to export material binding into \(layerURL.url.lastPathComponent)"
            )
        }
    }
}
