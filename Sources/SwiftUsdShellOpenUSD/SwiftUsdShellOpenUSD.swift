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
typealias UsdTimeCode = pxr.UsdTimeCode
typealias UsdGeomImageable = pxr.UsdGeomImageable
typealias UsdGeomXformCommonAPI = pxr.UsdGeomXformCommonAPI
typealias UsdShadeMaterialBindingAPI = pxr.UsdShadeMaterialBindingAPI
typealias UsdModelAPI = pxr.UsdModelAPI
typealias TfToken = pxr.TfToken
typealias SdfPath = pxr.SdfPath
typealias SdfPathVector = pxr.SdfPathVector
typealias SdfLayerOffset = pxr.SdfLayerOffset
typealias SdfSpecifier = pxr.SdfSpecifier
typealias GfVec3d = pxr.GfVec3d
typealias GfVec3f = pxr.GfVec3f

/// Mechanical runtime adapter that answers SwiftUsdShell requests with OpenUSD.
///
/// This target may import SwiftUsd/OpenUSD. The base SwiftUsdShell target must
/// remain independent from this adapter.
public actor OpenUSDStageRuntime: USDStageRuntime {
    private var stages: [USDStageURL: UsdStage] = [:]

    public init() {}

    public func inspectStage(_ request: USDStageInspectionRequest) async throws -> USDStageInspection {
        let stage = try stage(for: request.stageURL, loadPolicy: request.options.loadPolicy)
        let metadata = stageMetadata(stage)
        let tree = request.options.includePrimTree ? primTree(stage.GetPseudoRoot()) : nil

        return USDStageInspection(
            stageURL: request.stageURL,
            metadata: metadata,
            primTree: tree,
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

        case .save(let stageURL):
            let stage = try stage(for: stageURL, loadPolicy: .loadAll)
            stage.Save()
            return USDEditResult(refreshHints: USDEditRefreshHints(refreshInspector: false))
        }
    }
}

private extension OpenUSDStageRuntime {
    func stage(for stageURL: USDStageURL, loadPolicy: USDLoadPolicy) throws -> UsdStage {
        if let cached = stages[stageURL] {
            return cached
        }

        let stageRef = UsdStage.Open(std.string(stageURL.url.path), openUSDLoadPolicy(loadPolicy))
        guard stageRef._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stageURL, diagnostic: nil)
        }
        let stage = USDOverlay.Dereference(stageRef)
        stages[stageURL] = stage
        return stage
    }

    func stageMetadata(_ stage: UsdStage) -> USDStageMetadata {
        let defaultPrim = stage.GetDefaultPrim()
        return USDStageMetadata(
            upAxis: tokenOrNil(pxr.UsdGeomGetStageUpAxis(USDOverlay.TfWeakPtr(stage))),
            metersPerUnit: pxr.UsdGeomGetStageMetersPerUnit(USDOverlay.TfWeakPtr(stage)),
            defaultPrimName: defaultPrim.IsValid()
                ? USDToken(stableOwnedString(describing: defaultPrim.GetName().GetString()))
                : nil,
            timeCodesPerSecond: stage.GetTimeCodesPerSecond(),
            startTimeCode: stage.GetStartTimeCode(),
            endTimeCode: stage.GetEndTimeCode()
        )
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
            children: prim.GetChildren().map { primTree($0) }
        )
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
            USDRelationshipSummary(
                name: USDToken(stableOwnedString(describing: relationship.GetName().GetString())),
                targets: targets.map { USDPath(stableOwnedString(describing: $0.GetAsString())) }
            )
        }
    }

    func compositionArcs(_ prim: UsdPrim) -> [USDCompositionArcSummary] {
        var arcs: [USDCompositionArcSummary] = []
        for spec in prim.GetPrimStack() {
            arcs.append(contentsOf: spec.GetReferenceList().GetAddedOrExplicitItems().map {
                compositionArc(
                    kind: .reference,
                    assetPath: stableOwnedString(describing: $0.GetAssetPath()),
                    primPath: stableOwnedString(describing: $0.GetPrimPath().GetAsString()),
                    layerOffset: $0.GetLayerOffset()
                )
            })
            arcs.append(contentsOf: spec.GetPayloadList().GetAddedOrExplicitItems().map {
                compositionArc(
                    kind: .payload,
                    assetPath: stableOwnedString(describing: $0.GetAssetPath()),
                    primPath: stableOwnedString(describing: $0.GetPrimPath().GetAsString()),
                    layerOffset: $0.GetLayerOffset()
                )
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
            return nil
        }

        return USDTransformInspection(
            localTransform: USDTransformData(
                position: SIMD3<Double>(translation[0], translation[1], translation[2]),
                rotationDegrees: SIMD3<Double>(Double(rotation[0]), Double(rotation[1]), Double(rotation[2])),
                scale: SIMD3<Double>(Double(scale[0]), Double(scale[1]), Double(scale[2]))
            ),
            editCapability: .editableCommon,
            restrictionReason: nil
        )
    }

    func setCommonTransform(
        _ transform: USDTransformData,
        on prim: UsdPrim,
        options: USDTransformEditOptions
    ) throws {
        guard options.authoringStyle != .commonTRSOrient else {
            throw SwiftUsdShellError.unsupportedSchema("commonTRSOrient requires an orient xform-op adapter path")
        }

        let xform = UsdGeomXformCommonAPI(prim)
        let ok = xform.SetXformVectors(
            GfVec3d(transform.position.x, transform.position.y, transform.position.z),
            GfVec3f(Float(transform.rotationDegrees.x), Float(transform.rotationDegrees.y), Float(transform.rotationDegrees.z)),
            GfVec3f(Float(transform.scale.x), Float(transform.scale.y), Float(transform.scale.z)),
            GfVec3f(0, 0, 0),
            .RotationOrderXYZ,
            openUSDTimeCode(options.timeCode)
        )
        guard ok else {
            throw SwiftUsdShellError.invalidValue("Unable to author common transform")
        }
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

        let effectiveMaterialPath = effectiveMaterialPath(for: prim).map(USDPath.init)
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
}

private func collectDiagnostics(_ body: () -> Void) -> [USDDiagnostic] {
    USDOverlay.withTfErrorMark { mark in
        body()
        return mark.errors.map {
            USDDiagnostic(
                severity: .error,
                code: String($0.GetErrorCodeAsString()),
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
    var value = TfToken()
    guard imageable.GetVisibilityAttr().Get(&value) else { return nil }
    return tokenOrNil(value)
}

private func purpose(_ prim: UsdPrim) -> USDToken? {
    let imageable = UsdGeomImageable(prim)
    guard USDOverlay.GetPrim(imageable).IsValid() else { return nil }
    var value = TfToken()
    guard imageable.GetPurposeAttr().Get(&value) else { return nil }
    return tokenOrNil(value)
}

private func modelKind(_ prim: UsdPrim) -> USDToken? {
    var kind = TfToken()
    guard UsdModelAPI(prim).GetKind(&kind) else { return nil }
    return tokenOrNil(kind)
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
