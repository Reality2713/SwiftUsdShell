# Release Checklist

Use this checklist before tagging a public SwiftUsdShell release.

## Boundary Audit

Run:

```sh
scripts/audit-public-surface.sh
```

This checks that:

- `SwiftUsdShell` stays free of runtime and C++ interop imports
- tests exercise the base shell without importing the OpenUSD adapter
- package-local path dependencies are not committed
- the OpenUSD product dependency and C++ interop setting remain isolated to the
  adapter target
- public docs and source do not mention internal project or product names
- removed renderer/workflow graph concepts do not re-enter the shell

## Base Contract Tests

Run:

```sh
swift build --target SwiftUsdShell
swift test --filter SwiftUsdShellTests
```

These should not require building the OpenUSD adapter. If SwiftPM starts
building the OpenUSD module for this step, stop and inspect the package graph:
the base test target should depend only on `SwiftUsdShell`.

## Adapter Validation

Run the adapter build separately:

```sh
swift build --target SwiftUsdShellOpenUSD
```

This can be expensive because it builds the SwiftUsd/OpenUSD module. Treat
adapter compile failures as implementation issues in `SwiftUsdShellOpenUSD`,
not as reasons to move runtime details into `SwiftUsdShell`.

## Public Surface Review

Before tagging:

- confirm `README.md`, `Docs/Architecture.md`, `Docs/AdapterCoverage.md`, and
  `Docs/ConsumerGuide.md` match the actual package surface
- confirm pending adapter gaps are listed in `Docs/AdapterCoverage.md`
- confirm new DTOs are `Codable`, `Hashable`, and `Sendable` unless explicitly
  documented otherwise
- confirm new APIs are product-neutral USD contracts, not editor workflow policy

## Versioning

Patch releases are appropriate for:

- documentation changes
- non-breaking adapter implementation fixes
- additive convenience initializers that preserve ABI/source compatibility

Minor releases are appropriate for:

- new public DTOs
- new runtime protocol requirements
- new generic edit request cases
- new adapter coverage that exposes additional shell contract fields

Avoid breaking public DTO shapes without a deliberate major-version plan.

## Binary distribution authority

Publish this repository only when the Shell API or implementation source
changes. Then lock that exact source tag in
`Reality2713/SwiftUsd-binaries/.github/workflows/binary-release.yml`.

That workflow owns clean-scratch compilation, exact toolchain identity,
Swiftmodule/interface coherence, one Shell-owned OpenUSD implementation,
combined and `-ObjC` host linkage, behavior fixtures, attestations, and the one
runtime/plugin release. A toolchain-only rebuild reuses this source revision
and does not create a new Shell source release.
