#pragma once

#include "pxr/usd/sdf/layerUtils.h"
#include "pxr/usd/sdf/reference.h"

#include <string>

inline std::string SwiftUsdShellSdfReferenceAssetPath(const pxr::SdfReference& reference) {
    return reference.GetAssetPath();
}

inline std::string SwiftUsdShellSdfReferencePrimPath(const pxr::SdfReference& reference) {
    return reference.GetPrimPath().GetAsString();
}

inline std::string SwiftUsdShellSdfReferenceResolvedAssetPath(
    const pxr::SdfLayerHandle& anchor,
    const pxr::SdfReference& reference
) {
    const std::string assetPath = reference.GetAssetPath();
    if (assetPath.empty()) {
        return assetPath;
    }
    return pxr::SdfResolveAssetPathRelativeToLayer(anchor, assetPath);
}
