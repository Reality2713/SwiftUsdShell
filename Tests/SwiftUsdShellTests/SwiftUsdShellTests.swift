import Foundation
import Testing

@testable import SwiftUsdShell

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
