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
typealias UsdShadeMaterialBindingAPI = pxr.UsdShadeMaterialBindingAPI
typealias UsdModelAPI = pxr.UsdModelAPI
typealias TfToken = pxr.TfToken
typealias SdfPath = pxr.SdfPath
typealias SdfPathVector = pxr.SdfPathVector
typealias SdfLayerOffset = pxr.SdfLayerOffset
typealias SdfSpecifier = pxr.SdfSpecifier
typealias SdfValueTypeName = pxr.SdfValueTypeName
typealias GfVec3d = pxr.GfVec3d
typealias GfVec3f = pxr.GfVec3f
typealias VtIntArray = pxr.VtIntArray
typealias VtTokenArray = pxr.VtTokenArray
typealias VtVec3fArray = pxr.VtVec3fArray

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
            statistics: request.options.includeStatistics ? geometryStatistics(prim) : nil,
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
            return value.isEmpty ? nil : value
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
