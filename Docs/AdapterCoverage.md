# SwiftUsdShellOpenUSD Adapter Coverage

`SwiftUsdShellOpenUSD` is the optional mechanical runtime adapter for the
pure Swift contracts in `SwiftUsdShell`.

The base `SwiftUsdShell` product remains runtime-free. This document describes
only the optional adapter product.

## Implemented

Stage inspection:

- opens a stage with the requested load policy
- reads stage metadata: up-axis, meters-per-unit, default prim, timeline range
- optionally maps the prim hierarchy into `USDPrimTree`
- optionally computes generic geometry statistics: mesh count, material count,
  texture shader count, vertex count, and triangulated face count
- optionally computes world-space scene bounds for the default prim or root
  children
- optionally maps generic material summaries, material topology, and material
  properties for material prims in the stage
- returns OpenUSD diagnostics captured during inspection

Prim inspection:

- resolves a prim by path
- maps prim identity, type name, specifier, active/defined/abstract/instanceable
  state
- optionally maps attributes and relationships
- optionally computes generic geometry statistics for the selected prim subtree
- optionally maps references and payloads into composition arc summaries
- optionally maps variant set names, choices, authored selection state, and
  selected variant
- optionally maps common transform vectors, authored xform-op order, supported
  authored xform-op values, animation status, and generic edit capability
- optionally maps generic material binding information
- optionally computes world-space bounds for the selected prim subtree
- optionally maps a generic material summary, topology, and properties for a
  selected material prim or the selected prim's effective bound material
- returns OpenUSD diagnostics captured during inspection

Generic edits:

- set default prim
- set stage meters-per-unit
- set stage up-axis
- set common prim transform
- save the stage

## Pending

There are no known unpopulated inspection contract fields at this layer.

## Non-Goals

The adapter must not implement:

- application-specific import/export decisions
- validation or repair workflows
- material edit planning, readiness checks, or conversion strategy
- renderer publication, selection mapping, or editor identity
- package, texture, or asset relocation policy

Those concerns belong above `SwiftUsdShell` and `SwiftUsdShellOpenUSD`.
