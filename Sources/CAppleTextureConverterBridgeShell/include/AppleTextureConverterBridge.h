#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns true when the bridge was compiled with AppleTextureConverter available.
bool ATCBridge_IsAvailable(void);

typedef enum ATCBridgeCompressionFormat {
    ATCBridgeCompressionFormatASTC = 0,
    ATCBridgeCompressionFormatBC7 = 1,
    ATCBridgeCompressionFormatETC2RGBA = 2
} ATCBridgeCompressionFormat;

typedef enum ATCBridgeASTCBlockSize {
    ATCBridgeASTCBlock4x4 = 0,
    ATCBridgeASTCBlock6x6 = 1,
    ATCBridgeASTCBlock8x8 = 2,
    ATCBridgeASTCBlock10x10 = 3,
    ATCBridgeASTCBlock12x12 = 4
} ATCBridgeASTCBlockSize;

typedef enum ATCBridgeColorGamut {
    ATCBridgeColorGamutUnknown = 0,
    ATCBridgeColorGamutNone = 1,
    ATCBridgeColorGamutDisplayP3 = 2,
    ATCBridgeColorGamutSRGB = 3
} ATCBridgeColorGamut;

typedef enum ATCBridgeMipmapFilter {
    ATCBridgeMipmapFilterBox = 0,
    ATCBridgeMipmapFilterTriangle = 1,
    ATCBridgeMipmapFilterKaiser = 2
} ATCBridgeMipmapFilter;

typedef enum ATCBridgeResizeFilter {
    ATCBridgeResizeFilterBox = 0,
    ATCBridgeResizeFilterTriangle = 1,
    ATCBridgeResizeFilterKaiser = 2,
    ATCBridgeResizeFilterMitchell = 3
} ATCBridgeResizeFilter;

typedef enum ATCBridgeResizeRoundMode {
    ATCBridgeResizeRoundModeNone = 0,
    ATCBridgeResizeRoundModeNextPowerOfTwo = 1,
    ATCBridgeResizeRoundModeNearestPowerOfTwo = 2,
    ATCBridgeResizeRoundModePreviousPowerOfTwo = 3,
    ATCBridgeResizeRoundModeNextMultipleOfFour = 4,
    ATCBridgeResizeRoundModeNearestMultipleOfFour = 5,
    ATCBridgeResizeRoundModePreviousMultipleOfFour = 6
} ATCBridgeResizeRoundMode;

typedef struct ATCBridgeCompareMetrics {
    double mse;
    double psnr;
    double rms;
    bool texturesAreIdentical;
} ATCBridgeCompareMetrics;

// Generic file compression entry point.
// qualityLevel: 0=fast, 1=balanced, 2=best
// maxExtent: 0 keeps source dimensions
// generateMipmaps: true to generate mipmaps, false for base level only
bool ATCBridge_CompressToFormat(
    const char *inputPath,
    const char *outputPath,
    uint32_t compressionFormat,
    uint32_t astcBlockSize,
    uint32_t qualityLevel,
    uint32_t maxExtent,
    bool generateMipmaps,
    uint32_t gamutIn,
    uint32_t gamutOut,
    char *errorMessage,
    size_t errorMessageSize
);

// Backward-compatible alias for ATCBridge_CompressToFormat.
bool ATCBridge_Compress(
    const char *inputPath,
    const char *outputPath,
    uint32_t compressionFormat,
    uint32_t astcBlockSize,
    uint32_t qualityLevel,
    uint32_t maxExtent,
    bool generateMipmaps,
    uint32_t gamutIn,
    uint32_t gamutOut,
    char *errorMessage,
    size_t errorMessageSize
);

// Backward-compatible KTX2 helper.
bool ATCBridge_CompressFileKTX2(
    const char *inputPath,
    const char *outputPath,
    uint32_t qualityLevel,
    uint32_t maxExtent,
    bool generateMipmaps,
    char *errorMessage,
    size_t errorMessageSize
);

// Generates mipmaps with professional filtering and writes output texture file.
bool ATCBridge_GenerateMipmaps(
    const char *inputPath,
    const char *outputPath,
    uint32_t compressionFormat,
    uint32_t astcBlockSize,
    uint32_t qualityLevel,
    uint32_t maxExtent,
    uint32_t mipmapFilter,
    uint32_t gamutIn,
    uint32_t gamutOut,
    char *errorMessage,
    size_t errorMessageSize
);

// Resizes texture with ATC filters and optional POT/alignment rounding.
bool ATCBridge_ResizeWithFilter(
    const char *inputPath,
    const char *outputPath,
    uint32_t maxExtent,
    uint32_t resizeFilter,
    uint32_t resizeRoundMode,
    uint32_t qualityLevel,
    uint32_t gamutIn,
    uint32_t gamutOut,
    char *errorMessage,
    size_t errorMessageSize
);

// Decompresses a compressed texture file to an uncompressed output file.
bool ATCBridge_DecompressFile(
    const char *inputPath,
    const char *outputPath,
    char *errorMessage,
    size_t errorMessageSize
);

// Compares two texture files and returns quality metrics.
bool ATCBridge_CompareFiles(
    const char *referencePath,
    const char *comparisonPath,
    ATCBridgeCompareMetrics *outMetrics,
    char *errorMessage,
    size_t errorMessageSize
);

// Converts the color gamut while preserving uncompressed output.
bool ATCBridge_ConvertGamut(
    const char *inputPath,
    const char *outputPath,
    uint32_t gamutIn,
    uint32_t gamutOut,
    char *errorMessage,
    size_t errorMessageSize
);

// Compresses RGBA8 memory to compressed payload memory (mip 0 surface payload).
bool ATCBridge_CompressMemory(
    const uint8_t *rgba8Data,
    uint32_t width,
    uint32_t height,
    uint32_t bytesPerRow,
    uint32_t compressionFormat,
    uint32_t astcBlockSize,
    uint32_t qualityLevel,
    uint32_t maxExtent,
    bool generateMipmaps,
    uint32_t gamutIn,
    uint32_t gamutOut,
    uint8_t **outData,
    size_t *outDataSize,
    uint32_t *outWidth,
    uint32_t *outHeight,
    uint32_t *outMipLevels,
    char *errorMessage,
    size_t errorMessageSize
);

// Frees buffers returned from bridge APIs.
void ATCBridge_FreeBuffer(uint8_t *buffer);

#ifdef __cplusplus
}
#endif
