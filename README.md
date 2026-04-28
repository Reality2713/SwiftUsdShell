# SwiftUsdShell

SwiftUsdShell is the pure Swift API boundary for USD-capable applications.
It defines stable value types, handles, requests, and results for USD-related
inspection and editing APIs.

This package is not a USD runtime. Importing SwiftUsdShell alone does not open,
inspect, validate, render, or edit USD files. A separate runtime package or
application service must implement these contracts and map them to a USD engine.

## Boundary Rules

- SwiftUsdShell must not import a USD runtime, C++ interop target, or private
  bridge module.
- Public APIs must not expose native USD runtime types such as `Usd*`, `Sdf*`,
  `Tf*`, `Vt*`, `Gf*`, `OpenUSD.*`, or `pxrInternal_*`.
- Product workflow policy belongs above the shell in consumer or domain
  packages.
- Runtime primitives belong in runtime implementation packages, not in this
  contract package.
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

- Renderer, application, or product-specific concepts.
- Material edit planning policy, readiness, branch plans, or execution strategy.
- Runtime stage caches, plugin registration, file format loading, or bridge
  APIs.

Those concepts belong in runtime, renderer, application, or domain packages that
depend on this shell.

## Release Checklist

Before tagging a public release:

1. Run `swift test` in this package.
2. Confirm no runtime imports, bridge imports, C++ interop settings, or
   product-specific names are present in source or tests.
3. Confirm new public DTOs are Codable, Hashable, and Sendable unless there is a
   documented reason they cannot be.
4. Confirm product and workflow logic stayed in a higher-level package.
