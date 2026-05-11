public enum USDTextureCompressionFormat: String, Equatable, Hashable, Sendable, Codable {
    case astc, bc7, etc2RGBA
}

public enum USDTextureASTCBlockSize: String, Equatable, Hashable, Sendable, Codable {
    case b4x4, b6x6, b8x8, b10x10, b12x12
}

public enum USDTextureColorGamut: String, Equatable, Hashable, Sendable, Codable {
    case unknown, none, sRGB, displayP3
}

public enum USDTextureMipmapFilter: String, Equatable, Hashable, Sendable, Codable {
    case box, triangle, kaiser
}

public enum USDTextureResizeFilter: String, Equatable, Hashable, Sendable, Codable {
    case box, triangle, kaiser, mitchell
}

public enum USDTextureResizeRoundMode: String, Equatable, Hashable, Sendable, Codable {
    case none, nextPowerOfTwo, nearestPowerOfTwo, previousPowerOfTwo
    case nextMultipleOfFour, nearestMultipleOfFour, previousMultipleOfFour
}

public enum USDTextureConvertQuality: String, Equatable, Hashable, Sendable, Codable {
    case fast, balanced, best
}

public struct USDTextureCompressRequest: Equatable, Hashable, Sendable {
    public var inputURL: URL
    public var outputURL: URL
    public var compressionFormat: USDTextureCompressionFormat
    public var astcBlockSize: USDTextureASTCBlockSize
    public var quality: USDTextureConvertQuality
    public var maxDimension: Int?
    public var generateMipmaps: Bool
    public var gamutIn: USDTextureColorGamut
    public var gamutOut: USDTextureColorGamut
    public init(inputURL: URL, outputURL: URL,
                compressionFormat: USDTextureCompressionFormat = .astc,
                astcBlockSize: USDTextureASTCBlockSize = .b8x8,
                quality: USDTextureConvertQuality = .balanced,
                maxDimension: Int? = nil, generateMipmaps: Bool = true,
                gamutIn: USDTextureColorGamut = .unknown,
                gamutOut: USDTextureColorGamut = .unknown) {
        self.inputURL = inputURL; self.outputURL = outputURL
        self.compressionFormat = compressionFormat; self.astcBlockSize = astcBlockSize
        self.quality = quality; self.maxDimension = maxDimension
        self.generateMipmaps = generateMipmaps; self.gamutIn = gamutIn; self.gamutOut = gamutOut
    }
}

public struct USDTextureCompressResult: Equatable, Sendable {
    public var success: Bool
    public var outputURL: URL?
    public var diagnosticMessage: String?
    public init(success: Bool, outputURL: URL? = nil, diagnosticMessage: String? = nil) {
        self.success = success; self.outputURL = outputURL; self.diagnosticMessage = diagnosticMessage
    }
}
