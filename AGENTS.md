# SwiftUsdShell agent rules

SwiftUsdShell is the sole typed, product-neutral mechanical boundary around raw
OpenUSD for the shared private engines.

- Put generic pxr mechanics in `SwiftUsdShellOpenUSD` and return only pure-Swift
  DTOs from its public API.
- OpenUSD imports in that target must be `private import`; they must not appear
  in the emitted public interface.
- Keep product policy in Drydock/Preflight engine repositories, not here.
- Engine consumers must compile without C++ interoperability.
- Publish Shell API changes from this repository. The existing
  `Reality2713/SwiftUsd-binaries` workflow locks the source revision and
  publishes compiler-coupled artifacts to SwiftUsdShell-binaries.
- A toolchain-only binary rebuild does not require a new Shell source tag.
- Historical coordinated-train documentation and tags are incident history,
  not a current procedure.
- Never build SwiftUsd locally for a release. The remote M5 is the sole builder.
