import CxxStdlib
import Foundation
private import OpenUSD
import SwiftUsdShell

/// A typed snapshot of one asset-valued USD attribute.
///
/// This is a mechanical OpenUSD result. Callers own any policy that decides
/// whether the asset is a texture, where it should be copied, or how its path
/// should be rewritten.
public struct USDResolvedAssetAttribute: Hashable, Sendable, Codable {
    public var primPath: USDPath
    public var attributeName: USDToken
    public var authoredPath: USDAssetPath
    public var resolvedPath: USDAssetPath?

    public init(
        primPath: USDPath,
        attributeName: USDToken,
        authoredPath: USDAssetPath,
        resolvedPath: USDAssetPath? = nil
    ) {
        self.primPath = primPath
        self.attributeName = attributeName
        self.authoredPath = authoredPath
        self.resolvedPath = resolvedPath
    }
}

/// Exact accounting for a typed asset-path rewrite batch.
public struct USDAssetPathRewriteResult: Hashable, Sendable, Codable {
    public var appliedCount: Int
    public var failedEdits: [USDAssetPathEdit]

    public init(appliedCount: Int, failedEdits: [USDAssetPathEdit] = []) {
        self.appliedCount = appliedCount
        self.failedEdits = failedEdits
    }
}

/// One requested float input on a material's effective surface shader.
///
/// A snapshot is returned even when the input is absent or has no readable
/// float value, allowing callers to decide whether to author a default.
public struct USDMaterialSurfaceFloatInput: Hashable, Sendable, Codable {
    public var materialPath: USDPath
    public var shaderPath: USDPath
    public var inputName: USDToken
    public var value: Double?

    public init(
        materialPath: USDPath,
        shaderPath: USDPath,
        inputName: USDToken,
        value: Double? = nil
    ) {
        self.materialPath = materialPath
        self.shaderPath = shaderPath
        self.inputName = inputName
        self.value = value
    }
}

/// A typed float opinion for one shader input.
public struct USDShaderFloatInputEdit: Hashable, Sendable, Codable {
    public var shaderPath: USDPath
    public var inputName: USDToken
    public var value: Double
    public var clearConnections: Bool

    public init(
        shaderPath: USDPath,
        inputName: USDToken,
        value: Double,
        clearConnections: Bool = false
    ) {
        self.shaderPath = shaderPath
        self.inputName = inputName
        self.value = value
        self.clearConnections = clearConnections
    }
}

/// Exact accounting for a typed shader-float edit batch.
public struct USDShaderFloatInputEditResult: Hashable, Sendable, Codable {
    public var appliedCount: Int
    public var failedEdits: [USDShaderFloatInputEdit]

    public init(appliedCount: Int, failedEdits: [USDShaderFloatInputEdit] = []) {
        self.appliedCount = appliedCount
        self.failedEdits = failedEdits
    }
}

public extension OpenUSDStageRuntime {
    /// Enumerates every readable asset-valued attribute on the composed stage.
    func resolvedAssetAttributes(
        stageURL: USDStageURL
    ) throws -> [USDResolvedAssetAttribute] {
        try withConversionEngineStage(stageURL) { stage in
            var snapshots: [USDResolvedAssetAttribute] = []

            func visit(_ prim: UsdPrim) {
                guard prim.IsValid() else { return }
                let primPath = USDPath(String(prim.GetPath().GetAsString()))
                for attribute in prim.GetAttributes() {
                    guard attribute.GetTypeName() == SdfValueTypeName.Asset else { continue }
                    var value = SdfAssetPath()
                    guard attribute.Get(&value, UsdTimeCode.Default()) else { continue }

                    let authored = String(value.GetAssetPath().pointee)
                    let resolved = String(value.GetResolvedPath().pointee)
                    snapshots.append(
                        USDResolvedAssetAttribute(
                            primPath: primPath,
                            attributeName: USDToken(String(attribute.GetName().GetString())),
                            authoredPath: USDAssetPath(authored),
                            resolvedPath: resolved.isEmpty ? nil : USDAssetPath(resolved)
                        )
                    )
                }
                for child in prim.GetChildren().swiftSequence {
                    visit(child)
                }
            }

            visit(stage.GetPseudoRoot())
            return snapshots
        }
    }

    /// Applies asset-path edits through typed `SdfAssetPath` values and saves
    /// the stage once after the batch.
    func rewriteAssetPaths(
        stageURL: USDStageURL,
        edits: [USDAssetPathEdit]
    ) throws -> USDAssetPathRewriteResult {
        guard !edits.isEmpty else {
            return USDAssetPathRewriteResult(appliedCount: 0)
        }

        return try withConversionEngineStage(stageURL) { stage in
            var appliedCount = 0
            var failedEdits: [USDAssetPathEdit] = []

            for edit in edits {
                let prim = stage.GetPrimAtPath(SdfPath(std.string(edit.primPath.rawValue)))
                guard prim.IsValid() else {
                    failedEdits.append(edit)
                    continue
                }
                let attribute = prim.GetAttribute(TfToken(std.string(edit.attributeName.rawValue)))
                guard attribute.IsValid(),
                      attribute.GetTypeName() == SdfValueTypeName.Asset,
                      attribute.Set(
                        SdfAssetPath(std.string(edit.assetPath)),
                        UsdTimeCode.Default()
                      )
                else {
                    failedEdits.append(edit)
                    continue
                }
                appliedCount += 1
            }

            if appliedCount > 0 {
                stage.Save()
            }
            return USDAssetPathRewriteResult(
                appliedCount: appliedCount,
                failedEdits: failedEdits
            )
        }
    }

    /// Resolves each material's effective surface shader and reads the requested
    /// float inputs. It does not choose defaults or apply renderer policy.
    func materialSurfaceFloatInputs(
        stageURL: USDStageURL,
        inputNames: [USDToken]
    ) throws -> [USDMaterialSurfaceFloatInput] {
        guard !inputNames.isEmpty else { return [] }

        return try withConversionEngineStage(stageURL) { stage in
            var snapshots: [USDMaterialSurfaceFloatInput] = []

            func visit(_ prim: UsdPrim) {
                guard prim.IsValid() else { return }
                if String(prim.GetTypeName().GetString()) == "Material" {
                    let material = UsdShadeMaterial(prim)
                    let surfaceShader = material.ComputeSurfaceSource(
                        TfToken(""),
                        nil as UnsafeMutablePointer<TfToken>?,
                        nil as UnsafeMutablePointer<UsdShadeAttributeType>?
                    )
                    let shaderPrim = surfaceShader.GetPrim()
                    if material.GetPrim().IsValid(), shaderPrim.IsValid() {
                        let materialPath = USDPath(String(prim.GetPath().GetAsString()))
                        let shaderPath = USDPath(String(shaderPrim.GetPath().GetAsString()))
                        for inputName in inputNames {
                            let attribute = shaderPrim.GetAttribute(
                                TfToken(std.string("inputs:\(inputName.rawValue)"))
                            )
                            var value: Double?
                            if attribute.IsValid() {
                                var nativeValue = VtValue()
                                if attribute.Get(&nativeValue, UsdTimeCode.Default()),
                                   nativeValue.IsHolding(T: Float.self) {
                                    value = Double(nativeValue.Get() as Float)
                                }
                            }
                            snapshots.append(
                                USDMaterialSurfaceFloatInput(
                                    materialPath: materialPath,
                                    shaderPath: shaderPath,
                                    inputName: inputName,
                                    value: value
                                )
                            )
                        }
                    }
                }
                for child in prim.GetChildren().swiftSequence {
                    visit(child)
                }
            }

            visit(stage.GetPseudoRoot())
            return snapshots
        }
    }

    /// Authors typed float values on shader `inputs:*` attributes and saves the
    /// stage once after the batch.
    func setShaderFloatInputs(
        stageURL: USDStageURL,
        edits: [USDShaderFloatInputEdit]
    ) throws -> USDShaderFloatInputEditResult {
        guard !edits.isEmpty else {
            return USDShaderFloatInputEditResult(appliedCount: 0)
        }

        return try withConversionEngineStage(stageURL) { stage in
            var appliedCount = 0
            var failedEdits: [USDShaderFloatInputEdit] = []

            for edit in edits {
                guard edit.value.isFinite else {
                    failedEdits.append(edit)
                    continue
                }
                let prim = stage.GetPrimAtPath(SdfPath(std.string(edit.shaderPath.rawValue)))
                guard prim.IsValid() else {
                    failedEdits.append(edit)
                    continue
                }

                let attributeName = TfToken(std.string("inputs:\(edit.inputName.rawValue)"))
                let existing = prim.GetAttribute(attributeName)
                let attribute = existing.IsValid()
                    ? existing
                    : prim.CreateAttribute(
                        attributeName,
                        SdfValueTypeName.Float,
                        false,
                        SdfVariability.SdfVariabilityVarying
                    )
                guard attribute.IsValid() else {
                    failedEdits.append(edit)
                    continue
                }
                if edit.clearConnections {
                    _ = attribute.ClearConnections()
                }
                guard attribute.Set(VtValue(Float(edit.value)), UsdTimeCode.Default()) else {
                    failedEdits.append(edit)
                    continue
                }
                appliedCount += 1
            }

            if appliedCount > 0 {
                stage.Save()
            }
            return USDShaderFloatInputEditResult(
                appliedCount: appliedCount,
                failedEdits: failedEdits
            )
        }
    }
}

private func withConversionEngineStage<T>(
    _ stageURL: USDStageURL,
    _ body: (UsdStage) throws -> T
) throws -> T {
    let stageReference = UsdStage.Open(
        std.string(stageURL.url.path),
        UsdStage.InitialLoadSet.LoadAll
    )
    guard stageReference._isNonnull() else {
        throw SwiftUsdShellError.stageOpenFailed(stageURL, diagnostic: nil)
    }
    return try body(USDOverlay.Dereference(stageReference))
}
