#include "AppleTextureConverterBridge.h"

#include <stdlib.h>
#include <stdio.h>
#include <strings.h>
#include <string.h>

#if defined(ATC_BRIDGE_ENABLED)
#include <AppleTextureConverter.h>
#endif

static void copyMessage(char *dest, size_t size, const char *message) {
    if (dest == NULL || size == 0) {
        return;
    }
    if (message == NULL) {
        dest[0] = '\0';
        return;
    }
    snprintf(dest, size, "%s", message);
}

static uint32_t chooseASTCBlockFromExtent(uint32_t maxExtent) {
    if (maxExtent > 0 && maxExtent <= 1024) {
        return ATCBridgeASTCBlock4x4;
    }
    if (maxExtent > 0 && maxExtent <= 2048) {
        return ATCBridgeASTCBlock6x6;
    }
    return ATCBridgeASTCBlock8x8;
}

#if defined(ATC_BRIDGE_ENABLED)
static ATC_Quality mapQuality(uint32_t qualityLevel) {
    switch (qualityLevel) {
    case 0:
        return atcQualityFastest;
    case 2:
        return atcQualityHighest;
    default:
        return atcQualityProduction;
    }
}

static ATC_Format mapASTCFormat(uint32_t blockSize) {
    switch (blockSize) {
    case ATCBridgeASTCBlock4x4:
        return atcFormatAstc4x4Unorm;
    case ATCBridgeASTCBlock6x6:
        return atcFormatAstc6x6Unorm;
    case ATCBridgeASTCBlock10x10:
        return atcFormatAstc10x10Unorm;
    case ATCBridgeASTCBlock12x12:
        return atcFormatAstc12x12Unorm;
    case ATCBridgeASTCBlock8x8:
    default:
        return atcFormatAstc8x8Unorm;
    }
}

static ATC_Format mapCompressionFormat(uint32_t compressionFormat, uint32_t astcBlockSize) {
    switch (compressionFormat) {
    case ATCBridgeCompressionFormatBC7:
        return atcFormatBc7Unorm;
    case ATCBridgeCompressionFormatETC2RGBA:
        return atcFormatEacRgba8Unorm;
    case ATCBridgeCompressionFormatASTC:
    default:
        return mapASTCFormat(astcBlockSize);
    }
}

static ATC_ColorGamut mapGamut(uint32_t gamut) {
    switch (gamut) {
    case ATCBridgeColorGamutNone:
        return atcColorGamutNone;
    case ATCBridgeColorGamutDisplayP3:
        return atcColorGamutDisplayP3;
    case ATCBridgeColorGamutSRGB:
        return atcColorGamutSRGB;
    case ATCBridgeColorGamutUnknown:
    default:
        return atcColorGamutUnknown;
    }
}

static ATC_MipmapFilter mapMipmapFilter(uint32_t filter) {
    switch (filter) {
    case ATCBridgeMipmapFilterBox:
        return atcMipmapFilterBox;
    case ATCBridgeMipmapFilterKaiser:
        return atcMipmapFilterKaiser;
    case ATCBridgeMipmapFilterTriangle:
    default:
        return atcMipmapFilterTriangle;
    }
}

static ATC_ResizeFilter mapResizeFilter(uint32_t filter) {
    switch (filter) {
    case ATCBridgeResizeFilterBox:
        return atcResizeFilterBox;
    case ATCBridgeResizeFilterKaiser:
        return atcResizeFilterKaiser;
    case ATCBridgeResizeFilterMitchell:
        return atcResizeFilterMitchell;
    case ATCBridgeResizeFilterTriangle:
    default:
        return atcResizeFilterTriangle;
    }
}

static ATC_RoundMode mapRoundMode(uint32_t mode) {
    switch (mode) {
    case ATCBridgeResizeRoundModeNextPowerOfTwo:
        return atcRoundModeNextPowerOfTwo;
    case ATCBridgeResizeRoundModeNearestPowerOfTwo:
        return atcRoundModeNearestPowerOfTwo;
    case ATCBridgeResizeRoundModePreviousPowerOfTwo:
        return atcRoundModePreviousPowerOfTwo;
    case ATCBridgeResizeRoundModeNextMultipleOfFour:
        return atcRoundModeNextMultipleOfFour;
    case ATCBridgeResizeRoundModeNearestMultipleOfFour:
        return atcRoundModeNearestMultipleOfFour;
    case ATCBridgeResizeRoundModePreviousMultipleOfFour:
        return atcRoundModePreviousMultipleOfFour;
    case ATCBridgeResizeRoundModeNone:
    default:
        return atcRoundModeNone;
    }
}

static ATC_FileFormat fileFormatForOutputPath(const char *outputPath) {
    if (outputPath == NULL) {
        return atcFileFormatAuto;
    }
    const char *dot = strrchr(outputPath, '.');
    if (dot == NULL || *(dot + 1) == '\0') {
        return atcFileFormatAuto;
    }
    const char *ext = dot + 1;
    if (strcasecmp(ext, "dds") == 0) {
        return atcFileFormatDDS;
    }
    if (strcasecmp(ext, "ktx") == 0) {
        return atcFileFormatKTX;
    }
    if (strcasecmp(ext, "ktx2") == 0) {
        return atcFileFormatKTX2;
    }
    if (strcasecmp(ext, "exr") == 0) {
        return atcFileFormatEXR;
    }
    return atcFileFormatAuto;
}

static const char *errorName(ATC_Error error) {
    switch (error) {
    case atcErrorNone:
        return "none";
    case atcErrorUnknown:
        return "unknown";
    case atcErrorInvalidContext:
        return "invalid_context";
    case atcErrorInvalidOptions:
        return "invalid_options";
    case atcErrorInvalidSourceTexture:
        return "invalid_source_texture";
    case atcErrorInvalidDestTexture:
        return "invalid_dest_texture";
    case atcErrorMemory:
        return "memory";
    default:
        return "other";
    }
}
#endif

static void setBridgeUnavailableMessage(char *errorMessage, size_t errorMessageSize) {
    copyMessage(errorMessage, errorMessageSize, "AppleTextureConverter bridge is not available in this build.");
}

bool ATCBridge_IsAvailable(void) {
#if defined(ATC_BRIDGE_ENABLED)
    return true;
#else
    return false;
#endif
}

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
) {
#if defined(ATC_BRIDGE_ENABLED)
    if (inputPath == NULL || outputPath == NULL) {
        copyMessage(errorMessage, errorMessageSize, "Input and output paths are required.");
        return false;
    }

    ATC_Options options;
    if (!ATC_InitialiseDefaultOptions(&options)) {
        copyMessage(errorMessage, errorMessageSize, "Failed to initialize AppleTextureConverter options.");
        return false;
    }

    options.format = mapCompressionFormat(compressionFormat, astcBlockSize);
    options.fileFormat = fileFormatForOutputPath(outputPath);
    options.quality = mapQuality(qualityLevel);
    options.maxExtent = maxExtent;
    options.maxMipmaps = generateMipmaps ? atcMaxMipMaps : 1;
    options.colorGamutIn = mapGamut(gamutIn);
    options.colorGamutOut = mapGamut(gamutOut);

    const ATC_Error result = ATC_CompressFile(NULL, inputPath, outputPath, &options);
    if (result != atcErrorNone) {
        char buffer[256];
        snprintf(buffer, sizeof(buffer), "AppleTextureConverter compression failed (%s).", errorName(result));
        copyMessage(errorMessage, errorMessageSize, buffer);
        return false;
    }

    copyMessage(errorMessage, errorMessageSize, "");
    return true;
#else
    (void)inputPath;
    (void)outputPath;
    (void)compressionFormat;
    (void)astcBlockSize;
    (void)qualityLevel;
    (void)maxExtent;
    (void)generateMipmaps;
    (void)gamutIn;
    (void)gamutOut;
    setBridgeUnavailableMessage(errorMessage, errorMessageSize);
    return false;
#endif
}

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
) {
    return ATCBridge_CompressToFormat(
        inputPath,
        outputPath,
        compressionFormat,
        astcBlockSize,
        qualityLevel,
        maxExtent,
        generateMipmaps,
        gamutIn,
        gamutOut,
        errorMessage,
        errorMessageSize
    );
}

bool ATCBridge_CompressFileKTX2(
    const char *inputPath,
    const char *outputPath,
    uint32_t qualityLevel,
    uint32_t maxExtent,
    bool generateMipmaps,
    char *errorMessage,
    size_t errorMessageSize
) {
    return ATCBridge_CompressToFormat(
        inputPath,
        outputPath,
        ATCBridgeCompressionFormatASTC,
        chooseASTCBlockFromExtent(maxExtent),
        qualityLevel,
        maxExtent,
        generateMipmaps,
        ATCBridgeColorGamutUnknown,
        ATCBridgeColorGamutUnknown,
        errorMessage,
        errorMessageSize
    );
}

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
) {
#if defined(ATC_BRIDGE_ENABLED)
    if (inputPath == NULL || outputPath == NULL) {
        copyMessage(errorMessage, errorMessageSize, "Input and output paths are required.");
        return false;
    }

    ATC_Options options;
    if (!ATC_InitialiseDefaultOptions(&options)) {
        copyMessage(errorMessage, errorMessageSize, "Failed to initialize AppleTextureConverter options.");
        return false;
    }

    options.format = mapCompressionFormat(compressionFormat, astcBlockSize);
    options.fileFormat = fileFormatForOutputPath(outputPath);
    options.quality = mapQuality(qualityLevel);
    options.maxExtent = maxExtent;
    options.maxMipmaps = atcMaxMipMaps;
    options.mipmapFilter = mapMipmapFilter(mipmapFilter);
    options.colorGamutIn = mapGamut(gamutIn);
    options.colorGamutOut = mapGamut(gamutOut);

    const ATC_Error result = ATC_CompressFile(NULL, inputPath, outputPath, &options);
    if (result != atcErrorNone) {
        char buffer[256];
        snprintf(buffer, sizeof(buffer), "AppleTextureConverter mipmap generation failed (%s).", errorName(result));
        copyMessage(errorMessage, errorMessageSize, buffer);
        return false;
    }

    copyMessage(errorMessage, errorMessageSize, "");
    return true;
#else
    (void)inputPath;
    (void)outputPath;
    (void)compressionFormat;
    (void)astcBlockSize;
    (void)qualityLevel;
    (void)maxExtent;
    (void)mipmapFilter;
    (void)gamutIn;
    (void)gamutOut;
    setBridgeUnavailableMessage(errorMessage, errorMessageSize);
    return false;
#endif
}

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
) {
#if defined(ATC_BRIDGE_ENABLED)
    if (inputPath == NULL || outputPath == NULL) {
        copyMessage(errorMessage, errorMessageSize, "Input and output paths are required.");
        return false;
    }

    ATC_Options options;
    if (!ATC_InitialiseDefaultOptions(&options)) {
        copyMessage(errorMessage, errorMessageSize, "Failed to initialize AppleTextureConverter options.");
        return false;
    }

    options.compressor = atcCompressorRaw;
    options.format = atcFormatRgba8Unorm;
    options.fileFormat = fileFormatForOutputPath(outputPath);
    options.quality = mapQuality(qualityLevel);
    options.maxExtent = maxExtent;
    options.resizeFilter = mapResizeFilter(resizeFilter);
    options.resizeRoundMode = mapRoundMode(resizeRoundMode);
    options.colorGamutIn = mapGamut(gamutIn);
    options.colorGamutOut = mapGamut(gamutOut);
    options.useSrgbFormat = (options.colorGamutOut == atcColorGamutSRGB);
    options.maxMipmaps = 1;

    const ATC_Error result = ATC_CompressFile(NULL, inputPath, outputPath, &options);
    if (result != atcErrorNone) {
        char buffer[256];
        snprintf(buffer, sizeof(buffer), "AppleTextureConverter resize failed (%s).", errorName(result));
        copyMessage(errorMessage, errorMessageSize, buffer);
        return false;
    }

    copyMessage(errorMessage, errorMessageSize, "");
    return true;
#else
    (void)inputPath;
    (void)outputPath;
    (void)maxExtent;
    (void)resizeFilter;
    (void)resizeRoundMode;
    (void)qualityLevel;
    (void)gamutIn;
    (void)gamutOut;
    setBridgeUnavailableMessage(errorMessage, errorMessageSize);
    return false;
#endif
}

bool ATCBridge_DecompressFile(
    const char *inputPath,
    const char *outputPath,
    char *errorMessage,
    size_t errorMessageSize
) {
#if defined(ATC_BRIDGE_ENABLED)
    if (inputPath == NULL || outputPath == NULL) {
        copyMessage(errorMessage, errorMessageSize, "Input and output paths are required.");
        return false;
    }

    ATC_Options options;
    if (!ATC_InitialiseDefaultOptions(&options)) {
        copyMessage(errorMessage, errorMessageSize, "Failed to initialize AppleTextureConverter options.");
        return false;
    }
    options.fileFormat = fileFormatForOutputPath(outputPath);

    const ATC_Error result = ATC_DecompressFile(NULL, inputPath, outputPath, &options);
    if (result != atcErrorNone) {
        char buffer[256];
        snprintf(buffer, sizeof(buffer), "AppleTextureConverter decompression failed (%s).", errorName(result));
        copyMessage(errorMessage, errorMessageSize, buffer);
        return false;
    }

    copyMessage(errorMessage, errorMessageSize, "");
    return true;
#else
    (void)inputPath;
    (void)outputPath;
    setBridgeUnavailableMessage(errorMessage, errorMessageSize);
    return false;
#endif
}

bool ATCBridge_CompareFiles(
    const char *referencePath,
    const char *comparisonPath,
    ATCBridgeCompareMetrics *outMetrics,
    char *errorMessage,
    size_t errorMessageSize
) {
#if defined(ATC_BRIDGE_ENABLED)
    if (referencePath == NULL || comparisonPath == NULL || outMetrics == NULL) {
        copyMessage(errorMessage, errorMessageSize, "Reference path, comparison path and output metrics are required.");
        return false;
    }

    ATC_Options options;
    if (!ATC_InitialiseDefaultOptions(&options)) {
        copyMessage(errorMessage, errorMessageSize, "Failed to initialize AppleTextureConverter options.");
        return false;
    }

    ATC_ErrorMetrics metrics;
    const ATC_Error result = ATC_CompareFile(NULL, referencePath, comparisonPath, &options, &metrics);
    if (result != atcErrorNone) {
        char buffer[256];
        snprintf(buffer, sizeof(buffer), "AppleTextureConverter compare failed (%s).", errorName(result));
        copyMessage(errorMessage, errorMessageSize, buffer);
        return false;
    }

    outMetrics->mse = metrics.MSE;
    outMetrics->psnr = metrics.PSNR;
    outMetrics->rms = metrics.RMS;
    outMetrics->texturesAreIdentical = metrics.bTexturesAreIdentical;
    copyMessage(errorMessage, errorMessageSize, "");
    return true;
#else
    (void)referencePath;
    (void)comparisonPath;
    if (outMetrics != NULL) {
        outMetrics->mse = 0.0;
        outMetrics->psnr = 0.0;
        outMetrics->rms = 0.0;
        outMetrics->texturesAreIdentical = false;
    }
    setBridgeUnavailableMessage(errorMessage, errorMessageSize);
    return false;
#endif
}

bool ATCBridge_ConvertGamut(
    const char *inputPath,
    const char *outputPath,
    uint32_t gamutIn,
    uint32_t gamutOut,
    char *errorMessage,
    size_t errorMessageSize
) {
#if defined(ATC_BRIDGE_ENABLED)
    if (inputPath == NULL || outputPath == NULL) {
        copyMessage(errorMessage, errorMessageSize, "Input and output paths are required.");
        return false;
    }

    ATC_Options options;
    if (!ATC_InitialiseDefaultOptions(&options)) {
        copyMessage(errorMessage, errorMessageSize, "Failed to initialize AppleTextureConverter options.");
        return false;
    }

    options.compressor = atcCompressorRaw;
    options.format = atcFormatRgba8Unorm;
    options.fileFormat = fileFormatForOutputPath(outputPath);
    options.colorGamutIn = mapGamut(gamutIn);
    options.colorGamutOut = mapGamut(gamutOut);
    options.useSrgbFormat = (options.colorGamutOut == atcColorGamutSRGB);

    const ATC_Error result = ATC_CompressFile(NULL, inputPath, outputPath, &options);
    if (result != atcErrorNone) {
        char buffer[256];
        snprintf(buffer, sizeof(buffer), "AppleTextureConverter gamut conversion failed (%s).", errorName(result));
        copyMessage(errorMessage, errorMessageSize, buffer);
        return false;
    }

    copyMessage(errorMessage, errorMessageSize, "");
    return true;
#else
    (void)inputPath;
    (void)outputPath;
    (void)gamutIn;
    (void)gamutOut;
    setBridgeUnavailableMessage(errorMessage, errorMessageSize);
    return false;
#endif
}

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
) {
#if defined(ATC_BRIDGE_ENABLED)
    if (rgba8Data == NULL || width == 0 || height == 0 || bytesPerRow == 0 || outData == NULL || outDataSize == NULL) {
        copyMessage(errorMessage, errorMessageSize, "RGBA input and output buffer pointers are required.");
        return false;
    }

    *outData = NULL;
    *outDataSize = 0;
    if (outWidth != NULL) { *outWidth = 0; }
    if (outHeight != NULL) { *outHeight = 0; }
    if (outMipLevels != NULL) { *outMipLevels = 0; }

    const ATC_Texture *sourceTex = NULL;
    const ATC_Texture *destTex = NULL;
    ATC_Surface *sourceSurface = NULL;

    if (ATC_CreateTexture2D(
            NULL,
            width,
            height,
            1,
            atcFormatRgba8Unorm,
            mapGamut(gamutIn),
            false,
            &sourceTex
        ) != atcErrorNone) {
        copyMessage(errorMessage, errorMessageSize, "Failed to allocate source texture.");
        return false;
    }

    if (ATC_GetSurface(NULL, sourceTex, 0, 0, &sourceSurface) != atcErrorNone || sourceSurface == NULL) {
        copyMessage(errorMessage, errorMessageSize, "Failed to access source texture surface.");
        ATC_DeleteTexture(NULL, sourceTex, false);
        return false;
    }

    const size_t sourceSize = (size_t)bytesPerRow * (size_t)height;
    sourceSurface->rowBytes = bytesPerRow;
    sourceSurface->size = (uint32_t)sourceSize;
    sourceSurface->data = malloc(sourceSize);
    if (sourceSurface->data == NULL) {
        copyMessage(errorMessage, errorMessageSize, "Failed to allocate source surface memory.");
        ATC_DeleteTexture(NULL, sourceTex, false);
        return false;
    }
    memcpy(sourceSurface->data, rgba8Data, sourceSize);

    ATC_Options options;
    if (!ATC_InitialiseDefaultOptions(&options)) {
        copyMessage(errorMessage, errorMessageSize, "Failed to initialize AppleTextureConverter options.");
        free(sourceSurface->data);
        sourceSurface->data = NULL;
        ATC_DeleteTexture(NULL, sourceTex, false);
        return false;
    }

    options.format = mapCompressionFormat(compressionFormat, astcBlockSize);
    options.quality = mapQuality(qualityLevel);
    options.maxExtent = maxExtent;
    options.maxMipmaps = generateMipmaps ? atcMaxMipMaps : 1;
    options.colorGamutIn = mapGamut(gamutIn);
    options.colorGamutOut = mapGamut(gamutOut);

    const ATC_Error result = ATC_CompressMemory(NULL, sourceTex, &destTex, &options);
    free(sourceSurface->data);
    sourceSurface->data = NULL;
    ATC_DeleteTexture(NULL, sourceTex, false);
    if (result != atcErrorNone) {
        char buffer[256];
        snprintf(buffer, sizeof(buffer), "AppleTextureConverter memory compression failed (%s).", errorName(result));
        copyMessage(errorMessage, errorMessageSize, buffer);
        return false;
    }

    ATC_Surface *destSurface = NULL;
    if (ATC_GetSurface(NULL, destTex, 0, 0, &destSurface) != atcErrorNone || destSurface == NULL || destSurface->data == NULL || destSurface->size == 0) {
        copyMessage(errorMessage, errorMessageSize, "Compressed texture has no readable surface payload.");
        ATC_DeleteTexture(NULL, destTex, true);
        return false;
    }

    uint8_t *payload = (uint8_t *)malloc(destSurface->size);
    if (payload == NULL) {
        copyMessage(errorMessage, errorMessageSize, "Failed to allocate output payload memory.");
        ATC_DeleteTexture(NULL, destTex, true);
        return false;
    }
    memcpy(payload, destSurface->data, destSurface->size);

    *outData = payload;
    *outDataSize = (size_t)destSurface->size;
    if (outWidth != NULL) { *outWidth = destTex->width; }
    if (outHeight != NULL) { *outHeight = destTex->height; }
    if (outMipLevels != NULL) { *outMipLevels = destTex->numMipLevels; }

    ATC_DeleteTexture(NULL, destTex, true);
    copyMessage(errorMessage, errorMessageSize, "");
    return true;
#else
    (void)rgba8Data;
    (void)width;
    (void)height;
    (void)bytesPerRow;
    (void)compressionFormat;
    (void)astcBlockSize;
    (void)qualityLevel;
    (void)maxExtent;
    (void)generateMipmaps;
    (void)gamutIn;
    (void)gamutOut;
    if (outData != NULL) { *outData = NULL; }
    if (outDataSize != NULL) { *outDataSize = 0; }
    if (outWidth != NULL) { *outWidth = 0; }
    if (outHeight != NULL) { *outHeight = 0; }
    if (outMipLevels != NULL) { *outMipLevels = 0; }
    setBridgeUnavailableMessage(errorMessage, errorMessageSize);
    return false;
#endif
}

void ATCBridge_FreeBuffer(uint8_t *buffer) {
    free(buffer);
}
