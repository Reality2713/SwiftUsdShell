# SwiftUsdShell

SwiftUsdShell is the pure Swift API boundary for USD-capable applications.
It defines stable value types, handles, requests, and results for USD-related
inspection and editing APIs.

This package is not a USD runtime. Importing SwiftUsdShell alone does not open,
inspect, validate, render, or edit USD files. A separate runtime package or
application service must implement these contracts and map them to a USD engine.

The optional `SwiftUsdShellOpenUSD` product is the mechanical OpenUSD-backed
adapter. Applications that only need contracts can depend on `SwiftUsdShell`;
applications that need execution can also depend on `SwiftUsdShellOpenUSD`.

For the full layering model, see
[Docs/Architecture.md](Docs/Architecture.md). For current adapter coverage,
see [Docs/AdapterCoverage.md](Docs/AdapterCoverage.md). For consumer setup,
see [Docs/ConsumerGuide.md](Docs/ConsumerGuide.md).

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
- Values and summaries: `USDValue`, vector/matrix/quaternion values,
  `USDTimeCode`, `USDAttributeSummary`, `USDRelationshipSummary`,
  `USDDiagnostic`, `USDPrimSummary`, `USDPrimTree`, `USDStageMetadata`.
- Materials: material summaries, property summaries, binding information,
  generic semantic edit requests, and edit results.
- Transforms: common transform data, authored xform-op summaries, and transform
  edit capability/restriction DTOs.
- Statistics and model info: scene bounds, geometry statistics, animation
  status, blend shapes, and model metadata.
- Runtime contracts: stage/prim inspection requests and results, composition
  arc summaries for references and payloads, variant set summaries, generic edit
  requests, refresh hints, and runtime errors.

## What Is Not In The Shell

SwiftUsdShell intentionally does not contain:

- Renderer, application, or product-specific concepts.
- Material edit planning policy, readiness, branch plans, or execution strategy.
- Runtime stage caches, plugin registration, file format loading, or bridge
  APIs.

Those concepts belong in runtime, renderer, application, or domain packages that
depend on this shell.

## Runtime Adapter Direction

SwiftUsdShell should be paired with a separate generic runtime adapter, such as
`SwiftUsdShellOpenUSD`, when an application needs to execute USD work. That
adapter may import SwiftUsd/OpenUSD and implement shell protocols, but it must
stay mechanical: open stages, inspect prims, perform generic edits, and map
results back into shell DTOs.

Application/domain layers remain above both packages. They own editor
identity, import/export policy, selection mapping, component authoring,
validation, repair, conversion, and workflow decisions.

## Release Checklist

Before tagging a public release:

1. Run `scripts/audit-public-surface.sh`.
2. Run `swift test` in this package.
3. Confirm no runtime imports, bridge imports, C++ interop settings, or
   product-specific names are present in source or tests.
4. Confirm new public DTOs are Codable, Hashable, and Sendable unless there is a
   documented reason they cannot be.
5. Confirm product and workflow logic stayed in a higher-level package.
