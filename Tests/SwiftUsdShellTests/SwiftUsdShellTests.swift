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
                timeSamples: [.default]
            ),
            USDAttributeSummary(
                name: "asset",
                typeName: "asset",
                value: .assetPath("textures/baseColor.png")
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
}
