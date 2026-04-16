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
