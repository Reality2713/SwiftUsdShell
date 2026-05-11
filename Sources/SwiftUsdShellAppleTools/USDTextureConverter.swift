import Foundation
import SwiftUsdShell
#if canImport(CAppleTextureConverterBridgeShell)
import CAppleTextureConverterBridgeShell
#endif

public struct USDTextureConverter: Sendable {
    public init() {}

    public var isAvailable: Bool {
        #if canImport(CAppleTextureConverterBridgeShell)
        ATCBridge_IsAvailable()
        #else
        false
        #endif
    }

    public func compressToFormat(_ request: USDTextureCompressRequest) -> USDTextureCompressResult {
        #if canImport(CAppleTextureConverterBridgeShell)
        withBridgeMessageBuffer { errorBuf, size in
            let ok = ATCBridge_CompressToFormat(
                (request.inputURL.path as NSString).fileSystemRepresentation,
                (request.outputURL.path as NSString).fileSystemRepresentation,
                UInt32(mapCompressionFormat(request.compressionFormat)),
                UInt32(mapASTCBlockSize(request.astcBlockSize)),
                UInt32(mapQuality(request.quality)),
                UInt32(request.maxDimension ?? 0),
                request.generateMipmaps,
                UInt32(mapGamut(request.gamutIn)),
                UInt32(mapGamut(request.gamutOut)),
                errorBuf,
                size
            )
            if ok {
                return USDTextureCompressResult(success: true, outputURL: request.outputURL)
            }
            let msg = String(cString: errorBuf)
            return USDTextureCompressResult(success: false, diagnosticMessage: msg.isEmpty ? nil : msg)
        }
        #else
        return USDTextureCompressResult(success: false, diagnosticMessage: "ATC bridge not compiled in")
        #endif
    }

    public func generateMipmaps(
        inputURL: URL, outputURL: URL,
        compressionFormat: USDTextureCompressionFormat = .astc,
        astcBlockSize: USDTextureASTCBlockSize = .b8x8,
        quality: USDTextureConvertQuality = .balanced,
        maxDimension: Int? = nil,
        mipmapFilter: USDTextureMipmapFilter = .kaiser,
        gamutIn: USDTextureColorGamut = .unknown,
        gamutOut: USDTextureColorGamut = .unknown
    ) -> USDTextureCompressResult {
        #if canImport(CAppleTextureConverterBridgeShell)
        withBridgeMessageBuffer { errorBuf, size in
            let ok = ATCBridge_GenerateMipmaps(
                (inputURL.path as NSString).fileSystemRepresentation,
                (outputURL.path as NSString).fileSystemRepresentation,
                UInt32(mapCompressionFormat(compressionFormat)),
                UInt32(mapASTCBlockSize(astcBlockSize)),
                UInt32(mapQuality(quality)),
                UInt32(maxDimension ?? 0),
                UInt32(mapMipmapFilter(mipmapFilter)),
                UInt32(mapGamut(gamutIn)),
                UInt32(mapGamut(gamutOut)),
                errorBuf,
                size
            )
            if ok {
                return USDTextureCompressResult(success: true, outputURL: outputURL)
            }
            let msg = String(cString: errorBuf)
            return USDTextureCompressResult(success: false, diagnosticMessage: msg.isEmpty ? nil : msg)
        }
        #else
        return USDTextureCompressResult(success: false, diagnosticMessage: "ATC bridge not compiled in")
        #endif
    }
}

// MARK: - Helpers

private func withBridgeMessageBuffer<T>(
    _ body: (UnsafeMutablePointer<CChar>, Int) -> T
) -> T {
    let size = 4096
    let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: size)
    buffer.initialize(repeating: 0, count: size)
    defer { buffer.deallocate() }
    return body(buffer, size)
}

private func mapCompressionFormat(_ f: USDTextureCompressionFormat) -> Int {
    switch f {
    case .astc: return 0
    case .bc7: return 1
    case .etc2RGBA: return 2
    }
}

private func mapASTCBlockSize(_ b: USDTextureASTCBlockSize) -> Int {
    switch b {
    case .b4x4: return 0
    case .b6x6: return 1
    case .b8x8: return 2
    case .b10x10: return 3
    case .b12x12: return 4
    }
}

private func mapQuality(_ q: USDTextureConvertQuality) -> Int {
    switch q {
    case .fast: return 0
    case .balanced: return 1
    case .best: return 2
    }
}

private func mapGamut(_ g: USDTextureColorGamut) -> Int {
    switch g {
    case .unknown: return 0
    case .none: return 1
    case .displayP3: return 2
    case .sRGB: return 3
    }
}

private func mapMipmapFilter(_ f: USDTextureMipmapFilter) -> Int {
    switch f {
    case .box: return 0
    case .triangle: return 1
    case .kaiser: return 2
    }
}
