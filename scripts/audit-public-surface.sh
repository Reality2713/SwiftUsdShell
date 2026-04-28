#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

failures=0

check_no_matches() {
    local description="$1"
    shift

    if "$@"; then
        echo "error: $description"
        failures=$((failures + 1))
    fi
}

check_no_matches \
    "base SwiftUsdShell target must not import runtime or interop modules" \
    rg -n '^\s*import\s+(OpenUSD|CxxStdlib|SwiftUsd)\b' Sources/SwiftUsdShell Tests

check_no_matches \
    "base SwiftUsdShell target must not expose native OpenUSD type names" \
    rg -n '\b(Usd[A-Z][A-Za-z0-9_]*|Sdf[A-Z][A-Za-z0-9_]*|Tf[A-Z][A-Za-z0-9_]*|Vt[A-Z][A-Za-z0-9_]*|Gf[A-Z][A-Za-z0-9_]*|pxrInternal_[A-Za-z0-9_]+)\b' Sources/SwiftUsdShell Tests

check_no_matches \
    "public docs/source must not mention internal product or project names" \
    rg -n '(Preflight|Gantry|Deconstructed|USDTools|CoreAsset|Reality Composer|RCP|/Volumes|elkraneo)' README.md Docs Sources Tests Package.swift

check_no_matches \
    "shell material surface families must not expose renderer/workflow graph concepts" \
    rg -n 'realityKitGraph|RealityKitGraph|shaderGraph|workflowMaterial|materialEditPlanning' Sources/SwiftUsdShell Tests README.md Docs

if [[ "$failures" -gt 0 ]]; then
    echo "audit-public-surface failed with $failures issue(s)"
    exit 1
fi

echo "audit-public-surface passed"
