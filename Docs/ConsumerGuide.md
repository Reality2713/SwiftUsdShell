# Consumer Guide

SwiftUsdShell has two public products with different jobs.

Use `SwiftUsdShell` in feature, UI, test, and domain modules that only need USD
contracts:

```swift
import SwiftUsdShell

struct SelectionInspector {
    var runtime: any USDStageRuntime

    func inspectSelection(stageURL: URL, primPath: String) async throws -> USDPrimInspection {
        try await runtime.inspectPrim(
            USDPrimInspectionRequest(
                stageURL: USDStageURL(stageURL),
                primPath: USDPath(primPath),
                options: USDPrimInspectionOptions(
                    includeAttributes: true,
                    includeRelationships: true,
                    includeCompositionArcs: true,
                    includeVariantSets: true,
                    includeTransform: true,
                    includeMaterialBinding: true
                )
            )
        )
    }
}
```

Use `SwiftUsdShellOpenUSD` only at the runtime composition boundary when you
want the default OpenUSD-backed implementation:

```swift
import SwiftUsdShell
import SwiftUsdShellOpenUSD

let runtime: any USDStageRuntime = OpenUSDStageRuntime()
```

A test, preview, or app can provide a fixture runtime without importing OpenUSD:

```swift
import SwiftUsdShell

struct FixtureRuntime: USDStageRuntime {
    func inspectStage(_ request: USDStageInspectionRequest) async throws -> USDStageInspection {
        USDStageInspection(
            stageURL: request.stageURL,
            metadata: USDStageMetadata(defaultPrimName: "Root"),
            primTree: USDPrimTree(path: "/Root", name: "Root", typeName: "Xform")
        )
    }

    func inspectPrim(_ request: USDPrimInspectionRequest) async throws -> USDPrimInspection {
        USDPrimInspection(
            prim: USDPrimSummary(
                path: request.primPath,
                name: USDToken(request.primPath.rawValue.split(separator: "/").last.map(String.init) ?? ""),
                typeName: "Mesh"
            )
        )
    }

    func edit(_ request: USDEditRequest) async throws -> USDEditResult {
        USDEditResult()
    }
}
```

## Dependency Rules

- Feature modules should depend on `SwiftUsdShell`.
- The app or service composition layer may depend on `SwiftUsdShellOpenUSD`.
- Tests for feature modules should use fixture runtimes where possible.
- Product workflow packages may wrap shell DTOs, but should not move workflow
  policy into the shell.
- Do not pass OpenUSD, SwiftUsd, or C++ interop types across a shell-facing API.

## When To Add To The Shell

Add a type to `SwiftUsdShell` when it is a stable, product-neutral USD request,
result, handle, summary, diagnostic, or edit contract.

Do not add a type to `SwiftUsdShell` when it encodes editor policy, validation
strategy, repair workflow, texture packaging, renderer behavior, or import/export
rules.
