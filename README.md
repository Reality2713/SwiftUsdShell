# SwiftUsdShell

SwiftUsdShell is the pure-Swift API boundary for USD-capable applications on
Apple platforms. It defines the value types, handles, requests, and results
that describe USD inspection and editing, without exposing OpenUSD's C++ types
to the code that consumes it.

It is a contract, not a runtime. Importing `SwiftUsdShell` alone does not open,
inspect, render, validate, or edit a USD file.

The USD work itself is done by [SwiftUsd](https://github.com/apple/SwiftUsd),
Apple's OpenUSD Swift bindings, on top of
[OpenUSD](https://openusd.org), Pixar's Universal Scene Description.
SwiftUsdShell adds no USD capability of its own — it is a boundary over that
work. See [Acknowledgments](#acknowledgments).

## Problem

OpenUSD's Swift bindings use C++ interoperability. Native USD types (`Usd*`,
`Sdf*`, `Tf*`, `Vt*`, `Gf*`, `pxrInternal_*`) cross the language boundary and
appear in Swift module interfaces. This has three consequences:

1. The C++ types leak into every module that links the USD runtime directly.
2. When more than one module in a build links the runtime, Release builds fail
   with module-deserialization and linker errors that do not occur in Debug.
3. Building the runtime from source compiles OpenUSD itself, which is large and
   slow.

An application that needs to read or write USD should not inherit these
properties across its whole module graph.

## Solution

SwiftUsdShell confines the boundary to one place:

- Consumers depend on `SwiftUsdShell`: pure Swift, value-oriented, `Codable`,
  `Hashable`, and `Sendable`. No C++ types cross it.
- Execution lives behind one optional adapter, `SwiftUsdShellOpenUSD`, which is
  the only target that imports OpenUSD and enables C++ interop.
- Both products are distributed as prebuilt binaries via
  [`SwiftUsdShell-binaries`](https://github.com/Reality2713/SwiftUsdShell-binaries).
  A consumer adds one dependency and does not compile OpenUSD.

The C++ leak is contained in a single leaf target. Everything above it stays
pure Swift.

## Two products

| Product | Imports OpenUSD / C++ | Depend on it when |
|---|---|---|
| `SwiftUsdShell` | No | You need the contracts: DTOs, requests, results. UI, models, and feature logic depend only on this. |
| `SwiftUsdShellOpenUSD` | Yes (the Cxx leaf) | You need execution: open a stage, inspect prims, run generic edits. |

Decision rule: depend on `SwiftUsdShell` by default. Add `SwiftUsdShellOpenUSD`
only in the single target that executes USD work.

## Install

Consumers use the binary distribution. Add one dependency:

```swift
// Package.swift
dependencies: [
    .package(
        url: "https://github.com/Reality2713/SwiftUsdShell-binaries.git",
        exact: "0.3.125-macos-arm64.2"
    ),
],
targets: [
    // Contracts only — pure Swift, no C++.
    .target(
        name: "YourContracts",
        dependencies: [
            .product(name: "SwiftUsdShell", package: "SwiftUsdShell-binaries"),
        ]
    ),
    // Execution — the one target that runs USD work.
    .target(
        name: "YourRuntime",
        dependencies: [
            .product(name: "SwiftUsdShellOpenUSD", package: "SwiftUsdShell-binaries"),
        ],
        swiftSettings: [.interoperabilityMode(.Cxx)]
    ),
]
```

Notes:

- The binary `OpenUSD` product (`SwiftUsd-binaries`) is resolved transitively.
  Do not declare it.
- `.interoperabilityMode(.Cxx)` is required only on targets that depend on
  `SwiftUsdShellOpenUSD`.
- The currently published slice is macOS arm64 only. The source package declares
  iOS 26 / macOS 15 / visionOS 26; further binary slices follow the same scheme.

## Usage

```swift
import SwiftUsdShellOpenUSD

let runtime = OpenUSDStageRuntime()

let summary = try runtime.primSummary(
    stage: USDStageURL(url),
    primPath: USDPath("/Root/Sphere")
)
// `summary` is a pure-Swift USDPrimSummary.
// No OpenUSD type crosses this call.
```

One import is enough. `SwiftUsdShellOpenUSD` re-exports `SwiftUsdShell`, so the
runtime and the contract types it returns (`USDStageURL`, `USDPath`,
`USDPrimSummary`, …) arrive together. You never import the wrapped module to name
a return type. (On binary slices built before this re-export, import both
`SwiftUsdShell` and `SwiftUsdShellOpenUSD`.)

A target that needs only the contracts — no execution — imports `SwiftUsdShell`
alone.

## What it is not

SwiftUsdShell does not contain, and must not grow:

- A renderer, an application, or product-specific concepts.
- Material edit planning, readiness, branch plans, or execution strategy.
- Stage caches, plugin registration, file-format loading, or bridge APIs.
- File loading, rendering, validation, repair, conversion, or packaging
  workflows.

These belong in the runtime adapter, or in the application and domain packages
above it. Workflow and heuristics belong above the shell, not in it.

## Boundary rules

- `SwiftUsdShell` must not import a USD runtime, a C++ interop target, or a
  private bridge module.
- Public APIs must not expose native USD runtime types (`Usd*`, `Sdf*`, `Tf*`,
  `Vt*`, `Gf*`, `OpenUSD.*`, `pxrInternal_*`).
- `SwiftUsdShellOpenUSD` stays mechanical: open stages, inspect prims, perform
  generic edits, and map results back into shell DTOs. It carries no product
  policy.
- The package stays small, value-oriented, and `Sendable` wherever possible.

`scripts/audit-public-surface.sh` enforces the type-leak rule.

## Surface

- Identity: `USDStageURL`, `USDStageHandle`, `USDPrimHandle`, `USDPath`,
  `USDAssetPath`, `USDToken`, `USDLoadPolicy`.
- Values and summaries: `USDValue`, vector/matrix/quaternion values,
  `USDTimeCode`, `USDAttributeSummary`, `USDRelationshipSummary`,
  `USDDiagnostic`, `USDPrimSummary`, `USDPrimTree`, `USDStageMetadata`.
- Materials: material and property summaries, binding info, generic semantic
  edit requests, and edit results.
- Transforms: common transform data, authored xform-op summaries, transform
  edit capability and restriction DTOs.
- Statistics and model info: scene bounds, geometry statistics, animation
  status, blend shapes, model metadata.
- Runtime contracts: stage and prim inspection requests and results,
  composition-arc summaries (references and payloads), variant-set summaries,
  generic edit requests, refresh hints, and runtime errors.

## Layering

```
Application / domain      editor identity, import/export, selection,
                          component authoring, validation, repair, workflows
        depends on
SwiftUsdShell (contracts) pure-Swift DTOs, requests, results        <- this repo
        implemented by
SwiftUsdShellOpenUSD       mechanical adapter, imports OpenUSD (Cxx leaf)
        depends on
SwiftUsd / OpenUSD         the USD runtime
```

The application owns all policy. The shell owns the contract. The adapter owns
the mapping. The runtime owns execution.

## Documentation

- [Docs/Architecture.md](Docs/Architecture.md) — the full layering model.
- [Docs/AdapterCoverage.md](Docs/AdapterCoverage.md) — current adapter coverage.
- [Docs/ConsumerGuide.md](Docs/ConsumerGuide.md) — consumer setup.
- [Docs/ReleaseChecklist.md](Docs/ReleaseChecklist.md) — release steps.

## Acknowledgments

SwiftUsdShell is a boundary layer. The capability it exposes belongs to the
projects underneath it:

- [OpenUSD](https://openusd.org) — Pixar's Universal Scene Description, the scene
  format and runtime this entire stack serves.
  ([PixarAnimationStudios/OpenUSD](https://github.com/PixarAnimationStudios/OpenUSD))
- [SwiftUsd](https://github.com/apple/SwiftUsd) — Apple's Swift package for
  OpenUSD via Swift/C++ interoperability, licensed under Apache 2.0. It is what
  `SwiftUsdShellOpenUSD` calls into.

Without these, there is nothing to wrap.

## Development

This repository is the source package. It depends on `SwiftUsd` from source and
compiles OpenUSD; use it to develop the shell itself. Applications should not
depend on this source package — they depend on `SwiftUsdShell-binaries`.

Before tagging a release:

1. Run `scripts/audit-public-surface.sh`.
2. Run `swift test`.
3. Follow [Docs/ReleaseChecklist.md](Docs/ReleaseChecklist.md).
