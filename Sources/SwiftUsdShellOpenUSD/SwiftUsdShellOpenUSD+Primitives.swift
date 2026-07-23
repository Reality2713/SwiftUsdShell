import CxxStdlib
import Foundation
internal import OpenUSD
import SwiftUsdShell

// MARK: - Package-relative path helpers
//
// Thin Swift wrappers over OpenUSD's `Ar` package-relative path utilities.
// Package-relative paths address assets contained inside package assets
// (e.g. `Model.usdz[geom/mesh.usd]`); see `pxr/usd/ar/packageUtils.h` for
// the canonical syntax. These primitives are pure string transforms and do
// not consult the asset resolver.

/// Package-relative path utilities backed by `pxr::ArPackageRelativePath` APIs.
public enum USDPackageRelativePath {

    /// Returns `true` when `path` parses as a package-relative path
    /// (`outer[inner]`) per `ArIsPackageRelativePath`.
    public static func isPackageRelative(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        return pxr.ArIsPackageRelativePath(std.string(path))
    }

    /// Splits the outermost package-relative path into `(package, packaged)`.
    /// Returns `nil` when `path` is not package-relative.
    ///
    /// For `a.pack[b.pack[c.pack]]` this returns `("a.pack", "b.pack[c.pack]")`.
    public static func splitOuter(_ path: String) -> (packagePath: String, packagedPath: String)? {
        guard isPackageRelative(path) else { return nil }
        let pair = pxr.ArSplitPackageRelativePathOuter(std.string(path))
        return (String(pair.first), String(pair.second))
    }

    /// Splits the innermost package-relative path into `(package, packaged)`.
    /// Returns `nil` when `path` is not package-relative.
    ///
    /// For `a.pack[b.pack[c.pack]]` this returns `("a.pack[b.pack]", "c.pack")`.
    public static func splitInner(_ path: String) -> (packagePath: String, packagedPath: String)? {
        guard isPackageRelative(path) else { return nil }
        let pair = pxr.ArSplitPackageRelativePathInner(std.string(path))
        return (String(pair.first), String(pair.second))
    }

    /// Joins `packagePath` and `packagedPath` using canonical `Ar` rules,
    /// nesting brackets as necessary. Returns `nil` when either side is empty.
    public static func join(packagePath: String, packagedPath: String) -> String? {
        guard !packagePath.isEmpty, !packagedPath.isEmpty else { return nil }
        let joined = pxr.ArJoinPackageRelativePath(std.string(packagePath), std.string(packagedPath))
        let result = String(joined)
        return result.isEmpty ? nil : result
    }

    /// Walks `splitInner` repeatedly to return the deepest packaged path.
    ///
    /// Mirrors the helper in USDInterop: strips surrounding `@…@` and `[ ]`
    /// decoration so callers receive a bare packaged path. Useful when a
    /// validation result needs the leaf asset reference for filename checks.
    public static func innermostPackagedPath(_ path: String) -> String {
        var current = path
            .replacingOccurrences(of: "@", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while let split = splitInner(current) {
            current = split.packagedPath
        }

        return current.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }
}

// MARK: - Typed attribute setter overloads
//
// Convenience overloads of a single `setAttribute` name so call sites read
// uniformly regardless of the value type. These thread directly into
// `UsdAttribute.Set` via `VtValue` construction — no extra schema validation,
// no time-sample fan-out — matching the low-level `USDInteropAttributeWriter`
// helpers in USDInterop. Callers are responsible for ensuring `attr` is
// valid and that `value` is type-compatible with the attribute's declared
// `SdfValueTypeName`.

extension OpenUSDStageRuntime {

    /// Authors `value` on `attr` at `timeCode`. Returns `attr.Set(...)`.
    @discardableResult
    func setAttribute(
        _ attr: UsdAttribute,
        value: Bool,
        timeCode: UsdTimeCode = UsdTimeCode.Default()
    ) -> Bool {
        attr.Set(VtValue(value), timeCode)
    }

    /// Authors `value` on `attr` at `timeCode`.
    @discardableResult
    func setAttribute(
        _ attr: UsdAttribute,
        value: Float,
        timeCode: UsdTimeCode = UsdTimeCode.Default()
    ) -> Bool {
        attr.Set(VtValue(value), timeCode)
    }

    /// Authors `value` on `attr` at `timeCode`. Stored as `int32` in OpenUSD.
    @discardableResult
    func setAttribute(
        _ attr: UsdAttribute,
        value: Int32,
        timeCode: UsdTimeCode = UsdTimeCode.Default()
    ) -> Bool {
        attr.Set(VtValue(value), timeCode)
    }

    /// Authors a linear-space `Color3f` on `attr`. Components are taken as-is;
    /// no colorspace conversion is performed.
    @discardableResult
    func setAttribute(
        _ attr: UsdAttribute,
        color red: Float,
        green: Float,
        blue: Float,
        timeCode: UsdTimeCode = UsdTimeCode.Default()
    ) -> Bool {
        attr.Set(VtValue(GfVec3f(red, green, blue)), timeCode)
    }

    /// Authors a UTF-8 `string` value on `attr`.
    @discardableResult
    func setAttribute(
        _ attr: UsdAttribute,
        value: String,
        timeCode: UsdTimeCode = UsdTimeCode.Default()
    ) -> Bool {
        attr.Set(VtValue(std.string(value)), timeCode)
    }

    /// Authors a `TfToken` value on `attr` from `value` (already-encoded UTF-8).
    @discardableResult
    func setAttribute(
        _ attr: UsdAttribute,
        token value: String,
        timeCode: UsdTimeCode = UsdTimeCode.Default()
    ) -> Bool {
        attr.Set(VtValue(TfToken(std.string(value))), timeCode)
    }
}

// MARK: - UsdShade output + connection wrappers
//
// Direct conveniences around `UsdShadeShader.CreateOutput` and
// `UsdShadeInput.ConnectToSource(UsdShadeOutput)`. SwiftUsdShell already
// uses `shader.CreateInput(...)` directly; these match that pattern for the
// symmetric output authoring path used when wiring shader networks.

extension OpenUSDStageRuntime {

    /// Defines (or returns existing) `outputs:<name>` of declared `typeName`
    /// on `shader`. Wraps `UsdShadeShader.CreateOutput`.
    func createShaderOutput(
        _ shader: UsdShadeShader,
        name: String,
        typeName: SdfValueTypeName
    ) -> pxr.UsdShadeOutput {
        var shader = shader
        return shader.CreateOutput(TfToken(std.string(name)), typeName)
    }

    /// Connects `input` to `output` via `UsdShadeInput.ConnectToSource`.
    /// Returns the underlying success flag — `false` typically means the
    /// connection target is invalid or types are incompatible.
    @discardableResult
    func connectShaderInput(
        _ input: UsdShadeInput,
        toOutput output: pxr.UsdShadeOutput
    ) -> Bool {
        var input = input
        return input.ConnectToSource(output)
    }
}
