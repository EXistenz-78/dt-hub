# AGENTS.md

Guidance for AI coding agents working on the DrawThings-Swift repository. To *use* the library in
an app, see the skill in [skills/drawthings-swift](skills/drawthings-swift/SKILL.md) instead.

## What this is

A Swift package (`DrawThingsSwift`) with four library products for talking to a Draw Things gRPC
server from macOS 15+ / iOS 18+ apps, in Swift 6 language mode:

| Target | Path | Notes |
|---|---|---|
| `DrawThingsClient` | `Sources/DrawThingsClient` | Transport (grpc-swift 2), configuration and Draw Things JSON, tensors, media, `DrawThingsSession`. Everything else depends on it. |
| `DrawThingsQueue` | `Sources/DrawThingsQueue` | `GenerationQueue`, `QueueStorage` |
| `DrawThingsVideoKit` | `Sources/DrawThingsVideoKit` | `VideoProcessor`, `VideoAssembler`, interpolation, super resolution |
| `DrawThingsKit` | `Sources/DrawThingsKit` | `ConnectionManager`, `ModelsManager`, `ConfigurationManager`, bundled Draw Things+ catalogs |
| `CFpzip` | `Sources/CFpzip` | Vendored fpzip (C++11) for tensor decompression |

`Examples/DrawThingsExample` is a separate package (a SwiftUI app) that depends on this one by path.

## Build and test

```bash
swift build
swift test                                   # all suites; ~0.5 s, no server needed
swift test --filter QueueTests               # one suite (filter matches type or test names)
swift build --package-path Examples/DrawThingsExample
xcodebuild build -scheme DrawThingsSwift-Package -destination 'generic/platform=iOS Simulator'
```

- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- `Tests/DrawThingsClientTests/Support/FakeDrawThingsServer.swift` is an in-process gRPC server
  standing in for Draw Things. Script responses in its `generate` closure; inspect
  `server.record` for what the client sent. Prefer it over mocks for anything that touches the
  transport, queue or session.
- Tests that encode video carry the `.writesVideo` trait, which skips them on GitHub Actions
  (`AVAssetWriter` crashes intermittently on the hosted macOS VMs). Run them locally.
- Tests that touch profile storage pass an in-memory `SecretStore` (`MemorySecrets`) so they don't
  write to the developer's Keychain.
- Before finishing: zero warnings in `swift build --build-tests`, all tests passing, the iOS
  Simulator build succeeding, and `xcodebuild docbuild -scheme DrawThingsSwift-Package` without
  warnings from this package.

## Conventions

- Swift 6 strict concurrency. Values that cross actors are `Sendable` structs and enums. The service
  is an actor; UI-facing state types (`DrawThingsSession`, `GenerationQueue`, `VideoProcessor`, Kit's
  managers) are `@MainActor @Observable`. No Combine and no SwiftUI in library targets; the library
  ships no views.
- Match the surrounding code: its comment density, naming, doc-comment style (`///` on public API,
  documenting every parameter, so DocC builds cleanly) and file header.
- `Broadcast<Element>` (`Sources/DrawThingsClient/Support`, `package` access) backs every `events`
  and `results` `AsyncStream`. Reuse it rather than writing new subscriber registries.
- Errors: throw `DrawThingsError` (or a target's own error enum) instead of trapping on bad input.
  Tensor and network data is untrusted: check sizes and bounds.
- Behavior should match the Draw Things app. When unsure how the server or app does something
  (frame rates, JSON keys, chunking, mask format), check the upstream source
  ([draw-things-community](https://github.com/drawthingsai/draw-things-community)) rather than
  guessing, and cite the upstream function in a comment.
- Public API changes need entries in `CHANGELOG.md` (an `## Unreleased` section until release), and
  breaking ones in `MIGRATING-2.0.md` or its successor. Code samples in `README.md`, the DocC
  catalogs and `skills/drawthings-swift` must compile; keep them in sync with the API.

## Generated and vendored code

- `Sources/DrawThingsClient/Generated/` is generated. Don't edit it by hand. Regenerate with
  `Scripts/generate.sh <path-to-draw-things-community>` (needs `protoc` and `flatc` 25.9.23); it also
  regenerates the test server stubs in `Tests/DrawThingsClientTests/Generated/`.
- `Sources/DrawThingsClient/Resources/models.json` is the bundled model-spec snapshot, refreshed
  by `Scripts/update-model-specs.sh` (and weekly by CI). Don't edit entries by hand.
- `Sources/CFpzip` is vendored fpzip. Local changes are marked `DrawThingsClient` in comments; keep
  them minimal and marked.

## Testing against a real server

Only when a real server is available and the user agrees:
- The Draw Things app's API server (default port 7859, TLS on) or `gRPCServerCLI`.
- Use settings that suit the model. `DrawThingsConfiguration()`'s defaults are Draw Things' preset
  for Z Image Turbo (`z_image_turbo_1.0_q8p.ckpt`, 8 steps, UniPC Trailing, guidance 1, shift 3, no
  resolution-dependent shift); use them as is, or for other models a configuration copied from
  Draw Things (upstream presets: `MediaGenerationKit/Resources/configs.json`). Unsuitable settings
  make the server return no image, and some servers crash on the next request.
- Bridge Mode to Draw Things+ passes generation to the cloud: fine for a few requests, but don't
  send large batches.

## Commits and releases

- Work on a branch and open a PR to `main`; CI (macOS build and test, iOS Simulator build, example
  app) must pass.
- Releases: date the CHANGELOG section, merge the PR with a merge commit, tag `vX.Y.Z` on `main`,
  and publish a GitHub release with the changelog section as notes. Semantic versioning: new public
  API is a minor release.
