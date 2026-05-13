import CxxStdlib
import Foundation
import OpenUSD
import SwiftUsdShell

typealias USDOverlay = OpenUSD.Overlay
typealias pxr = pxrInternal_v0_26_3__pxrReserved__

typealias UsdStage = pxr.UsdStage
typealias UsdStageRefPtr = pxr.UsdStageRefPtr
typealias UsdPrim = pxr.UsdPrim
typealias UsdRelationship = pxr.UsdRelationship
typealias UsdAttribute = pxr.UsdAttribute
typealias UsdTimeCode = pxr.UsdTimeCode
typealias UsdGeomImageable = pxr.UsdGeomImageable
typealias UsdGeomMesh = pxr.UsdGeomMesh
typealias UsdGeomXformCommonAPI = pxr.UsdGeomXformCommonAPI
typealias UsdShadeConnectableAPI = pxr.UsdShadeConnectableAPI
typealias SdfReference = pxr.SdfReference
typealias SdfLayerOffset = pxr.SdfLayerOffset
typealias VtDictionary = pxr.VtDictionary
typealias SdfChangeBlock = pxr.SdfChangeBlock
typealias UsdShadeInput = pxr.UsdShadeInput
typealias UsdShadeMaterial = pxr.UsdShadeMaterial
typealias UsdShadeMaterialBindingAPI = pxr.UsdShadeMaterialBindingAPI
typealias UsdShadeShader = pxr.UsdShadeShader
typealias UsdModelAPI = pxr.UsdModelAPI
typealias TfToken = pxr.TfToken
typealias SdfPath = pxr.SdfPath
typealias SdfAssetPath = pxr.SdfAssetPath
typealias SdfPathVector = pxr.SdfPathVector
typealias SdfLayerOffset = pxr.SdfLayerOffset
typealias SdfSpecifier = pxr.SdfSpecifier
typealias SdfValueTypeName = pxr.SdfValueTypeName
typealias GfVec3d = pxr.GfVec3d
typealias GfVec3f = pxr.GfVec3f
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

/// Mechanical runtime adapter that answers SwiftUsdShell requests with OpenUSD.
///
/// This target may import SwiftUsd/OpenUSD. The base SwiftUsdShell target must
/// remain independent from this adapter.
public actor OpenUSDStageRuntime: USDStageRuntime {
    private var stages: [USDStageURL: UsdStage] = [:]
    private var stageModificationTimes: [USDStageURL: TimeInterval] = [:]

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
            materials: request.options.includeMaterialSummaries
                ? materialSummaries(stage.GetPseudoRoot())
                : [],
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
            materialBinding: request.options.includeMaterialBinding
                ? materialBindingInfo(for: prim, selectedPath: request.primPath)
                : nil,
            materialSummary: request.options.includeMaterialSummary
                ? materialSummary(for: prim, stage: stage)
                : nil,
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
            let attr = prim.GetAttribute(TfToken("familyType"))
            if attr.IsValid() {
                attr.Set(VtValue(TfToken(std.string(familyType.rawValue))), UsdTimeCode.Default())
            } else {
                let created = prim.CreateAttribute(
                    TfToken("familyType"), SdfValueTypeName.Token, false,
                    SdfVariability.SdfVariabilityUniform
                )
                created.Set(VtValue(TfToken(std.string(familyType.rawValue))), UsdTimeCode.Default())
            }
            return USDEditResult(refreshHints: USDEditRefreshHints(refreshInspector: true))

        case .save(let stageURL):
            let stage = try stage(for: stageURL, loadPolicy: .loadAll)
            stage.Save()
            return USDEditResult(refreshHints: USDEditRefreshHints(refreshInspector: false))
        }
    }

    nonisolated public func probeCapabilities() -> USDRuntimeCapabilities {
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

    nonisolated private func probeAppleTextureConverter() -> Bool {
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

    nonisolated public func registerPlugin(at url: USDStageURL) -> Bool {
        let pluginPath = std.string(url.url.path)
        let plugins = pxr.PlugRegistry.GetInstance().RegisterPlugins(pluginPath)
        return !plugins.empty()
    }

    nonisolated public func remapSkeletonPaths(
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

    nonisolated public func makeRCPReady(stage: USDStageURL, primPath: USDPath) throws -> USDStageURL {
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



    nonisolated public func observeStageChanges(
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

    nonisolated public func sceneStatistics(stage: USDStageURL) throws -> USDGeometryStatistics {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        return geometryStatistics(USDOverlay.Dereference(stagePtr).GetPseudoRoot())
    }

    nonisolated public func primStatistics(
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

    nonisolated public func modelInfo(stage: USDStageURL) throws -> USDModelInfo {
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
                let dpStr = String(dp.GetAsString())
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

    nonisolated public func variantDescriptors(
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

    nonisolated public func exportVariantCombination(
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

    nonisolated public func materialSummaries(stage: USDStageURL) throws -> [USDMaterialSummary] {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        return materialSummaries(USDOverlay.Dereference(stagePtr).GetPseudoRoot())
    }




    nonisolated public func primHierarchy(stage: USDStageURL) throws -> USDPrimTree? {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        let pseudoRoot = USDOverlay.Dereference(stagePtr).GetPseudoRoot()
        for child in pseudoRoot.GetChildren() {
            return primTree(child)
        }
        return nil
    }

    nonisolated public func primSummary(
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

    nonisolated public func primTransformData(
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
        let exact = prim.GetAttribute(TfToken(prefix))
        if exact.IsValid() {
            var value = VtValue()
            if getAttributeValue(exact, &value), let triple = parseVector3(from: String(describing: value)) {
                return triple
            }
        }
        for attr in prim.GetAttributes() {
            let name = String(attr.GetName())
            guard name.hasPrefix(prefix) else { continue }
            var value = VtValue()
            if getAttributeValue(attr, &value), let triple = parseVector3(from: String(describing: value)) {
                return triple
            }
        }
        return nil
    }

    private func authoredQuaternionOp(prim: UsdPrim, prefix: String) -> simd_quatd? {
        let exact = prim.GetAttribute(TfToken(prefix))
        if exact.IsValid() {
            var value = VtValue()
            if getAttributeValue(exact, &value), let quat = parseQuaternion(from: String(describing: value)) {
                return quat
            }
        }
        for attr in prim.GetAttributes() {
            let name = String(attr.GetName())
            guard name.hasPrefix(prefix) else { continue }
            var value = VtValue()
            if getAttributeValue(attr, &value), let quat = parseQuaternion(from: String(describing: value)) {
                return quat
            }
        }
        return nil
    }

    private func authoredSplitEulerDegrees(prim: UsdPrim) -> SIMD3<Double>? {
        let rx = prim.GetAttribute(TfToken("xformOp:rotateX"))
        let ry = prim.GetAttribute(TfToken("xformOp:rotateY"))
        let rz = prim.GetAttribute(TfToken("xformOp:rotateZ"))
        guard rx.IsValid() || ry.IsValid() || rz.IsValid() else { return nil }
        var x = 0.0
        var y = 0.0
        var z = 0.0
        if rx.IsValid() {
            var value = VtValue()
            if getAttributeValue(rx, &value), let scalar = parseScalar(from: String(describing: value)) {
                x = scalar
            }
        }
        if ry.IsValid() {
            var value = VtValue()
            if getAttributeValue(ry, &value), let scalar = parseScalar(from: String(describing: value)) {
                y = scalar
            }
        }
        if rz.IsValid() {
            var value = VtValue()
            if getAttributeValue(rz, &value), let scalar = parseScalar(from: String(describing: value)) {
                z = scalar
            }
        }
        return SIMD3<Double>(x, y, z)
    }

    private func rotationEulerHintDegrees(prim: UsdPrim) -> SIMD3<Double>? {
        var customData = VtValue()
        guard prim.GetMetadata(TfToken("customData"), &customData) else { return nil }
        let raw = String(describing: customData)
        guard raw.contains("rotationEulerHint") else { return nil }
        let pattern = #"rotationEulerHint\s*=\s*\(([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?),\s*([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?),\s*([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, options: [], range: NSRange(raw.startIndex..<raw.endIndex, in: raw))
        else { return nil }
        func group(_ index: Int) -> Double? {
            guard let r = Range(match.range(at: index), in: raw) else { return nil }
            return Double(String(raw[r]))
        }
        guard let rx = group(1), let ry = group(2), let rz = group(3) else { return nil }
        let radToDeg = 180.0 / Double.pi
        return SIMD3<Double>(rx * radToDeg, ry * radToDeg, rz * radToDeg)
    }

    private func parseVector3(from value: String) -> SIMD3<Double>? {
        let pattern = #"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, options: [], range: range)
        guard matches.count >= 3 else { return nil }
        func number(_ idx: Int) -> Double? {
            guard let r = Range(matches[idx].range, in: value) else { return nil }
            return Double(String(value[r]))
        }
        guard let a = number(0), let b = number(1), let c = number(2) else { return nil }
        return SIMD3<Double>(a, b, c)
    }

    private func parseScalar(from value: String) -> Double? {
        let pattern = #"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, options: [], range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let r = Range(match.range, in: value)
        else { return nil }
        return Double(String(value[r]))
    }

    private func parseQuaternion(from value: String) -> simd_quatd? {
        let pattern = #"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, options: [], range: range)
        var numbers: [Double] = []
        numbers.reserveCapacity(4)
        for match in matches {
            guard let r = Range(match.range, in: value), let number = Double(String(value[r])) else {
                continue
            }
            numbers.append(number)
            if numbers.count == 4 { break }
        }
        guard numbers.count == 4 else { return nil }
        return simd_quatd(ix: numbers[1], iy: numbers[2], iz: numbers[3], r: numbers[0])
    }

    nonisolated public func primMaterialBinding(
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




    nonisolated public func normalizeAssetPath(_ reference: String) -> String {
        reference.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    nonisolated public func validateStage(
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

    nonisolated public func primReferences(
        stage: USDStageURL, primPath: USDPath
    ) throws -> [USDReference] {
        let prim = try openAndGetPrim(stage: stage, primPath: primPath)
        guard prim.HasAuthoredReferences() else { return [] }
        var refsValue = VtValue()
        guard prim.GetMetadata(TfToken("references"), &refsValue) else { return [] }
        return parseReferencesFromMetadata(String(describing: refsValue))
    }

    nonisolated public func addReference(
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
        deref.GetRootLayer().Save(false)
    }

    nonisolated public func removeReference(
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

        let existing = (try? primReferences(stage: stage, primPath: primPath)) ?? []
        let ok = USDOverlay.withUsdEditContext(deref, deref.GetEditTarget()) {
            var refs = prim.GetReferences()
            _ = refs.ClearReferences()
            for item in existing {
                guard item.assetPath != reference.assetPath
                    || (item.primPath ?? "") != (reference.primPath ?? "") else { continue }
                let sdfPath = if let pp = item.primPath, !pp.isEmpty {
                    SdfPath(std.string(pp))
                } else { SdfPath() }
                let sdfRef = SdfReference(
                    std.string(item.assetPath),
                    sdfPath,
                    SdfLayerOffset(0.0, 1.0),
                    VtDictionary()
                )
                _ = refs.AddReference(sdfRef, pxr.UsdListPosition.UsdListPositionBackOfPrependList)
            }
            return true
        }
        guard ok else {
            throw SwiftUsdShellError.referenceEditFailed(
                operation: "remove", stageURL: stage, primPath: primPath,
                assetPath: reference.assetPath, targetPrimPath: reference.primPath
            )
        }
        deref.GetRootLayer().Save(false)
    }

    /// Parse the raw string representation of a references metadata VtValue
    /// into typed `USDReference` values.
    private func parseReferencesFromMetadata(_ raw: String) -> [USDReference] {
        var items: [USDReference] = []
        var index = raw.startIndex
        while let atStart = raw[index...].firstIndex(of: "@") {
            let assetStart = raw.index(after: atStart)
            guard let atEnd = raw[assetStart...].firstIndex(of: "@") else { break }
            let assetPath = String(raw[assetStart..<atEnd])
            var next = raw.index(after: atEnd)
            while next < raw.endIndex, raw[next].isWhitespace {
                next = raw.index(after: next)
            }
            var primPath: String?
            if next < raw.endIndex, raw[next] == "<" {
                let primStart = raw.index(after: next)
                if let primEnd = raw[primStart...].firstIndex(of: ">") {
                    let parsed = String(raw[primStart..<primEnd])
                    primPath = parsed.isEmpty ? nil : parsed
                    next = raw.index(after: primEnd)
                }
            }
            if !assetPath.isEmpty {
                items.append(.init(assetPath: assetPath, primPath: primPath))
            }
            index = next
        }
        var seen = Set<String>()
        return items.filter { ref in
            let key = "\(ref.assetPath)|\(ref.primPath ?? "")"
            return seen.insert(key).inserted
        }
    }

    // MARK: - Session layer / packaging

    nonisolated public func writeSessionLayer(
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
        if let footer = footerComment, !footer.isEmpty {
            lines.append("    // \(footer)")
        }
        lines.append(")")
        if !subLayers.isEmpty {
            lines.append("(")
            lines.append("    subLayers = [")
            for subLayer in subLayers {
                lines.append("        @\(subLayer)@,")
            }
            lines.append("    ]")
            lines.append(")")
        }
        lines.append("")
        let content = lines.joined(separator: "\n")
        try content.write(to: outputURL.url, atomically: true, encoding: .utf8)
    }

    nonisolated public func exportFlattenedLayer(
        sessionLayerURL: USDStageURL,
        outputURL: USDStageURL,
        isUsdz: Bool
    ) throws {
        let metaStagePtr = UsdStage.Open(std.string(sessionLayerURL.url.path), UsdStage.InitialLoadSet.LoadNone)
        guard metaStagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(sessionLayerURL, diagnostic: nil)
        }
        let metaStage = USDOverlay.Dereference(metaStagePtr)
        let sessionLayer = USDOverlay.Dereference(metaStage.GetRootLayer())
        let sessionDir = sessionLayerURL.url.deletingLastPathComponent()

        // Resolve sublayer asset paths relative to the session directory.
        let subLayerPaths = sessionLayer.GetSubLayerPaths()
        var resolvedPaths: [std.string] = []
        for i in 0..<subLayerPaths.size() {
            let raw = String(subLayerPaths[i])
            let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            let resolved: URL
            if trimmed.hasPrefix("/") {
                resolved = URL(fileURLWithPath: trimmed)
            } else {
                resolved = sessionDir.appendingPathComponent(trimmed)
            }
            guard FileManager.default.fileExists(atPath: resolved.path) else {
                throw SwiftUsdShellError.fileNotFound(USDStageURL(resolved))
            }
            resolvedPaths.push_back(std.string(resolved.path))
        }

        // Build in-memory export stage with metadata inherited from the
        // session layer, then flatten all composition arcs.
        let stagePtr = UsdStage.CreateInMemory(std.string("ExportStage"), UsdStage.InitialLoadSet.LoadAll)
        let stage = USDOverlay.Dereference(stagePtr)
        let root = USDOverlay.Dereference(stage.GetRootLayer())

        stage.SetTimeCodesPerSecond(metaStage.GetTimeCodesPerSecond())
        stage.SetFramesPerSecond(metaStage.GetFramesPerSecond())

        var mpuVal = VtValue()
        if metaStage.GetMetadata(TfToken("metersPerUnit"), &mpuVal) {
            stage.SetMetadata(TfToken("metersPerUnit"), mpuVal)
        }
        var upAxisVal = VtValue()
        if metaStage.GetMetadata(TfToken("upAxis"), &upAxisVal) {
            stage.SetMetadata(TfToken("upAxis"), upAxisVal)
        }
        if sessionLayer.HasDefaultPrim() {
            root.SetDefaultPrim(sessionLayer.GetDefaultPrim())
        }
        _ = root.SetSubLayerPaths(resolvedPaths)

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

    nonisolated public func createVerbatimUSDZPackage(
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

    nonisolated public func flattenAndExport(
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

    nonisolated public func extractPackagedTextures(
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

        for entry in zipFile {
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
            try data.write(to: outputURL, options: .atomic)
            writtenCount += 1
        }
        return writtenCount
    }
    nonisolated public func rootPrimPaths(stage: USDStageURL) throws -> [USDPath] {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadNone)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        let pseudoRoot = USDOverlay.Dereference(stagePtr).GetPseudoRoot()
        var paths: [USDPath] = []
        for child in pseudoRoot.GetChildren() {
            guard child.IsValid() else { continue }
            let pathStr = String(child.GetPath().GetAsString())
            guard !pathStr.isEmpty else { continue }
            paths.append(USDPath(pathStr))
        }
        return paths
    }

    nonisolated public func unresolvedDependencies(stage: USDStageURL) throws -> [String] {
        let stagePtr = UsdStage.Open(std.string(stage.url.path), UsdStage.InitialLoadSet.LoadAll)
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stage, diagnostic: nil)
        }
        let pxrStage = USDOverlay.Dereference(stagePtr)
        let fileManager = FileManager.default
        var unresolved: [String] = []
        var seen = Set<String>()
        let dir = stage.url.deletingLastPathComponent()
        for prim in pxrStage.Traverse() {
            guard prim.IsValid(), prim.HasAuthoredReferences() else { continue }
            var refsValue = VtValue()
            guard prim.GetMetadata(TfToken("references"), &refsValue) else { continue }
            let raw = String(describing: refsValue)
            for ref in parseReferencesFromMetadata(raw) {
                let key = ref.assetPath
                guard seen.insert(key).inserted else { continue }
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
        let modificationTime = stageModificationTime(stageURL.url)

        if let cached = stages[stageURL],
           stageModificationTimes[stageURL] == modificationTime {
            return cached
        }

        let stageRef = UsdStage.Open(std.string(stageURL.url.path), openUSDLoadPolicy(loadPolicy))
        guard stageRef._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stageURL, diagnostic: nil)
        }
        let stage = USDOverlay.Dereference(stageRef)
        stages[stageURL] = stage
        stageModificationTimes[stageURL] = modificationTime
        return stage
    }

    func stageModificationTime(_ url: URL) -> TimeInterval {
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        return date?.timeIntervalSinceReferenceDate ?? 0
    }

    nonisolated func stageMetadata(_ stage: UsdStage) -> USDStageMetadata {
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

    nonisolated func stageTimeSampleRange(_ stage: UsdStage) -> (start: Double, end: Double)? {
        var start: Double?
        var end: Double?

        for prim in stage.Traverse() {
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

    nonisolated func attributeTimeSampleRange(_ attribute: UsdAttribute) -> (start: Double, end: Double)? {
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

    nonisolated func stageAnimationTracks(_ stage: UsdStage) -> [USDPath] {
        var tracks: [USDPath] = []
        for prim in stage.Traverse() {
            let typeName = stableOwnedString(describing: prim.GetTypeName().GetString()).lowercased()
            guard typeName == "skelanimation"
                || typeName == "animation"
                || typeName == "realitykittimeline"
            else { continue }
            tracks.append(USDPath(stableOwnedString(describing: prim.GetPath().GetAsString())))
        }
        return tracks
    }

    nonisolated func stageCameras(_ stage: UsdStage) -> [USDPath] {
        var cameras: [USDPath] = []
        for prim in stage.Traverse() {
            guard stableOwnedString(describing: prim.GetTypeName().GetString()) == "Camera" else { continue }
            cameras.append(USDPath(stableOwnedString(describing: prim.GetPath().GetAsString())))
        }
        return cameras
    }

    nonisolated func primTree(_ prim: UsdPrim) -> USDPrimTree {
        USDPrimTree(
            path: USDPath(stableOwnedString(describing: prim.GetPath().GetAsString())),
            name: USDToken(stableOwnedString(describing: prim.GetName().GetString())),
            typeName: tokenOrNil(prim.GetTypeName()),
            specifier: primSpecifier(prim.GetSpecifier()),
            isActive: prim.IsActive(),
            isInstanceable: prim.IsInstanceable(),
            purpose: purpose(prim),
            children: prim.GetChildren().map { primTree($0) }
        )
    }

    nonisolated func geometryStatistics(_ root: UsdPrim) -> USDGeometryStatistics {
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

            for child in prim.GetChildren() {
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

    nonisolated func sceneBounds(_ stage: UsdStage) -> USDSceneBounds? {
        let defaultPrim = stage.GetDefaultPrim()
        if defaultPrim.IsValid(), let bounds = sceneBounds(defaultPrim, timeCode: .default) {
            return bounds
        }
        return combinedChildBounds(stage.GetPseudoRoot(), timeCode: .default)
    }

    nonisolated func sceneBounds(_ prim: UsdPrim, timeCode: USDTimeCode) -> USDSceneBounds? {
        let imageable = UsdGeomImageable(prim)
        if USDOverlay.GetPrim(imageable).IsValid(),
           let bounds = sceneBounds(imageable, timeCode: timeCode) {
            return bounds
        }
        return combinedChildBounds(prim, timeCode: timeCode)
    }

    nonisolated func sceneBounds(_ imageable: UsdGeomImageable, timeCode: USDTimeCode) -> USDSceneBounds? {
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

    nonisolated func combinedChildBounds(_ prim: UsdPrim, timeCode: USDTimeCode) -> USDSceneBounds? {
        var combined: USDSceneBounds?
        for child in prim.GetChildren() {
            guard let childBounds = sceneBounds(child, timeCode: timeCode) else {
                continue
            }
            combined = combined.map { union($0, childBounds) } ?? childBounds
        }
        return combined
    }

    nonisolated func sceneBounds(min: SIMD3<Float>, max: SIMD3<Float>) -> USDSceneBounds {
        let center = (min + max) / 2
        let extent = max - min
        return USDSceneBounds(
            min: min,
            max: max,
            center: center,
            maxExtent: Swift.max(extent.x, Swift.max(extent.y, extent.z))
        )
    }

    nonisolated func union(_ lhs: USDSceneBounds, _ rhs: USDSceneBounds) -> USDSceneBounds {
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

    nonisolated func meshGeometryCounts(_ prim: UsdPrim) -> (triangles: Int, vertices: Int) {
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

    nonisolated func shaderIdentifier(_ prim: UsdPrim) -> String? {
        let idAttr = prim.GetAttribute(TfToken(std.string("info:id")))
        guard idAttr.IsValid() else { return nil }

        var token = TfToken()
        if idAttr.Get(&token, UsdTimeCode.Default()) {
            let value = stableOwnedString(describing: token.GetString())
            return value.isEmpty ? nil : value
        }

        return nil
    }

    nonisolated func primSummary(
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

    nonisolated func attributes(_ prim: UsdPrim) -> [USDAttributeSummary] {
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

    nonisolated func relationships(_ prim: UsdPrim) -> [USDRelationshipSummary] {
        prim.GetRelationships().map { relationship in
            var targets = SdfPathVector()
            _ = relationship.GetTargets(&targets)
            return USDRelationshipSummary(
                name: USDToken(stableOwnedString(describing: relationship.GetName().GetString())),
                targets: targets.map { USDPath(stableOwnedString(describing: $0.GetAsString())) }
            )
        }
    }

    nonisolated func compositionArcs(_ prim: UsdPrim) -> [USDCompositionArcSummary] {
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

    nonisolated func variantSets(_ prim: UsdPrim) -> [USDVariantSetSummary] {
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

    nonisolated func transformInspection(_ prim: UsdPrim, timeCode: USDTimeCode) -> USDTransformInspection? {
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

    nonisolated func authoredTransformInspection(
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

    nonisolated func collectAuthoredOps(for prim: UsdPrim) -> [USDAuthoredXformOp] {
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

    nonisolated func xformOpOrder(_ prim: UsdPrim) -> [String] {
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

    nonisolated func authoredOp(
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

    nonisolated func authoredXformValue(
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

    nonisolated func xformVector3Value(_ attr: UsdAttribute) -> SIMD3<Double>? {
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

    nonisolated func xformScalarValue(_ attr: UsdAttribute) -> Double? {
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

    nonisolated func setCommonTransform(
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

    nonisolated func materialBindingInfo(
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
        let purposeToken = TfToken(std.string("allPurpose"))

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

    nonisolated func materialSummaries(_ root: UsdPrim) -> [USDMaterialSummary] {
        var summaries: [USDMaterialSummary] = []

        func visit(_ prim: UsdPrim) {
            if stableOwnedString(describing: prim.GetTypeName().GetString()) == "Material",
               let summary = materialSummary(prim) {
                summaries.append(summary)
            }

            for child in prim.GetChildren() {
                visit(child)
            }
        }

        visit(root)
        return summaries
    }

    nonisolated func materialSummary(for prim: UsdPrim, stage: UsdStage) -> USDMaterialSummary? {
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

    nonisolated func materialSummary(_ materialPrim: UsdPrim) -> USDMaterialSummary? {
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

    nonisolated func materialSummaryType(_ material: UsdShadeMaterial) -> USDMaterialSummaryType {
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

    nonisolated func materialProperties(_ material: UsdShadeMaterial) -> [USDMaterialPropertySummary] {
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

    nonisolated func materialProperty(_ input: UsdShadeInput) -> USDMaterialPropertySummary? {
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

    nonisolated func textureProperty(_ input: UsdShadeInput, depth: Int) -> USDMaterialPropertyInfo? {
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

    nonisolated func textureProperty(
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

    nonisolated func textureValue(_ attr: UsdAttribute) -> USDMaterialPropertyInfo? {
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

    nonisolated func effectiveMaterialPath(for prim: UsdPrim) -> String? {
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
            for child in prim.GetChildren() {
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

    nonisolated func directBindingDetails(
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

    nonisolated func firstBindingTarget(from relationship: UsdRelationship) -> String? {
        var targets = SdfPathVector()
        _ = relationship.GetTargets(&targets)
        guard !targets.empty() else { return nil }
        return stableOwnedString(describing: targets[0].GetAsString())
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

private func stableOwnedString<T>(describing value: T) -> String {
    String(describing: value)
}
