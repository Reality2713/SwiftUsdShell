import CxxStdlib
import Foundation
internal import OpenUSD
import SwiftUsdShell

/// A typed request for OpenUSD's arc-preserving layer-stack flatten operation.
///
/// This is equivalent to `usdcat --flattenLayerStack`: local layer-stack
/// opinions are merged while references, payloads, and variants remain arcs.
public struct USDArcPreservingExportRequest: Hashable, Sendable, Codable {
    public var sourceURL: USDStageURL
    public var destinationURL: USDStageURL
    public var tag: String

    public init(
        sourceURL: USDStageURL,
        destinationURL: USDStageURL,
        tag: String = "SwiftUsdShell"
    ) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.tag = tag
    }
}

/// The output of one successful arc-preserving export.
public struct USDArcPreservingExportResult: Hashable, Sendable, Codable {
    public var destinationURL: USDStageURL

    public init(destinationURL: USDStageURL) {
        self.destinationURL = destinationURL
    }
}

/// Mechanical failures emitted by the arc-export primitives.
public enum USDArcExportPrimitiveError: Error, Equatable, Sendable, Codable {
    case stageOpenFailed(USDStageURL)
    case flattenLayerStackFailed(USDStageURL)
    case exportFailed(USDStageURL)
}

extension OpenUSDStageRuntime {
    /// Flattens only the local layer stack and exports it through the destination
    /// file format, preserving external composition arcs.
    public func exportArcPreserving(
        _ request: USDArcPreservingExportRequest
    ) throws -> USDArcPreservingExportResult {
        let sourcePath = std.string(request.sourceURL.url.path)
        let resolver = USDOverlay.ArGetResolver()
        let resolverContext = resolver.CreateDefaultContextForAsset(sourcePath)
        let stagePtr = UsdStage.Open(
            sourcePath,
            resolverContext,
            UsdStage.InitialLoadSet.LoadAll
        )
        guard stagePtr._isNonnull() else {
            throw USDArcExportPrimitiveError.stageOpenFailed(request.sourceURL)
        }

        let stage = USDOverlay.Dereference(stagePtr)
        stage.Reload()

        let flattenedPtr = pxr.UsdUtilsFlattenLayerStack(
            USDOverlay.TfWeakPtr(stage),
            std.string(request.tag)
        )
        guard flattenedPtr._isNonnull() else {
            throw USDArcExportPrimitiveError.flattenLayerStackFailed(request.sourceURL)
        }

        let flattened = USDOverlay.Dereference(flattenedPtr)
        guard flattened.Export(
            std.string(request.destinationURL.url.path),
            std.string(),
            SdfLayer.FileFormatArguments()
        ) else {
            throw USDArcExportPrimitiveError.exportFailed(request.destinationURL)
        }

        return USDArcPreservingExportResult(destinationURL: request.destinationURL)
    }
}
