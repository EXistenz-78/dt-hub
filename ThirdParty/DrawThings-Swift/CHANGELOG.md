# Changelog

All notable changes to DrawThings-Swift (formerly DT-gRPC-Swift-Client) are documented here. The project follows
[Semantic Versioning](https://semver.org).

## 2.2.0 — 2026-09-28

### Added
- `skills/drawthings-swift`, an Agent Skill that teaches coding agents (Claude Code, OpenAI Codex,
  Qwen Code, DeepSeek agents) to use the library in apps; install it with
  `npx skills add euphoriacyberware-ai/DrawThings-Swift --skill drawthings-swift`.
- `AGENTS.md` for agents working on this repository, imported by `CLAUDE.md` and `QWEN.md`.
- DrawThingsKit: `ConfigurationDefaults.model` and `ConfigurationDefaults.resolutionDependentShift`.

### Changed
- `DrawThingsConfiguration()`'s defaults are now Draw Things' own preset for Z Image Turbo, a model
  most servers have: `z_image_turbo_1.0_q8p.ckpt`, 1024×1024, 8 steps, UniPC Trailing, guidance 1,
  shift 3, `resolutionDependentShift` false. The old defaults (`sd_xl_base_1.0.safetensors`, a file
  name Draw Things doesn't use, 512×512, 20 steps, DPM++ 2M Karras, guidance 7, shift 1) made
  servers return no image. Values missing from JSON passed to `fromJSON(_:)` take the new defaults.
  DrawThingsKit's `ConfigurationDefaults` and `ConfigurationManager`'s starting configuration follow.
- Examples and docs use the app's Z Image Turbo preset (UniPC Trailing, no resolution-dependent
  shift, rather than DPM++ 2M Trailing), no longer pair Z Image with an SDXL ControlNet or a refiner
  LoRA, and the MiniMax H3 video example uses the settings Draw Things exports for it.

## 2.1.0 — 2026-09-27

### Changed
- DrawThingsKit: `ProfileStorage` keeps server shared secrets in the Keychain instead of
  `UserDefaults`. Secrets saved by DrawThingsKit 2.2 or DrawThings-Swift 2.0.0 move to the Keychain
  when profiles are first loaded; if the Keychain can't be written, a secret stays where it was.
  Deleting a profile deletes its secret. No code changes are needed.

### Added
- `SecretStore`, `KeychainSecretStore` and `KeychainError`; `ProfileStorage(secrets:)` accepts
  another store.

## 2.0.0 — 2026-09-27

A major rework for Swift 6 that also brings DrawThingsQueue, DrawThingsVideoKit and DrawThingsKit
into this package as optional products. See [MIGRATING-2.0.md](MIGRATING-2.0.md) for the API mapping.

### Requirements
- macOS 15 / iOS 18, Swift 6 language mode, grpc-swift 2.

### Added
- `DrawThingsService.stream(_:)`: an `AsyncThrowingStream` of `GenerationEvent`s (progress, preview,
  remote download, image, audio, completed) in server order, and `generate(_:)` returning a
  `GenerationResult`. Cancelling cancels the generation on the server.
- `GenerationRequest`, `GenerationProgress` and `GenerationResult` value types.
- `DrawThingsSession`, an `@Observable` session for SwiftUI (the library contains no views).
- `DrawThingsQueue` product (formerly the separate DrawThingsQueue package): an `@Observable`
  `GenerationQueue` built on the event stream, with pause, cancel, retry, reordering, `AsyncStream`
  events and results, and saved queues that keep input images and hints and read 0.x files.
- `DrawThingsVideoKit` product (formerly the separate DrawThingsVideoKit package, without its
  SwiftUI views): an `@Observable` `VideoProcessor` fed by any sequence of `GenerationResult`s,
  using `result.media` for video detection and frame rate and `result.audio` for the soundtrack.
  Automatic assemblies are queued, so a result that arrives during an assembly also gets a video.
- `DrawThingsKit` product (formerly the separate DrawThingsKit package, without its SwiftUI views,
  job queue and JSON codec): `@Observable` `ConnectionManager`, `ModelsManager` and
  `ConfigurationManager`, `ConfigurationManager.makeRequest()`, and IPv6 server profiles.
- `ConnectionOptions`: TLS verification policy, shared secret, client identity, message size,
  request timeout and model spec source. `ServerEndpoint` parses IPv6 addresses.
- `MediaProfile` and `GeneratedAudio` (planar PCM, `AVAudioPCMBuffer` and in-memory WAV).
  `ModelFamily.audioSampleRate`.
- Draw Things JSON: `DrawThingsConfiguration`, `LoRAConfig` and `ControlConfig` are `Codable` in the
  app's format, with `toJSON`, `fromJSON`, `mergeJSON`, `validateJSON` and `formatJSON` (moved
  from DrawThingsKit and rewritten to match the app).
- `DrawThingsConfiguration.validate()`; configuration fields `shiftForAudio`, `usesSolAttention`,
  `solAttentionStart`, `solAttentionTau`; full `ControlConfig` settings.
- `ModelSpecStore` with app-registered specs; the override includes refiner and stage models.
- `DrawThingsError`.
- `CGImage` forms of all image helpers; `loadCGImage(from:)` and `decodeCGImage(_:)` apply EXIF
  orientation.
- `Scripts/generate.sh` (code generation from a local draw-things-community checkout) and
  `Scripts/update-model-specs.sh`.
- `Examples/DrawThingsExample`, a SwiftUI app for macOS and iOS that rebuilds the earlier packages'
  views on the public API; CI builds it.
- CI for macOS and iOS; a weekly workflow that refreshes the bundled model specs.
- An in-process gRPC test server; 146 tests on Swift Testing, including the first tests for the queue,
  video and app-state code.

### Changed
- The repository is renamed DrawThings-Swift and the package `DrawThingsSwift`; the module is
  still `DrawThingsClient`.
- No network request by default: the models.drawthings.ai fetch is opt-in
  (`.bundledAndRemote()`), and the bundled snapshot is refreshed before releases (now 246 specs).
- TLS verifies public servers; local-network servers (including names that resolve to LAN
  addresses) keep accepting Draw Things' self-signed certificate.
- The service connects on first use and has an async `shutdown()`.
- `seed` is `UInt32?`; `seedMode` is `SeedMode`.
- `LatentModelFamily` is renamed `ModelFamily` (deprecated alias).
- `HintBuilder` is a `Sendable` struct whose `build()` throws.
- `ImageHelpers` and `AudioHelpers` are namespace enums.
- Image encoding and decoding use Accelerate (2048×2048 encode 25 → 9 ms, decode 15 → 2 ms).

### Fixed
- DrawThingsKit: the profile's shared secret was never sent; disconnecting or switching servers left
  the old connection open; one unreadable model in the server's list discarded the whole list.
- Video frame rates now follow Draw Things: a model's spec can set its own rate (some Wan 2.1 14B
  and Hunyuan models differ from their family), Hunyuan Video is 30 fps, Wan 2.2 5B is 24 fps, and
  Stable Video Diffusion counts as a 30 fps video model.
- fpzip's error code was a global written by every decode, a data race when tensors were decoded
  concurrently (found with the Thread Sanitizer). It is now per thread.
- VideoKit: ML frame interpolation gave every interpolated frame a timestamp of 0.
- A generation that failed on the server was returned as a success, with the last preview (a
  small latent-sized image) as its result. It now throws `DrawThingsError.incompleteResponse`.
- Audio could be missing from results, and progress and previews could arrive out of order.
- SwiftUI progress never updated (`ImageGenerationProgress` was a nested `ObservableObject`).
- Progress wasn't cleared after an error.
- Concurrent callers could skip the remote model spec fetch, and a failed fetch was never retried.
- Invalid configuration values trapped instead of throwing.
- Resized images were 2×/3× the requested size on Retina Macs and iPhones; `UIImage` orientation
  was ignored.
- `CGContext` wrote through a dangling pointer; tensor headers were read with misaligned loads;
  malformed or truncated tensors (including fpzip streams) could read out of bounds.
- `deinit` blocked and could trap on an event-loop thread.
- IPv6 addresses didn't parse; TLS to an IPv4 address failed (the IP was sent as the TLS server name).
- 4 MiB image chunks plus framing exceeded gRPC's default message limit.
- MiniMax H3 / LTX-2 decoded frames were cropped by the audio-row stripping meant for latents.
- Model specs were missing for 47 newer models (MiniMax H3, Qwen Image 2.1, Krea 2 Turbo, Ideogram 4…).

### Removed
- The `DrawThingsClient` class, `GenerationOutput`, `ImageGenerationProgress`, the closure-based
  `generateImage`, `ModelSpecProvider`, the ControlPanel stubs, deprecated `ImageHelpers` NSImage
  methods and `createMaskFromImage`, and `Examples/ConfigfromJSON.swift`.

## 1.7.2

- Removed the unsafe compiler flags from `CFpzip` so the package can be required by version.
  Every release from 1.6.0 to 1.7.1 failed as a version-pinned dependency.
- Added fpzip and deflate round-trip tests.
