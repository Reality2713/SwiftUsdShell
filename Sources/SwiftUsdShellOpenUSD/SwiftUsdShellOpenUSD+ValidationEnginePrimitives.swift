import CxxStdlib
import Foundation
internal import OpenUSD
import SwiftUsdShell

/// Missing canonical feature providers on one `UsdVolParticleField`.
public struct USDParticleFieldRequirementsIssue: Hashable, Sendable, Codable {
    public static let positionFeature: UInt8 = 1 << 0
    public static let kernelFeature: UInt8 = 1 << 1
    public static let radianceFeature: UInt8 = 1 << 2

    public var primPath: USDPath
    public var missingFeatures: UInt8

    public init(primPath: USDPath, missingFeatures: UInt8) {
        self.primPath = primPath
        self.missingFeatures = missingFeatures
    }
}

/// The canonical way to normalize authored physics-joint body targets.
public enum USDJointBodyTargetNormalization: Hashable, Sendable, Codable {
    /// Retain the first authored target and discard additional targets.
    case keepFirst
    /// Retain every target that resolves to a prim on the composed stage.
    case removeMissing
}

public extension OpenUSDStageRuntime {
    /// The `PXR_VERSION` number compiled into the linked OpenUSD runtime.
    static var openUSDVersionNumber: Int {
        Int(PXR_VERSION)
    }

    /// Finds particle fields missing any canonical usdVol base feature API.
    func incompleteParticleFieldRequirements(
        stageURL: USDStageURL
    ) throws -> [USDParticleFieldRequirementsIssue] {
        let stagePtr = UsdStage.Open(
            std.string(stageURL.url.path),
            UsdStage.InitialLoadSet.LoadAll
        )
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stageURL, diagnostic: nil)
        }
        let stage = USDOverlay.Dereference(stagePtr)
        var issues: [USDParticleFieldRequirementsIssue] = []

        for prim in stage.Traverse().swiftSequence {
            guard Bool(pxr.UsdVolParticleField(prim)) else { continue }
            var missingFeatures: UInt8 = 0
            if !Bool(pxr.UsdVolParticleFieldPositionBaseAPI(prim)) {
                missingFeatures |= USDParticleFieldRequirementsIssue.positionFeature
            }
            if !Bool(pxr.UsdVolParticleFieldKernelBaseAPI(prim)) {
                missingFeatures |= USDParticleFieldRequirementsIssue.kernelFeature
            }
            if !Bool(pxr.UsdVolParticleFieldRadianceBaseAPI(prim)) {
                missingFeatures |= USDParticleFieldRequirementsIssue.radianceFeature
            }
            if missingFeatures != 0 {
                issues.append(
                    USDParticleFieldRequirementsIssue(
                        primPath: USDPath(
                            validationOwnedString(prim.GetPath().GetAsString())
                        ),
                        missingFeatures: missingFeatures
                    )
                )
            }
        }
        return issues
    }

    /// Returns the canonical Sdr input type when the authored default value can
    /// be retyped losslessly. Animated properties deliberately return `nil`.
    func expectedShaderInputType(
        stageURL: USDStageURL,
        propertyPath: USDPath
    ) throws -> String? {
        let stagePtr = UsdStage.Open(
            std.string(stageURL.url.path),
            UsdStage.InitialLoadSet.LoadAll
        )
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stageURL, diagnostic: nil)
        }
        let stage = USDOverlay.Dereference(stagePtr)
        let sitePath = SdfPath(std.string(propertyPath.rawValue))
        guard sitePath.IsPropertyPath() else { return nil }

        let propertyName = validationOwnedString(
            USDOverlay.SdfPathName(sitePath)
        )
        let inputPrefix = "inputs:"
        guard propertyName.hasPrefix(inputPrefix) else { return nil }
        let inputName = String(propertyName.dropFirst(inputPrefix.count))
        guard !inputName.isEmpty else { return nil }

        let prim = stage.GetPrimAtPath(sitePath.GetPrimPath())
        let shader = UsdShadeShader(prim)
        guard Bool(shader) else { return nil }

        var shaderIdentifier = TfToken()
        guard shader.GetShaderId(&shaderIdentifier) else { return nil }
        var targetType = SdfValueTypeName()
        guard USDOverlay.SdrShaderInputSdfType(
            shaderIdentifier,
            TfToken(std.string(inputName)),
            &targetType
        ) else {
            return nil
        }
        let attribute = prim.GetAttribute(TfToken(std.string(propertyName)))
        guard
            attribute.IsValid(),
            validationIsLosslessShaderRetype(
                source: attribute.GetTypeName(),
                target: targetType
            )
        else {
            return nil
        }

        var timeSamples = USDOverlay.Double_Vector()
        guard attribute.GetTimeSamples(&timeSamples), timeSamples.empty() else {
            return nil
        }
        return validationOwnedString(targetType.GetAsToken().GetString())
    }

    /// Inlines compatible Material-interface values into one
    /// `UsdPreviewSurface` shader on the supplied repair copy.
    @discardableResult
    func inlineMaterialInputs(
        stageURL: USDStageURL,
        materialPath: USDPath
    ) throws -> Int {
        let stagePtr = UsdStage.Open(
            std.string(stageURL.url.path),
            UsdStage.InitialLoadSet.LoadAll
        )
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stageURL, diagnostic: nil)
        }
        let stage = USDOverlay.Dereference(stagePtr)
        let materialPrim = stage.GetPrimAtPath(
            SdfPath(std.string(materialPath.rawValue))
        )
        guard materialPrim.IsValid() else {
            throw SwiftUsdShellError.primNotFound(
                stageURL: stageURL,
                primPath: materialPath
            )
        }
        let material = UsdShadeMaterial(materialPrim)
        guard Bool(material) else { return 0 }
        let surfaceShader = material.ComputeSurfaceSource(
            TfToken(),
            nil as UnsafeMutablePointer<TfToken>?,
            nil as UnsafeMutablePointer<UsdShadeAttributeType>?
        )
        guard Bool(surfaceShader) else { return 0 }

        var shaderIdentifier = TfToken()
        guard
            surfaceShader.GetShaderId(&shaderIdentifier),
            shaderIdentifier == TfToken("UsdPreviewSurface")
        else {
            return 0
        }

        let inputNames = [
            "diffuseColor", "emissiveColor", "specularColor",
            "metallic", "roughness", "opacity",
        ]
        var changedCount = 0
        for inputName in inputNames {
            var shaderInput = surfaceShader.GetInput(
                TfToken(std.string(inputName))
            )
            guard Bool(shaderInput) else { continue }
            let sources = shaderInput.GetConnectedSources(
                nil as UnsafeMutablePointer<SdfPathVector>?
            )
            guard sources.size() == 1 else { continue }
            let source = sources[0]
            guard
                source.sourceType == UsdShadeAttributeType.Input,
                USDOverlay.GetPrim(source.source) == materialPrim
            else {
                continue
            }

            let materialInput = source.source.GetInput(source.sourceName)
            guard
                Bool(materialInput),
                validationIsCompatibleMaterialInterfaceType(
                    shaderInputName: inputName,
                    sourceType: materialInput.GetAttr().GetTypeName()
                )
            else {
                continue
            }

            let sourceAttribute = materialInput.GetAttr()
            let timeSampleCount = sourceAttribute.GetNumTimeSamples()
            guard timeSampleCount <= 1 else { continue }
            var timeCode = UsdTimeCode.Default()
            if timeSampleCount == 1 {
                var sampleTimes = USDOverlay.Double_Vector()
                guard
                    sourceAttribute.GetTimeSamples(&sampleTimes),
                    sampleTimes.size() == 1
                else {
                    continue
                }
                timeCode = UsdTimeCode(sampleTimes[0])
            }

            var value = VtValue()
            guard
                sourceAttribute.Get(&value, timeCode),
                !value.IsEmpty(),
                shaderInput.Set(value, timeCode),
                shaderInput.ClearSources()
            else {
                continue
            }
            changedCount += 1
        }

        if changedCount > 0 {
            stage.Save()
        }
        return changedCount
    }

    /// Removes one applied API schema from the supplied repair copy.
    func removeAppliedAPISchema(
        stageURL: USDStageURL,
        primPath: USDPath,
        schemaName: USDToken
    ) throws {
        let stagePtr = UsdStage.Open(
            std.string(stageURL.url.path),
            UsdStage.InitialLoadSet.LoadAll
        )
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stageURL, diagnostic: nil)
        }
        let stage = USDOverlay.Dereference(stagePtr)
        let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
        guard prim.IsValid() else {
            throw SwiftUsdShellError.primNotFound(
                stageURL: stageURL,
                primPath: primPath
            )
        }
        guard prim.RemoveAPI(TfToken(std.string(schemaName.rawValue))) else {
            throw SwiftUsdShellError.invalidValue(
                "Could not remove API schema \(schemaName.rawValue) from \(primPath.rawValue)"
            )
        }
        stage.Save()
    }

    /// Moves a nested shader to a collision-free sibling path, removes the old
    /// prim, and rewires authored attribute connections and relationship
    /// targets that point into the old subtree.
    @discardableResult
    func flattenNestedShaderInPlace(
        stageURL: USDStageURL,
        parentPath: USDPath,
        childPath: USDPath
    ) throws -> USDPath {
        let stagePtr = UsdStage.Open(
            std.string(stageURL.url.path),
            UsdStage.InitialLoadSet.LoadAll
        )
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stageURL, diagnostic: nil)
        }
        let stage = USDOverlay.Dereference(stagePtr)
        let oldPath = SdfPath(std.string(childPath.rawValue))
        let oldParentPath = SdfPath(std.string(parentPath.rawValue))
        guard
            stage.GetPrimAtPath(oldPath).IsValid(),
            stage.GetPrimAtPath(oldParentPath).IsValid()
        else {
            throw SwiftUsdShellError.invalidValue(
                "Nested shader or its parent does not exist."
            )
        }

        let destinationParent = oldParentPath.GetParentPath()
        let childName =
            childPath.rawValue.split(separator: "/").last.map(String.init)
            ?? "Shader"
        var destination = destinationParent.AppendChild(
            TfToken(std.string(childName))
        )
        if destination == oldPath || stage.GetPrimAtPath(destination).IsValid() {
            destination = destinationParent.AppendChild(
                TfToken(std.string("\(childName)_flattened"))
            )
            var index = 2
            while stage.GetPrimAtPath(destination).IsValid() {
                destination = destinationParent.AppendChild(
                    TfToken(std.string("\(childName)_flattened\(index)"))
                )
                index += 1
            }
        }

        let rootLayer = stage.GetRootLayer()
        guard pxr.SdfCopySpec(rootLayer, oldPath, rootLayer, destination) else {
            throw SwiftUsdShellError.invalidValue(
                "Could not copy \(childPath.rawValue) to its flattened path."
            )
        }
        _ = stage.RemovePrim(oldPath)
        validationRewirePathConsumers(
            stage: stage,
            oldPath: oldPath,
            newPath: destination
        )
        stage.Save()
        return USDPath(validationOwnedString(destination.GetAsString()))
    }

    /// Normalizes `physics:body0` and `physics:body1` targets on one joint.
    func normalizeJointBodyTargets(
        stageURL: USDStageURL,
        primPath: USDPath,
        normalization: USDJointBodyTargetNormalization
    ) throws {
        let stagePtr = UsdStage.Open(
            std.string(stageURL.url.path),
            UsdStage.InitialLoadSet.LoadAll
        )
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stageURL, diagnostic: nil)
        }
        let stage = USDOverlay.Dereference(stagePtr)
        let prim = stage.GetPrimAtPath(SdfPath(std.string(primPath.rawValue)))
        guard prim.IsValid() else {
            throw SwiftUsdShellError.primNotFound(
                stageURL: stageURL,
                primPath: primPath
            )
        }

        for relationshipName in ["physics:body0", "physics:body1"] {
            var relationship = prim.GetRelationship(
                TfToken(std.string(relationshipName))
            )
            guard
                relationship.IsValid(),
                relationship.HasAuthoredTargets()
            else {
                continue
            }
            var targets = SdfPathVector()
            guard relationship.GetTargets(&targets) else { continue }

            var kept = SdfPathVector()
            var changed = false
            switch normalization {
            case .keepFirst:
                guard targets.size() > 1 else { continue }
                kept.push_back(targets[0])
                changed = true
            case .removeMissing:
                for target in targets {
                    if stage.GetPrimAtPath(target).IsValid() {
                        kept.push_back(target)
                    } else {
                        changed = true
                    }
                }
            }
            if changed {
                _ = relationship.SetTargets(kept)
            }
        }
        stage.Save()
    }

    /// Removes unresolved authored payload arcs matching `requestedAssetPath`.
    /// An empty request deliberately considers every unresolved payload.
    @discardableResult
    func removeUnresolvedPayloads(
        stageURL: USDStageURL,
        requestedAssetPath: String
    ) throws -> Int {
        let stagePtr = UsdStage.Open(
            std.string(stageURL.url.path),
            UsdStage.InitialLoadSet.LoadAll
        )
        guard stagePtr._isNonnull() else {
            throw SwiftUsdShellError.stageOpenFailed(stageURL, diagnostic: nil)
        }
        let stage = USDOverlay.Dereference(stagePtr)
        let resolverContextBinder = pxr.ArResolverContextBinder(
            stage.GetPathResolverContext()
        )
        let resolver = USDOverlay.ArGetResolver()
        let requestedBasename = URL(
            fileURLWithPath: requestedAssetPath
        ).lastPathComponent
        var removedCount = 0

        withExtendedLifetime(resolverContextBinder) {
            for prim in UsdPrimRange.AllPrims(stage.GetPseudoRoot()).swiftSequence {
                var candidates: [pxr.SdfPayload] = []
                for specHandle in prim.GetPrimStack() {
                    let spec = specHandle.pointee
                    for payload in spec.GetPayloadList().GetAppliedItems() {
                        let assetPath = validationOwnedString(
                            USDOverlay.SdfPayloadAssetPath(payload)
                        )
                        guard !assetPath.isEmpty else { continue }
                        let anchoredPath = validationOwnedString(
                            pxr.SdfComputeAssetPathRelativeToLayer(
                                spec.GetLayer(),
                                std.string(assetPath)
                            )
                        )
                        let matchesRequest =
                            requestedAssetPath.isEmpty
                            || assetPath == requestedAssetPath
                            || anchoredPath == requestedAssetPath
                            || URL(fileURLWithPath: assetPath).lastPathComponent
                                == requestedBasename
                        guard
                            matchesRequest,
                            resolver.Resolve(std.string(anchoredPath)).IsEmpty(),
                            !candidates.contains(payload)
                        else {
                            continue
                        }
                        candidates.append(payload)
                    }
                }
                var payloads = prim.GetPayloads()
                for payload in candidates where payloads.RemovePayload(payload) {
                    removedCount += 1
                }
            }
        }
        if removedCount > 0 {
            stage.Save()
        }
        return removedCount
    }
}

private func validationRewirePathConsumers(
    stage: UsdStage,
    oldPath: SdfPath,
    newPath: SdfPath
) {
    for prim in UsdPrimRange.AllPrims(stage.GetPseudoRoot()).swiftSequence {
        for attributeValue in prim.GetAttributes()
        where attributeValue.HasAuthoredConnections() {
            var attribute = attributeValue
            var paths = SdfPathVector()
            guard attribute.GetConnections(&paths) else { continue }
            var rewritten = SdfPathVector()
            var changed = false
            for path in paths {
                if path == oldPath || path.HasPrefix(oldPath) {
                    rewritten.push_back(
                        path.ReplacePrefix(oldPath, newPath, true)
                    )
                    changed = true
                } else {
                    rewritten.push_back(path)
                }
            }
            if changed {
                _ = attribute.SetConnections(rewritten)
            }
        }

        for relationshipValue in prim.GetRelationships()
        where relationshipValue.HasAuthoredTargets() {
            var relationship = relationshipValue
            var paths = SdfPathVector()
            guard relationship.GetTargets(&paths) else { continue }
            var rewritten = SdfPathVector()
            var changed = false
            for path in paths {
                if path == oldPath || path.HasPrefix(oldPath) {
                    rewritten.push_back(
                        path.ReplacePrefix(oldPath, newPath, true)
                    )
                    changed = true
                } else {
                    rewritten.push_back(path)
                }
            }
            if changed {
                _ = relationship.SetTargets(rewritten)
            }
        }
    }
}

private func validationIsLosslessShaderRetype(
    source: SdfValueTypeName,
    target: SdfValueTypeName
) -> Bool {
    if source == target {
        return true
    }
    if
        (source == SdfValueTypeName.String && target == SdfValueTypeName.Token)
        || (source == SdfValueTypeName.Token && target == SdfValueTypeName.String)
    {
        return true
    }
    return
        (validationIsFloat2Storage(source)
            && validationIsFloat2Storage(target))
        || (validationIsFloat3Storage(source)
            && validationIsFloat3Storage(target))
        || (validationIsFloat4Storage(source)
            && validationIsFloat4Storage(target))
}

private func validationIsFloat2Storage(_ type: SdfValueTypeName) -> Bool {
    type == SdfValueTypeName.Float2 || type == SdfValueTypeName.TexCoord2f
}

private func validationIsFloat3Storage(_ type: SdfValueTypeName) -> Bool {
    type == SdfValueTypeName.Float3
        || type == SdfValueTypeName.Color3f
        || type == SdfValueTypeName.Normal3f
        || type == SdfValueTypeName.Point3f
        || type == SdfValueTypeName.Vector3f
        || type == SdfValueTypeName.TexCoord3f
}

private func validationIsFloat4Storage(_ type: SdfValueTypeName) -> Bool {
    type == SdfValueTypeName.Float4 || type == SdfValueTypeName.Color4f
}

private func validationIsCompatibleMaterialInterfaceType(
    shaderInputName: String,
    sourceType: SdfValueTypeName
) -> Bool {
    if ["diffuseColor", "emissiveColor", "specularColor"]
        .contains(shaderInputName)
    {
        return sourceType == SdfValueTypeName.Color3f
            || sourceType == SdfValueTypeName.Float3
    }
    return sourceType == SdfValueTypeName.Float
        || sourceType == SdfValueTypeName.Double
        || sourceType == SdfValueTypeName.Half
}

private func validationOwnedString<T>(_ value: T) -> String {
    String(describing: value)
}
