# SwiftUsdShell

SwiftUsdShell is the pure Swift API boundary for USD-capable applications.
It defines stable value types, handles, requests, and results that can be used
without importing SwiftUsd, OpenUSD, USDInterop, or any Swift/C++ interop target.

SwiftUsd remains the runtime binding layer over OpenUSD. Packages such as
USDTools own product workflows and runtime implementations behind this shell.

## Boundary Rules

- SwiftUsdShell must not import SwiftUsd, OpenUSD, USDInterop, USDInteropCxx, or
  C++ interop targets.
- Public APIs must not expose `Usd*`, `Sdf*`, `Tf*`, `Vt*`, `Gf*`, `OpenUSD.*`,
  or `pxrInternal_*` types.
- Product workflow policy belongs above the shell, for example in USDTools.
- Generic runtime primitives should move toward SwiftUsd when practical.
- This package should stay small, value-oriented, Codable, Hashable, and
  Sendable wherever possible.

## Current Surface

- Core identity: `USDStageURL`, `USDStageHandle`, `USDPrimHandle`, `USDPath`,
  `USDAssetPath`, `USDToken`, `USDLoadPolicy`.
- Values and summaries: `USDValue`, vector/matrix values, `USDTimeCode`,
  `USDAttributeSummary`, `USDRelationshipSummary`, `USDPrimSummary`,
  `USDPrimTree`, `USDStageMetadata`.
- Materials: material summaries, property summaries, binding information,
  generic semantic edit requests, and edit results.
- Transforms: common transform data, authored xform-op summaries, and transform
  edit capability/restriction DTOs.
- Statistics and model info: scene bounds, geometry statistics, animation
  status, blend shapes, and model metadata.

## What Is Not In The Shell

SwiftUsdShell intentionally does not contain:

- RealityKit, Preflight, Gantry, or other product-specific concepts.
- Material edit planning policy, readiness, branch plans, or execution strategy.
- Runtime stage caches, OpenUSD plugin registration, file format loading, or
  C++ bridge APIs.

Those concepts belong in runtime or product packages that depend on this shell.

## Release Checklist

Before tagging a public release:

1. Run `swift test` in this package.
2. Confirm no forbidden imports or product names are present:
   `OpenUSD`, `USDInterop`, `USDInteropCxx`, `Cxx`, `RealityKit`, `Preflight`,
   `Gantry`, or `realityKitGraph`.
3. Confirm new public DTOs are Codable, Hashable, and Sendable unless there is a
   documented reason they cannot be.
4. Confirm product/workflow logic stayed in USDTools or another higher-level
   package.
