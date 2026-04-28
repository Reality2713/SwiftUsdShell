import Foundation
import simd
import Testing

@testable import SwiftUsdShell

private func assertSendable<T: Sendable>(_: T.Type) {}

@Test
func handlesAreHashableAndCodable() throws {
    let stage = USDStageHandle(rawValue: 42)
    let prim = USDPrimHandle(stage: stage, path: "/Root/Material")

    #expect(stage.rawValue == 42)
    #expect(prim.stage == stage)
    #expect(prim.path.rawValue == "/Root/Material")
}

@Test
func stageURLsAreTypedAndCodable() throws {
    let rawURL = URL(fileURLWithPath: "/tmp/../tmp/model.usda")
    let stageURL = USDStageURL(rawURL)

    #expect(stageURL.url == rawURL.standardizedFileURL)
    #expect(stageURL.description == rawURL.standardizedFileURL.path)

    let encoded = try JSONEncoder().encode(stageURL)
    let decoded = try JSONDecoder().decode(USDStageURL.self, from: encoded)
    #expect(decoded == stageURL)
}

@Test
func valueSummariesArePureSwiftAndCodable() throws {
    let summary = USDPrimSummary(
        path: "/Root/Cube",
        name: "Cube",
        typeName: "Mesh",
        isActive: true,
        visibility: "inherited",
        purpose: "default",
        kind: "component",
        attributes: [
            USDAttributeSummary(
                name: "displayColor",
                typeName: "color3f[]",
                value: .array([
                    .vector3(USDVector3(x: 1, y: 0.5, z: 0.25)),
                ]),
                isAuthored: true,
                hasValue: true,
                timeSampleCount: 0,
                timeSamples: [.default]
            ),
            USDAttributeSummary(
                name: "asset",
                typeName: "asset",
                value: .assetPath("textures/baseColor.png"),
                isAuthored: true,
                hasValue: true
            ),
        ],
        relationships: [
            USDRelationshipSummary(name: "material:binding", targets: ["/Root/Looks/Mat"]),
        ]
    )

    let encoded = try JSONEncoder().encode(summary)
    let decoded = try JSONDecoder().decode(USDPrimSummary.self, from: encoded)

    #expect(decoded == summary)
    #expect(decoded.attributes.first?.value == USDValue.array([
        USDValue.vector3(USDVector3(x: 1, y: 0.5, z: 0.25)),
    ]))
    #expect(decoded.typeNameText == "Mesh")
    #expect(decoded.visibilityText == "inherited")
    #expect(decoded.purposeText == "default")
    #expect(decoded.kindText == "component")
}

@Test
func primTreesArePureSwiftAndCodable() throws {
    let tree = USDPrimTree(
        path: "/",
        name: "",
        typeName: nil,
        purpose: "default",
        children: [
            USDPrimTree(path: "/Root", name: "Root", typeName: "Xform"),
        ]
    )

    let encoded = try JSONEncoder().encode(tree)
    let decoded = try JSONDecoder().decode(USDPrimTree.self, from: encoded)

    #expect(decoded == tree)
    #expect(decoded.id == "/")
}

@Test
func stageMetadataIsPureSwiftAndCodable() throws {
    let metadata = USDStageMetadata(
        upAxis: "Y",
        metersPerUnit: 0.01,
        defaultPrimName: "Robot",
        autoPlay: true,
        playbackMode: "loop",
        timeCodesPerSecond: 60,
        startTimeCode: 0,
        endTimeCode: 148,
        animationTracks: ["/Robot/Animation"],
        availableCameras: ["/Robot/Camera"]
    )

    #expect(metadata.hasAnimationTracks)
    #expect(metadata.hasUsableTimelineRange)

    let encoded = try JSONEncoder().encode(metadata)
    let decoded = try JSONDecoder().decode(USDStageMetadata.self, from: encoded)

    #expect(decoded == metadata)
    #expect(decoded.animationTracks.first?.rawValue == "/Robot/Animation")
    #expect(decoded.availableCameras.first?.rawValue == "/Robot/Camera")
}

@Test
func materialEditContractsArePureSwiftAndCodable() throws {
    let request = USDMaterialEditRequest(
        stageURL: USDStageURL(URL(fileURLWithPath: "/tmp/session.usda")),
        materialPath: "/Root/Looks/Body",
        channel: .diffuseColor,
        operation: .setTexture(
            sourceURL: USDStageURL(URL(fileURLWithPath: "/tmp/replacement.png")),
            authoredAssetPath: "../Resources/replacement.png"
        )
    )
    let result = USDMaterialEditResult(
        resultingMode: .usdPreviewSurface,
        changedPrimPaths: ["/Root/Looks/Body"],
        changedAssetPaths: ["../Resources/replacement.png"]
    )

    let encodedRequest = try JSONEncoder().encode(request)
    let decodedRequest = try JSONDecoder().decode(USDMaterialEditRequest.self, from: encodedRequest)
    #expect(decodedRequest == request)

    let encodedResult = try JSONEncoder().encode(result)
    let decodedResult = try JSONDecoder().decode(USDMaterialEditResult.self, from: encodedResult)
    #expect(decodedResult == result)
}

@Test
func primTreeTraversalHelpersFindAndCountNodes() {
    let tree = USDPrimTree(
        path: "/",
        name: "",
        children: [
            USDPrimTree(
                path: "/Root",
                name: "Root",
                typeName: "Xform",
                children: [
                    USDPrimTree(path: "/Root/Mesh", name: "Mesh", typeName: "Mesh"),
                    USDPrimTree(path: "/Root/Looks", name: "", typeName: "Scope"),
                ]
            ),
        ]
    )

    #expect(tree.nodeCount == 4)
    #expect(tree.displayName == "/")
    #expect(tree.typeNameText == "")
    #expect(tree.purposeText == "default")
    #expect(tree.first(path: "/Root/Mesh")?.displayName == "Mesh")
    #expect(tree.first(path: "/Root/Mesh")?.typeNameText == "Mesh")
    #expect(tree.first(path: "/Root/Looks")?.displayName == "/Root/Looks")
    #expect(tree.first(path: "/Missing") == nil)
}

@Test
func materialInspectionContractsArePureSwiftAndCodable() throws {
    let material = USDMaterialSummary(
        path: "/Root/Looks/Body",
        name: "Body",
        materialType: .usdPreviewSurface,
        properties: [
            USDMaterialPropertySummary(
                name: "diffuseColor",
                propertyType: .color,
                value: .color(red: 0.25, green: 0.5, blue: 1.0)
            ),
            USDMaterialPropertySummary(
                name: "normal",
                propertyType: .texture,
                value: .texture(
                    url: "textures/body_normal.png",
                    resolvedPath: "/Assets/textures/body_normal.png"
                )
            ),
        ]
    )
    let binding = USDMaterialBindingInfo(
        selectedPrimPath: "/Root/Geometry/Body",
        effectiveMaterialPath: "/Root/Looks/Body",
        authoredMaterialPath: "/Root/Looks/Body",
        bindingSourcePrimPath: "/Root/Geometry/Body",
        bindingStrength: .fallbackStrength
    )

    let encodedMaterial = try JSONEncoder().encode(material)
    let decodedMaterial = try JSONDecoder().decode(USDMaterialSummary.self, from: encodedMaterial)
    #expect(decodedMaterial == material)
    #expect(decodedMaterial.id == "/Root/Looks/Body")

    let encodedBinding = try JSONEncoder().encode(binding)
    let decodedBinding = try JSONDecoder().decode(USDMaterialBindingInfo.self, from: encodedBinding)
    #expect(decodedBinding == binding)
    #expect(decodedBinding.bindingStrength?.displayName == "Default")
}

@Test
func transformAndStatisticsContractsArePureSwiftAndCodable() throws {
    let transform = USDTransformInspection(
        localTransform: USDTransformData(
            position: SIMD3<Double>(1, 2, 3),
            rotationDegrees: SIMD3<Double>(0, 45, 90),
            scale: SIMD3<Double>(repeating: 2)
        ),
        authoredOps: [
            USDAuthoredXformOp(
                token: "xformOp:translate",
                kind: .translate,
                precision: .double,
                value: .vector3(SIMD3<Double>(1, 2, 3))
            ),
            USDAuthoredXformOp(
                token: "xformOp:transform",
                kind: .transform,
                precision: .double,
                value: .text("matrix4d")
            ),
        ],
        editCapability: .readonlyMatrix,
        restrictionReason: .matrixTransformOp,
        isAnimated: true
    )
    let stats = USDGeometryStatistics(
        totalTriangles: 12,
        totalVertices: 8,
        meshCount: 1,
        materialCount: 2,
        textureCount: 3
    )
    let bounds = USDSceneBounds(
        min: SIMD3<Float>(-1, -2, -3),
        max: SIMD3<Float>(1, 2, 3),
        center: .zero,
        maxExtent: 6
    )

    #expect(USDTransformEditCapability.editableCommon.isEditable)
    #expect(USDTransformEditCapability.readonlyMatrix.isEditable == false)

    let encodedTransform = try JSONEncoder().encode(transform)
    let decodedTransform = try JSONDecoder().decode(USDTransformInspection.self, from: encodedTransform)
    #expect(decodedTransform == transform)

    let encodedStats = try JSONEncoder().encode(stats)
    let decodedStats = try JSONDecoder().decode(USDGeometryStatistics.self, from: encodedStats)
    #expect(decodedStats == stats)

    let encodedBounds = try JSONEncoder().encode(bounds)
    let decodedBounds = try JSONDecoder().decode(USDSceneBounds.self, from: encodedBounds)
    #expect(decodedBounds == bounds)
}

@Test
func modelInfoContractsArePureSwiftAndCodable() throws {
    let modelInfo = USDModelInfo(
        boundsExtent: SIMD3<Float>(10, 20, 30),
        boundsCenter: SIMD3<Float>(1, 2, 3),
        scale: SIMD3<Float>(repeating: 0.01),
        upAxis: "Z",
        animationCount: 2,
        animationNames: ["Walk", "Idle"],
        metersPerUnit: 0.01,
        autoPlay: true,
        playbackMode: "loop",
        animatableStatus: .animatable,
        hasAnimationLibrary: true,
        skeletonJointCount: 32,
        maxJointInfluences: 4,
        hasSkinnedMesh: true,
        blendShapes: [
            USDBlendShapeInfo(
                path: "/Root/Skel/Face",
                name: "Smile",
                weightCount: 1,
                weightNames: ["smile"]
            ),
        ]
    )

    let encoded = try JSONEncoder().encode(modelInfo)
    let decoded = try JSONDecoder().decode(USDModelInfo.self, from: encoded)

    #expect(decoded == modelInfo)
    #expect(decoded.blendShapes.first?.name == "Smile")
}

@Test
func materialShellEnumsDoNotExposeProductOutputs() {
    #expect(USDMaterialSurfaceOutputFamily.allCases.map(\.rawValue) == [
        "usdPreviewSurface",
        "materialXPreviewSurface",
        "openPBR",
    ])
    #expect(USDMaterialAuthoringTarget.usdPreviewSurface.rawValue == "usdPreviewSurface")
    #expect(USDMaterialAuthoredMode.unknown.rawValue == "unknown")
}

@Test
func publicContractsRemainSendable() {
    assertSendable(USDStageURL.self)
    assertSendable(USDStageHandle.self)
    assertSendable(USDPrimHandle.self)
    assertSendable(USDValue.self)
    assertSendable(USDPrimSummary.self)
    assertSendable(USDPrimTree.self)
    assertSendable(USDStageMetadata.self)
    assertSendable(USDMaterialSummary.self)
    assertSendable(USDMaterialBindingInfo.self)
    assertSendable(USDMaterialEditRequest.self)
    assertSendable(USDMaterialEditResult.self)
    assertSendable(USDTransformInspection.self)
    assertSendable(USDGeometryStatistics.self)
    assertSendable(USDModelInfo.self)
}
