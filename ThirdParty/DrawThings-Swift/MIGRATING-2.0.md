# Migrating to DrawThings-Swift 2.0

Version 2 moves to Swift 6, grpc-swift 2 and an event-stream API, and fixes a set of bugs that
could lose audio, show stale progress, crash on bad values or send rotated images. It also brings
the separate DrawThingsQueue, DrawThingsVideoKit and DrawThingsKit packages into this one as
optional products, without their SwiftUI views. Most changes are mechanical; this guide maps the
1.x API, and each of those packages, to 2.0.

| If you used | Read |
|---|---|
| DrawThingsClient 1.x | everything up to [Errors](#errors) |
| DrawThingsQueue 0.x | [DrawThingsQueue 0.x](#drawthingsqueue-0x) |
| DrawThingsVideoKit 0.x | [DrawThingsVideoKit 0.x](#drawthingsvideokit-0x) |
| DrawThingsKit 2.x | [DrawThingsKit 2.x](#drawthingskit-2x) |
| any of their SwiftUI views | [Examples/DrawThingsExample](Examples/DrawThingsExample), which rebuilds them on the public API |

## Requirements

| | 1.x | 2.0 |
|---|---|---|
| Platforms | macOS 14 / iOS 17 | **macOS 15 / iOS 18** |
| Swift | 5.9 | **6.0** (Xcode 16) |
| gRPC | grpc-swift 1.x | grpc-swift 2 |
| Package pin | `branch: "main"` (1.6–1.7.1 couldn't be pinned by version) | `from: "2.0.0"` |

Stay on `.upToNextMajor(from: "1.7.2")` (and DrawThingsQueue 0.1.1, DrawThingsVideoKit 0.3.1,
DrawThingsKit 2.2.1) until you can meet the new platform floor. An app gets one version of a
package, so the old Queue, VideoKit and Kit packages can't be combined with DrawThings-Swift 2.0;
move them together.

## Package

The repository is renamed **DrawThings-Swift** (GitHub redirects the old URL). Module names are
unchanged, but the `package:` label follows the new URL:

```swift
.package(url: "https://github.com/euphoriacyberware-ai/DrawThings-Swift", from: "2.0.0"),
// in the target, the products you use:
.product(name: "DrawThingsClient", package: "DrawThings-Swift"),
.product(name: "DrawThingsQueue", package: "DrawThings-Swift"),
.product(name: "DrawThingsVideoKit", package: "DrawThings-Swift"),
.product(name: "DrawThingsKit", package: "DrawThings-Swift"),
```

The libraries no longer import SwiftUI or Combine; their observable types use Observation, so
`@StateObject` becomes `@State`, `@ObservedObject` becomes a plain property (or `@Bindable` for
bindings), and `@EnvironmentObject` becomes `@Environment(Type.self)`.

## SwiftUI: `DrawThingsClient` → `DrawThingsSession`

| 1.x | 2.0 |
|---|---|
| `DrawThingsClient` (`ObservableObject`) | `DrawThingsSession` (`@Observable`) |
| `@StateObject var client` | `@State var session` |
| `init(address:useTLS:)` | `init(address:options:)` |
| `connect(sharedSecret:)` | `connect()`; the secret is in `ConnectionOptions` |
| `currentProgress: ImageGenerationProgress?` (a class whose changes views didn't see) | `progress: GenerationProgress?` (a value; views update on every step) |
| (previews not exposed) | `preview: CGImage?`, `previewImage` |
| `generateImage(prompt:…) -> [PlatformImage]` | `generate(_:) -> GenerationResult` (`.images`, `.platformImages`) or `generate(prompt:configuration:image:mask:hints:)` |
| `generateImageAndAudio(…) -> GenerationOutput` | `generate(_:)`; audio is `result.audio: [GeneratedAudio]` (`pcmBuffer()`, `wavData()`) |
| | `isGenerating`, `serverInfo`, `lastResult`, `cancel()` |

The class shared its name with the module, which prevented writing `DrawThingsClient.SomeType`;
that works now.

## `DrawThingsService`

### Creating and connecting

```swift
// 1.x
let service = try DrawThingsService(address: "host:7859", useTLS: true)
_ = try await service.echo(sharedSecret: "secret")

// 2.0
let service = try DrawThingsService(address: "host:7859", options: ConnectionOptions(
    security: .tls(),            // .plaintext for useTLS: false
    sharedSecret: "secret"
))
try await service.echo()
await service.shutdown()         // new: closes the connection
```

- The shared secret is set once in `ConnectionOptions`, not per call.
- IPv6 addresses (`[fe80::1]:7859`, `::1`) now parse; `ServerEndpoint` does the parsing.
- **TLS now verifies public servers.** 1.x never verified certificates. The default
  `.tls(verification: .automatic)` still accepts Draw Things' self-signed certificate on local
  networks (including host names that resolve to LAN addresses). For a self-signed server reached
  over the internet use `.tls(verification: .trustRoots([pem]))`, or `.none` to keep the 1.x
  behavior.

### Generating

`generateImage(prompt:…configuration: Data…progressHandler:previewHandler:audioHandler:) -> [Data]`
is replaced by a request value and an event stream:

```swift
// 1.x
let configData = try config.toFlatBufferData()
let imageData = try ImageHelpers.imageToDTTensor(input, forceRGB: true)
let tensors = try await service.generateImage(
    prompt: "…", configuration: configData, image: imageData,
    progressHandler: { signpost in … }, previewHandler: { data in … }, audioHandler: { data in … }
)
let images = try tensors.map { try ImageHelpers.dtTensorToImage($0, modelFamily: family) }

// 2.0
let request = GenerationRequest(prompt: "…", configuration: config, image: input)  // CGImage
for try await event in service.stream(request) {
    switch event {
    case .progress(let progress): …   // GenerationProgress (stage, step, totalSteps, fractionCompleted)
    case .preview(let image): …       // CGImage, already decoded with the right model family
    case .audio(let audio): …         // GeneratedAudio
    case .image, .remoteDownload: break
    case .completed(let result): …    // GenerationResult: images, audio, media, request
    }
}
// or: let result = try await service.generate(request)
```

- Encoding the configuration, input image and mask is done for you, off the main actor. The mask
  is encoded in Draw Things' mask format; 1.x README examples that sent a mask through
  `imageToDTTensor` crash the server.
- Events are delivered in server order and `.completed` is always last. In 1.x, handlers ran in
  unordered tasks and audio could be missing from the result.
- Cancelling the consuming task cancels the generation on the server.
- A generation that returns no image now throws `DrawThingsError.incompleteResponse`.
- `contents` and `scaleFactor` are no longer parameters.

### Model metadata

`ModelSpecProvider` is replaced by `ModelSpecStore` (`service.modelSpecs`).

- **1.x downloaded models.drawthings.ai on every connection. 2.0 makes no network request
  by default**: specs come from the server's echo and a bundled snapshot refreshed each release.
  Opt in with `ConnectionOptions(modelSpecs: .bundledAndRemote())`.
- Register specs for custom models with `await service.modelSpecs.register([...])`.
- The override now also includes the refiner's and stage models' specs.

## Configuration

| 1.x | 2.0 |
|---|---|
| `seed: Int64?` (truncated to 32 bits) | `seed: UInt32?`, `nil` = random |
| `seedMode: Int32` | `seedMode: SeedMode` (`.legacy`, `.torchcpucompatible`, `.scalealike`, `.nvidiagpucompatible`) |
| `width`/`height`/hires-fix sizes rounded to 64 by `didSet` (not in the initializer) | stored as given; rounded to 64 when encoded |
| `toFlatBufferData()` could trap on negative or oversized values | throws `DrawThingsError.invalidConfiguration(field:reason:)`; see `validate()` |
| `ControlConfig` properties `let` | `var`, plus `noPrompt`, `downSamplingRate`, `inputOverride`, `targetBlocks` |
| `LoRAConfig` properties `let` | `var` |
| | new: `shiftForAudio`, `usesSolAttention`, `solAttentionStart`, `solAttentionTau` |
| | `Codable` (Draw Things JSON), `Hashable` |

### JSON (from DrawThingsKit)

DrawThingsKit's `ConfigurationCodable.swift` moved into the client and was rewritten to Draw Things'
own format. The API names are the same, so Kit users only drop the Kit version:

| DrawThingsKit | DrawThingsClient 2.0 |
|---|---|
| `toJSON(includeSeed:)`, `fromJSON(_:)`, `mergeJSON(_:)`, `validateJSON(_:)`, `formatJSON(_:)` | same names on `DrawThingsConfiguration` |
| `ConfigurationJSON`, `ConfigurationJSON.LoRAJSON`, `ConfigurationJSON.ControlJSON` | removed; `DrawThingsConfiguration`, `LoRAConfig` and `ControlConfig` are `Codable` |
| `ConfigurationCodableError` | `DecodingError` / `DrawThingsError` |

Output is now complete Draw Things JSON that pastes into the app. It includes fields Kit dropped,
such as `compressionArtifacts`, `colorCalibration` and every control setting. Input accepts Kit's
older spellings. The app's compact "Copy Configuration" is an overlay: apply it with `mergeJSON`
on a base configuration.

`Examples/ConfigfromJSON.swift` is removed; use `DrawThingsConfiguration.fromJSON(_:)`.

## Images, tensors and hints

| 1.x | 2.0 |
|---|---|
| `LatentModelFamily` | `ModelFamily` (deprecated alias kept); adds `audioSampleRate` |
| `ImageHelpers` (struct) | `ImageHelpers` (namespace enum) |
| `dtTensorToImage` | still available; `dtTensorToCGImage` is the `Sendable` primitive |
| `nsImageToDTTensor`, `dtTensorToNSImage`, `dataToNSImage`, `createMaskFromImage` | removed |
| `resizeImage(_:to:)` size in points (2×/3× pixels on Retina/iPhone) | size in **pixels**; `resizedImage(_:width:height:)` for `CGImage` |
| `scaleImageToCanvas`, `fillTransparentAreas` rendered at screen scale | exact pixel size; `CGImage` forms `scaledImageToCanvas`, `filledTransparentAreas` |
| `cgImageRepresentation` ignored `UIImage` orientation | returns upright pixels |
| NaN/∞ decoded to mid-gray | NaN to mid-gray, ±∞ clamp to black/white |
| `AudioHelpers.ccvTensorToAudioBuffer(_:sampleRate:)` default 16 kHz | default 24 kHz; prefer `GeneratedAudio(tensor:sampleRate:)` |
| | `loadCGImage(from:)`, `decodeCGImage(_:)`, `pngData(for:)` apply EXIF orientation |

`HintBuilder` is now a `Sendable` struct:

```swift
// 1.x
let hints = HintBuilder().addPose(pose).addDepthMap(depth).build()

// 2.0
var builder = HintBuilder()
builder.addPose(pose)
builder.addDepthMap(depth)
let hints = try builder.build()   // throws HintBuildError instead of dropping unreadable images
```

`clear()` is now `removeAll()`. DrawThingsKit's `@_exported import class DrawThingsClient.HintBuilder`
must become `@_exported import struct`.

## Errors

`DrawThingsError` is new: `connectionFailed`, `unauthenticated`, `invalidConfiguration`,
`decodingFailed`, `incompleteResponse`, `server(code:message:)`. Cancellation is always
`CancellationError`.

## DrawThingsQueue 0.x

The queue is now the `DrawThingsQueue` product of this package; the separate DrawThingsQueue
repository stays at 0.1.1 for 1.x apps. Add
`.product(name: "DrawThingsQueue", package: "DrawThings-Swift")` and remove the old package.

| DrawThingsQueue 0.x | 2.0 |
|---|---|
| `DrawThingsQueue` (`ObservableObject`) | `GenerationQueue` (`@Observable`); the module is still `DrawThingsQueue` |
| `init(address:useTLS:sharedSecret:storage:)` | `init(service:storage:)`; TLS and the secret are in the service's `ConnectionOptions` |
| `updateConnection(...)` | set `queue.service` |
| Queue's own `GenerationRequest` (`PlatformImage` inputs, `name`) | the client's `GenerationRequest` (`CGImage` inputs); pass `name:` to `enqueue` |
| Queue's own `GenerationResult` (`images: [PlatformImage]`, `audioData: [Data]`) | the client's `GenerationResult` (`images: [CGImage]`, `platformImages`, `audio`) |
| `pendingRequests`, `currentRequest`, `completedResults`, `errors` | `pending`, `current`, `finished` (`QueueJob` values with a `status`), `jobs` |
| `currentProgress` (`ObservableObject` with `previewImage`) | `progress: GenerationProgress?`, `preview: CGImage?` |
| `lastError`, `pauseForReconnection(error:)` | `pauseReason`, `pause(reason:)` |
| `status(for:)`, `result(for:)` | `job(_:)?.status`, `job(_:)?.result` |
| `cancel(id:)`, `moveRequests(from:to:)`, `retryCount(for:)` | `cancel(_:)`, `movePending(fromOffsets:toOffset:)`, `job(_:)?.retryCount` |
| `clearErrors()` | `clearFailed()`; also `clearFinished()` |
| `events` (Combine `PassthroughSubject<JobEvent, Never>`) | `events: AsyncStream<QueueEvent>` |
| `results: AsyncStream<GenerationResult>` | unchanged |
| `loadPersistedRequests()` | `try await restore()` |
| `modelFamilyProvider`, `audioSampleRateProvider` | removed: set `GenerationRequest.modelFamily` / `audioSampleRate` when the file name isn't enough |

Behavior changes:

- Cancelled jobs now appear in `finished` with status `.cancelled`.
- A lost connection is detected from `DrawThingsError.connectionFailed` instead of matching words
  in the error message.
- Saved queues keep input images, masks, hints and overrides. Files saved by 0.x (same default
  location) are read, without those.

## DrawThingsVideoKit 0.x

VideoKit is now the `DrawThingsVideoKit` product of this package and no longer depends on
DrawThingsQueue; the separate repository stays at 0.3.1 for 1.x apps. Add
`.product(name: "DrawThingsVideoKit", package: "DrawThings-Swift")` and remove the old package.

| DrawThingsVideoKit 0.x | 2.0 |
|---|---|
| `VideoProcessor` (`ObservableObject`) | `VideoProcessor` (`@Observable`) |
| `connect(to: DrawThingsQueue)` | `connect(to:)` any `AsyncSequence` of `GenerationResult`, such as `queue.results`; or `ingest(_:)` |
| `events` (Combine `PassthroughSubject`) | `events: AsyncStream<VideoProcessorEvent>` |
| `addFrames(from: [PlatformImage], result:)` | `addFrames(from: GenerationResult)` |
| `updateConfiguration(_:)` | set `processor.configuration` |
| video detection: `numFrames > 1` | `result.media.isVideo` (only video models; `numFrames` defaults to 14 for every configuration) |
| frame rate: `LatentModelFamily.detect(from:).nativeFrameRate ?? 16` | `result.media.frameRate` |
| audio: `result.audioData` (WAV from the Queue) | `result.audio` (`GeneratedAudio`); collected as WAV in `collectedFrames.audioData` |
| `VideoFrameMetadata.seed: Int64?` | `UInt32?`; saved collections still load |
| VideoKit's own `PlatformImage` typealias | the core's `PlatformImage` |
| `VideoConfigurationView`, `VideoAssemblyProgressView`, `VideoFrameCollectionView` | removed; the library has no views (see the example app) |
| `DrawThingsVideoKitInfo` | removed |

New: `lastOutputURL`, and automatic assemblies are queued instead of skipped while another is
running.

## DrawThingsKit 2.x

Kit is now the `DrawThingsKit` product of this package; the separate repository stays at 2.2.1 for
1.x apps. Add `.product(name: "DrawThingsKit", package: "DrawThings-Swift")` and remove the old
package. `import DrawThingsKit` still imports the client; it no longer imports the queue (add
`DrawThingsQueue` if you use it).

| DrawThingsKit 2.2 | 2.0 |
|---|---|
| `ConnectionManager`, `ModelsManager`, `ConfigurationManager` (`ObservableObject`) | the same classes, `@Observable`: use `@State` instead of `@StateObject` and `@Environment(Type.self)` instead of `@EnvironmentObject` |
| `JobQueue`, `GenerationJob`, `JobProgress`, `JobStatus`, Kit's `JobEvent` | `GenerationQueue` and `QueueJob` (DrawThingsQueue) |
| `ConfigurationCodable`, `ConfigurationJSON`, `ConfigurationCodableError` | the client's `DrawThingsConfiguration` JSON API (same method names) |
| `ConfigurationManager.copyToClipboard()` / `pasteFromClipboard()` | `exportToJSON()` / `loadFromJSON(_:)` with the pasteboard in your app |
| | `ConfigurationManager.makeRequest(image:mask:hints:)` |
| `ModelsManager.latentModelFamily(forFile:)` | `modelFamily(forFile:)` |
| `CheckpointModel.framesPerSecond`, `.audioSampleRate` (own tables) | same properties, from the client's tables (Wan 2.2 5B 24 fps, SVD 30, Hunyuan 30) |
| `ModelSource.iconColor` | removed; choose colors in your views (`iconName` stays) |
| `ServerProfile` | also `connectionOptions`; IPv6 addresses parse |
| the 15 connection and queue views | removed; the library has no views (see the example app) |

Behavior changes: the profile's shared secret is now sent when connecting;
`serverRequiresSharedSecret` is set when the server rejects the connection for a missing or wrong
secret; disconnecting closes the connection.

## Removed

- `DrawThingsClient` class, `GenerationOutput`, `ImageGenerationProgress`
- `DrawThingsService.init(address:useTLS:)`, `generateImage(…)`, the per-call `sharedSecret` parameter
- `ModelSpecProvider`
- the ControlPanel service stubs
- deprecated `ImageHelpers` NSImage methods and `createMaskFromImage`
- `Examples/ConfigfromJSON.swift` and `Examples/SwiftUIExample` (see `Examples/DrawThingsExample`)
- the SwiftUI views of DrawThingsVideoKit and DrawThingsKit
