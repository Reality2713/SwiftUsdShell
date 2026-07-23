# SwiftUsdShell agent rules

SwiftUsdShell is the sole typed mechanical boundary around raw OpenUSD for the
atomic PXR Engine SDK.

- Put generic pxr mechanics in `SwiftUsdShellOpenUSD` and return only pure-Swift
  DTOs from its public API.
- OpenUSD imports in that target must be `private import`; they must not appear
  in the emitted public interface.
- Keep product policy in Drydock/Preflight engine repositories, not here.
- Engine consumers must compile without C++ interoperability.
- Do not publish this repository or SwiftUsdShell-binaries independently.
  `Reality2713/SwiftUsd-binaries` locks this source revision and publishes the
  one atomic SDK version.
- Historical coordinated-train documentation and tags are incident history,
  not a current procedure.
- Do not trigger expensive SwiftUsd compilation unless explicitly requested.
