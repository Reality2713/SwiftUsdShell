# SwiftUsdShell

Pure Swift handles and identifiers for APIs backed by SwiftUsd/OpenUSD.

This package intentionally does not import SwiftUsd, OpenUSD, USDInterop, or
any C++ interop target. Runtime packages own the mapping between these stable
Swift values and native USD objects.

## Current Surface

- `USDStageHandle`
- `USDPrimHandle`
- `USDPath`
- `USDAssetPath`
- `USDToken`
- `USDLoadPolicy`
- `SwiftUsdShellError`

The package starts small so downstream packages can prove the invalidation
boundary before adding broader generated OpenUSD facade coverage.
