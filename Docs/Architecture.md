# SwiftUsdShell Architecture

SwiftUsdShell exists to give Swift USD applications a public, pure-Swift vocabulary without forcing feature modules to import SwiftUsd, OpenUSD, or Swift/C++ interop products.

The architecture has three layers.

## 1. SwiftUsdShell

Purpose: what an app can ask for.

This package owns pure Swift DTOs, protocols, request types, and result types. It must stay independent from every USD runtime implementation.

Allowed here:

- USD identity values such as paths, tokens, asset paths, and stage URLs
- inspection DTOs such as stage metadata, prim summaries, attributes, relationships, composition arcs, variant sets, transforms, bounds, diagnostics, material binding summaries, material topology, and material property summaries
- generic edit requests/results
- runtime-facing protocols whose requirements are expressed only in shell DTOs
- Codable, Hashable, Sendable value types suitable for testing, logging, and process boundaries

Not allowed here:

- SwiftUsd, OpenUSD, or C++ interop imports
- native USD runtime handles such as `UsdStage`, `SdfPath`, `TfToken`, `VtValue`, `GfVec*`, or `pxrInternal_*`
- renderer or application concepts
- product workflow policy
- repair, validation, material planning, conversion, packaging, or application heuristics

## 2. SwiftUsdShellOpenUSD / SwiftUsdScene

Purpose: how shell requests are answered using SwiftUsd/OpenUSD.

This layer is the generic runtime adapter. In this package it is exposed as the
separate `SwiftUsdShellOpenUSD` product. It must not be part of the base
`SwiftUsdShell` product.

Allowed here:

- importing SwiftUsd/OpenUSD
- opening stages and reading generic stage metadata
- traversing prims and mapping them into shell DTOs
- reading attributes, relationships, transforms, references, variants, bounds, statistics, generic material bindings, and generic material properties
- executing generic USD edits and returning shell edit results
- translating runtime diagnostics into typed shell errors

Not allowed here:

- application-specific policy
- editor-specific workflow policy
- product-specific material edit planning
- validation or repair strategy
- UI refresh policy beyond generic edit result hints

This layer should be mechanical: call the runtime, map into shell DTOs, return results.

The adapter should grow in the same groups that broad USD tooling tends to use:

- stage metadata and prim hierarchy
- prim identity, attributes, and relationships
- composition arcs for references and payloads
- variant sets and authored selections
- transforms and bounds
- generic material binding and material property inspection
- structured runtime diagnostics

Import/export policy, texture packaging, renderer publication, validation
strategy, and editor workflow decisions remain application/domain concerns.

## 3. Application / Domain Layers

Purpose: what the USD data means for an editor or product workflow.

These layers live outside SwiftUsdShell. They are owned by each application or
domain package.

Allowed here:

- import/export policy
- editor identity and selection mapping
- entity-to-prim reconciliation
- refresh strategy
- renderer or component authoring
- workflow validation and repair
- material planning and readiness checks
- packaging, conversion, and application-specific behavior

These layers can use SwiftUsdShell DTOs and call a runtime adapter, but their logic should not move down into the shell.

## Dependency Shape

The normal app graph should be:

```text
Feature/UI
  -> application/domain clients
  -> SwiftUsdShell contracts
  -> SwiftUsdShellOpenUSD or app runtime adapter
  -> SwiftUsd/OpenUSD
```

For simple open-source consumers, the product layer can be skipped:

```text
Feature/UI
  -> SwiftUsdShell contracts
  -> SwiftUsdShellOpenUSD
  -> SwiftUsd/OpenUSD
```

The graph should not be:

```text
Feature/UI
  -> SwiftUsd/OpenUSD/C++ interop
```

## Design Test

Before adding an API, answer:

1. Is it only a pure USD value, request, result, or protocol shape?
   Put it in `SwiftUsdShell`.
2. Is it only a mechanical implementation that calls SwiftUsd/OpenUSD and maps into shell DTOs?
   Put it in `SwiftUsdShellOpenUSD`, `SwiftUsdScene`, or an app-local runtime adapter.
3. Does it decide what an editor or product should do with USD data?
   Put it in an application/domain layer outside SwiftUsdShell.

## Action Plan

1. Keep broadening `SwiftUsdShellOpenUSD` only with mechanical USD facts that map directly into existing shell contracts.
2. Use external sample applications as proof: feature/UI targets should import shell contracts, while the runtime adapter is the only target that imports SwiftUsd/OpenUSD.
3. Move warning, repair, validation, packaging, and renderer-parity decisions into consuming application/domain packages.
4. When consumers need new data, first ask whether it is a neutral USD fact or a product workflow rule. Add only the neutral fact to SwiftUsdShell.
