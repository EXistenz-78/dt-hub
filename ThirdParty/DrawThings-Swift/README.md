<p align="center">
  <img src="Assets/logo.png" alt="DrawThings-Swift Logo" width="200"/>
</p>

# DrawThings-Swift

Swift libraries for apps that generate images, video and audio with a [Draw Things](https://drawthings.ai) gRPC server, on macOS and iOS.

| Product | What it does |
|---|---|
| **DrawThingsClient** | Speaks the Draw Things gRPC protocol: connection and TLS, configurations and Draw Things JSON, model specifications, Draw Things' tensor image format, and a stream of progress, previews, images and audio. `DrawThingsSession` wraps it for SwiftUI. |
| **DrawThingsQueue** | `GenerationQueue` runs many requests in order, with pause, cancel, retry, reordering and saved queues. |
| **DrawThingsVideoKit** | `VideoProcessor` turns video results into video files at the model's frame rate, with its audio, optional frame interpolation and super resolution. |
| **DrawThingsKit** | App state: saved servers and `ConnectionManager`, the server's model catalog plus Draw Things+ models, and the configuration being edited. |

Only DrawThingsClient is required; add the others as you need them. The libraries contain no views: their state types are `@Observable`, so SwiftUI views update as they change. [Examples/DrawThingsExample](Examples/DrawThingsExample) is a complete app built on all four.

> **Upgrading?** Version 2 is a major rework, and it replaces the separate DrawThingsQueue, DrawThingsVideoKit and DrawThingsKit packages. See [MIGRATING-2.0.md](MIGRATING-2.0.md) and the [CHANGELOG](CHANGELOG.md).

## Features

- **Swift 6 concurrency**: `Sendable` value types, an actor-based service and an `AsyncThrowingStream` of generation events delivered in server order.
- **SwiftUI-ready, no views**: `@Observable` session, queue, video processor and app state that SwiftUI views observe directly.
- **Cancellation**: cancelling the task (or leaving the event loop) cancels the generation on the server.
- **Video and audio**: frames, generated audio (`GeneratedAudio`, with WAV export) and each model's frame rate and audio sample rate.
- **Draw Things JSON**: read and write the app's configuration JSON, including its "Copy Configuration" output.
- **Model specifications**: the specs servers need for newer models come from the server, a snapshot bundled with the package, or (opt-in) the live Draw Things list; no network request by default.
- **Safe with untrusted data**: tensor headers, compressed payloads and configuration values are validated; bad data throws instead of crashing.
- **TLS**: verifies public servers and accepts the self-signed certificates Draw Things uses on local networks.
- **Queues that survive a relaunch**: pending jobs are saved with their input images, masks and hints; a lost connection pauses the queue instead of failing jobs.
- **Video files**: H.264, HEVC or ProRes with the generated audio muxed in, ML frame interpolation and super resolution where the system supports them, with Core Image fallbacks.

## Requirements

- macOS 15 / iOS 18
- Swift 6 (Xcode 16 or later)
- A Draw Things gRPC server: the Draw Things app with its API server enabled, or the standalone `gRPCServerCLI`

### Draw Things server settings

| Setting | Supported | Notes |
|---|---|---|
| Response compression | On or off | The client decompresses responses. |
| Transport Layer Security | On or off | Match `ConnectionOptions.security` to the server. TLS is recommended. |
| Bridge Mode (e.g. Draw Things+) | On or off | Generation passes through to the bridged server. Some models only run locally, and DT+ Bring Your Own LoRA isn't supported through a bridge (a DT+ limitation). |
| Enable Model Browsing | On or off | When on, the server reports its installed models and their specs; when off, the client uses its bundled specs. Model browsing is needed to list a server's models in a UI. |
| Shared Secret | On or off | Set `ConnectionOptions.sharedSecret`. |

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/euphoriacyberware-ai/DrawThings-Swift", from: "2.2.0")
]
```

Then add the products you use to your target:

```swift
.product(name: "DrawThingsClient", package: "DrawThings-Swift"),
.product(name: "DrawThingsQueue", package: "DrawThings-Swift"),     // optional
.product(name: "DrawThingsVideoKit", package: "DrawThings-Swift"),  // optional
.product(name: "DrawThingsKit", package: "DrawThings-Swift"),       // optional
```

Each optional product depends only on DrawThingsClient, and `import DrawThingsKit` also imports DrawThingsClient.

**Third-party packages** (resolved by Swift Package Manager): [grpc-swift-2](https://github.com/grpc/grpc-swift-2), [grpc-swift-nio-transport](https://github.com/grpc/grpc-swift-nio-transport), [grpc-swift-protobuf](https://github.com/grpc/grpc-swift-protobuf), [swift-protobuf](https://github.com/apple/swift-protobuf) and [flatbuffers](https://github.com/google/flatbuffers). fpzip (floating-point tensor decompression) is bundled as the `CFpzip` target.

## AI coding agents

[`skills/drawthings-swift`](skills/drawthings-swift/SKILL.md) is an [Agent Skill](https://agentskills.io) that teaches coding agents how to use these libraries in an app: which product to use, the settings and connection rules that avoid failed generations, and the 2.x APIs (models often suggest 1.x code that no longer compiles). Install it into your app's project with the cross-agent installer, which asks which agents you use:

```bash
npx skills add euphoriacyberware-ai/DrawThings-Swift --skill drawthings-swift
```

Or copy the `skills/drawthings-swift` folder into the agent's skills folder:

| Agent | Project folder | Personal folder |
|---|---|---|
| Claude Code | `.claude/skills/` | `~/.claude/skills/` |
| OpenAI Codex | `.agents/skills/` | `~/.agents/skills/` |
| Qwen Code | `.qwen/skills/` | `~/.qwen/skills/` |
| DeepSeek agents (Deep Code, DeepSeek Harness) | | `~/.agents/skills/` |

Agents working on this repository itself read [AGENTS.md](AGENTS.md) (Claude Code through `CLAUDE.md`, Qwen Code through `QWEN.md`).

## Quick start

### SwiftUI

```swift
import SwiftUI
import DrawThingsClient

struct ContentView: View {
    @State private var session = try! DrawThingsSession(address: "localhost:7859")
    @State private var image: CGImage?

    var body: some View {
        VStack {
            if let progress = session.progress {
                Text(progress.stage.description)
                ProgressView(value: progress.fractionCompleted ?? 0)
            }
            if let preview = session.preview ?? image {
                Image(decorative: preview, scale: 1).resizable().scaledToFit()
            }
            Button("Generate") {
                Task {
                    // A failure is also kept in session.lastError.
                    let result = try? await session.generate(GenerationRequest(
                        prompt: "A lighthouse on a rocky coast at sunset",
                        configuration: DrawThingsConfiguration(
                            width: 1024, height: 1024, steps: 8,
                            model: "z_image_turbo_1.0_q8p.ckpt",
                            sampler: .unipctrailing, guidanceScale: 1, shift: 3, resolutionDependentShift: false
                        )
                    ))
                    image = result?.images.first ?? image
                }
            }
            .disabled(!session.isConnected || session.isGenerating)
        }
        .task { await session.connect() }
    }
}
```

`DrawThingsSession` exposes `isConnected`, `serverInfo`, `isGenerating`, `progress`, `preview`, `remoteDownload`, `lastResult` and `lastError`, plus `cancel()`. It runs one generation at a time; `generate` throws `SessionError.busy` if another is running. For more than one at a time, use [`GenerationQueue`](#drawthingsqueue).

> **Model settings matter.** Sampler, steps, guidance and shift depend on the model. The examples use Z Image Turbo, which most Draw Things servers have, with Draw Things' own preset for it (8 steps, UniPC Trailing, guidance 1, shift 3, no resolution-dependent shift). These are also `DrawThingsConfiguration()`'s defaults, so changing only `model` leaves settings meant for Z Image Turbo. With unsuitable settings the server returns no image, the client throws `DrawThingsError.incompleteResponse`, and some servers crash on the next request. The easiest source of correct settings for another model is Draw Things itself: use Copy Configuration and [load the JSON](#draw-things-configuration-json).

### Without SwiftUI

```swift
import DrawThingsClient

let service = try DrawThingsService(address: "localhost:7859")

// Stream events as they arrive...
let request = GenerationRequest(prompt: "A red fox in fresh snow", configuration: configuration)
for try await event in service.stream(request) {
    switch event {
    case .progress(let progress): print(progress.stage)
    case .preview(let preview): show(preview)                // CGImage
    case .remoteDownload(let download): print(download.fractionCompleted ?? 0)
    case .image(let image, let index): save(image, index)    // each final image as it arrives
    case .audio(let audio): play(audio)                      // GeneratedAudio
    case .completed(let result): print(result.duration)      // always last
    }
}

// ...or just wait for the result.
let result = try await service.generate(request)
let images: [CGImage] = result.images           // or result.platformImages

await service.shutdown()
```

Events arrive in the order the server sends them. Cancelling the task that consumes the stream, or breaking out of the loop, cancels the generation on the server; `generate(_:)` then throws `CancellationError`.

## Connecting

```swift
// host:port, bare host (port 7859), [IPv6]:port or a bare IPv6 address
let endpoint = try ServerEndpoint("192.168.1.20:7859")

let service = DrawThingsService(endpoint: endpoint, options: ConnectionOptions(
    security: .tls(),                 // or .plaintext; must match the server
    sharedSecret: "my-secret",        // when the server requires one
    clientIdentity: ClientIdentity(user: "My App", device: .laptop),
    requestTimeout: .seconds(30),     // unary calls; generations are not limited
    modelSpecs: .bundled              // or .bundledAndRemote() to use the live model list
))

let reply = try await service.echo()  // checks the connection; reply.files lists installed models
```

No network activity happens until the first call. Call `shutdown()` when you are done with a service.

### TLS certificate verification

Draw Things serves a self-signed certificate. With the default `.tls(verification: .automatic)`, the client skips verification for **local-network** hosts (loopback, private and link-local addresses, `.local` names, single-label names, and host names that resolve only to such addresses) and verifies public hosts fully against the system trust store.

| Verification | Use |
|---|---|
| `.automatic` (default) | Local servers work out of the box; public servers are verified. |
| `.full` | Always verify against the system trust store. |
| `.trustRoots([pem])` | Verify a self-signed server reached over the internet by its certificate. |
| `.none` | Never verify (encrypted but open to interception). |

A TLS/plaintext mismatch or a rejected certificate surfaces as `DrawThingsError.connectionFailed` with a hint.

## Requests

```swift
var configuration = DrawThingsConfiguration(
    width: 1024, height: 1024, steps: 8,
    model: "z_image_turbo_1.0_q8p.ckpt",
    sampler: .unipctrailing,
    guidanceScale: 1,
    seed: 12345,          // nil = random
    shift: 3,
    resolutionDependentShift: false
)

let request = GenerationRequest(
    prompt: "A watercolor of a harbor",
    negativePrompt: "blurry",
    configuration: configuration,
    image: inputImage,    // CGImage: image-to-image / inpainting canvas
    mask: maskImage,      // CGImage: transparent pixels are regenerated
    hints: try hints.build()
)
```

Sizes are in pixels and are sent to the server in units of 64, rounded down. `validate()` reports values the server can't accept (and `toFlatBufferData()` calls it), so a bad configuration throws `DrawThingsError.invalidConfiguration(field:reason:)` instead of crashing. Image inputs are `CGImage`; for `NSImage`/`UIImage` use `image.cgImageRepresentation`, which also applies `UIImage` orientation, or `DrawThingsSession.generate(prompt:configuration:image:mask:)`.

### Image to image and inpainting

```swift
var configuration = DrawThingsConfiguration(
    width: 768, height: 768, steps: 8, model: "z_image_turbo_1.0_q8p.ckpt",
    sampler: .unipctrailing, guidanceScale: 1, shift: 3, strength: 0.6, resolutionDependentShift: false
)
let request = GenerationRequest(prompt: "A red fox, watercolor", configuration: configuration, image: photo)

// Inpainting: pass a mask whose transparent pixels mark the area to regenerate.
configuration.strength = 1
let inpaint = GenerationRequest(prompt: "A cat on the bench", configuration: configuration, image: photo, mask: mask)
```

The client encodes the canvas as an RGB tensor and the mask as Draw Things' 1-byte mask tensor (an RGB tensor sent as a mask crashes the server). Set `enableInpainting` for models that need the inpaint control.

### LoRAs

```swift
configuration.loras = [
    LoRAConfig(file: "my_z_image_style_lora_f16.ckpt", weight: 0.8),   // mode: .all (or .base, .refiner)
]
```

A LoRA must be trained for the configuration's model (here Z Image); use the file name Draw Things shows for an imported LoRA. The client sends a specification for each LoRA. A LoRA with no known spec gets a minimal one using the model's version, because the server silently skips LoRAs it has no spec for.

### Hints, moodboard and ControlNet

```swift
var hints = HintBuilder()
hints.addMoodboardImage(referencePNG)              // "shuffle"
hints.addDepthMap(depthPNG, weight: 0.8)
hints.addHint(type: .tile, imageData: tileJPEG)
let request = GenerationRequest(prompt: "...", configuration: configuration, hints: try hints.build())
```

`HintBuilder` takes encoded images (PNG, JPEG, HEIC...), applies EXIF orientation, and throws `HintBuildError` for an image it can't decode instead of dropping it. Hint types keep the order they were first added.

| Method | Hint type |
|---|---|
| `addMoodboardImage(_:weight:)`, `addMoodboardImages(_:weight:)` | `shuffle` |
| `addDepthMap(_:weight:)` | `depth` |
| `addPose(_:weight:)` | `pose` |
| `addCannyEdges(_:weight:)` | `canny` |
| `addScribble(_:weight:)` | `scribble` |
| `addColorReference(_:weight:)` | `color` |
| `addLineArt(_:weight:)` | `lineart` |
| `addHint(type:imageData:weight:)` | any `HintType` or string |

ControlNet models are configured as controls; their input images are sent as hints:

```swift
configuration.controls = [
    ControlConfig(file: "my_depth_controlnet_f16.ckpt", weight: 0.8, guidanceEnd: 0.7, controlMode: .control),
]
```

As with LoRAs, a ControlNet must be made for the configuration's model family; Draw Things ships none for Z Image Turbo, so import one or use a model that has them.

`ControlConfig` carries every Draw Things control setting: `weight`, `guidanceStart`/`guidanceEnd`, `controlMode` (`.balanced`, `.prompt`, `.control`), `globalAveragePooling` (true only for Shuffle), `noPrompt`, `downSamplingRate`, `inputOverride` and `targetBlocks`.

### Video and audio

```swift
// MiniMax H3 with a 3-step turbo LoRA, as copied from Draw Things ("H3 + Turbo" in DT Config Examples).
var configuration = DrawThingsConfiguration(
    width: 576, height: 384, steps: 4, model: "minimax_h3_fl2va_q8p.ckpt",
    sampler: .ddimtrailing, guidanceScale: 1, shift: 12, numFrames: 49
)
configuration.loras = [LoRAConfig(file: "taomate_h3_3step_comfyui_lora_f16.ckpt", weight: 0.6)]
let result = try await service.generate(GenerationRequest(prompt: "Waves on a beach, gulls calling", configuration: configuration))

result.media.isVideo          // true
result.media.frameRate        // 24
result.images                 // the frames, in order
if let audio = result.audio.first {
    try audio.wavData().write(to: wavURL)   // 32-bit float WAV, 32 kHz for MiniMax H3
    let buffer = try audio.pcmBuffer()      // AVAudioPCMBuffer
}
```

`result.media` (a `MediaProfile`) gives the model family, whether the output is a video, its frame rate and the audio sample rate. The frame rate follows Draw Things: the model's own spec when it sets one, otherwise its version or family. Generated audio has no rate metadata, so the rate comes from the model; override it with `GenerationRequest.audioSampleRate` (and the family with `modelFamily`) for custom models. To turn the frames into a video file, see [DrawThingsVideoKit](#drawthingsvideokit).

## Draw Things configuration JSON

`DrawThingsConfiguration` is `Codable` in Draw Things' own JSON format, the format you paste into and copy from the app.

```swift
let configuration = try DrawThingsConfiguration.fromJSON(json)
let json = try configuration.toJSON()                 // pretty-printed, sorted keys
let json = try configuration.toJSON(includeSeed: false)  // seed -1 (random)

let result = DrawThingsConfiguration.validateJSON(text)  // isValid, error, configuration
let pretty = DrawThingsConfiguration.formatJSON(text)
```

The app produces the format in two shapes:

- **Copy Configuration** writes a compact subset: the settings relevant to the current model. Pasting it into the app changes only those settings, so it's an overlay. To apply it the same way, merge it onto a base configuration:

  ```swift
  var configuration = myDefaults
  try configuration.mergeJSON(copiedJSON)   // only keys present in the JSON change
  ```

- **Complete exports** (such as GetConfigPro) contain every key. `toJSON()` writes this shape, so its output reproduces the whole configuration when pasted into Draw Things.

`fromJSON` accepts both shapes: missing keys take `DrawThingsConfiguration`'s defaults. Example exports of both shapes are in [DT Config Examples](DT%20Config%20Examples).

Values in the JSON:

| Field | JSON | Swift |
|---|---|---|
| `width`, `height`, tile and hires-fix sizes | pixels | `Int32` pixels |
| `seed` | integer, `-1` = random | `UInt32?`, `nil` = random |
| `sampler`, `seedMode` | integer | `SamplerType`, `SeedMode` |
| `loras[].mode` | `"all"`, `"base"`, `"refiner"` | `LoRAMode` |
| `controls[].controlImportance` | `"balanced"`, `"prompt"`, `"control"` | `ControlMode` |
| `controls[].inputOverride` | `""`, `"depth"`, `"inpaint"`... | `ControlInputType` |
| `compressionArtifacts` | `"disabled"`, `"h264"`, `"h265"`, `"jpeg"` | `CompressionMethod` |
| `colorCalibration` | `"none"` (older exports: `"disabled"`), `"lab"` | `ColorCalibration` |
| `upscaler`, `faceRestoration`, `refinerModel` | `""` or `null` = none | `String?` |
| `causalInference` | `0` = off | `causalInferenceEnabled` + `causalInference` |

<details>
<summary>Sampler values</summary>

| Sampler | Value | Sampler | Value |
|---|---|---|---|
| `dpmpp2mkarras` | 0 | `dpmpp2mays` | 12 |
| `eulera` | 1 | `euleraays` | 13 |
| `ddim` | 2 | `dpmppsdeays` | 14 |
| `plms` | 3 | `dpmpp2mtrailing` | 15 |
| `dpmppsdekarras` | 4 | `ddimtrailing` | 16 |
| `unipc` | 5 | `unipctrailing` | 17 |
| `lcm` | 6 | `unipcays` | 18 |
| `eulerasubstep` | 7 | `tcdtrailing` | 19 |
| `dpmppsdesubstep` | 8 | | |
| `tcd` | 9 | | |
| `euleratrailing` | 10 | | |
| `dpmppsdetrailing` | 11 | | |

</details>

## Model specifications

A Draw Things server needs each request's model specification (version, latent space, objective...) to run models it doesn't have built in; without one it falls back to SD 1.x defaults and produces noise. The client resolves specs in this order:

1. specs your app registers: `await service.modelSpecs.register([ModelSpec(json:)...])`
2. the live Draw Things model list, only with `ConnectionOptions(modelSpecs: .bundledAndRemote())`
3. the snapshot bundled with this package, refreshed before each release (`Scripts/update-model-specs.sh`, run weekly by CI)
4. the specs the server reports in its echo reply (none when model browsing is off)

Built-in models, including quantized variants such as `_q8p`, are known to every server. Pass `GenerationRequest.override` to send your own `MetadataOverride` instead.

## Images and tensors

Draw Things exchanges images as tensors (a 68-byte header followed by Float16 values), not PNG or JPEG. `DrawThingsService` converts for you; `ImageHelpers` exposes the conversions for custom use:

```swift
let tensor = try ImageHelpers.imageToDTTensor(cgImage, forceRGB: true)
let image = try ImageHelpers.dtTensorToCGImage(tensor, modelFamily: .flux)   // previews need the family
let mask = try ImageHelpers.createMaskFromAlpha(maskImage)                   // Draw Things mask format

let upright = try ImageHelpers.loadCGImage(from: url)                        // applies EXIF orientation
try ImageHelpers.saveImage(image, to: outputURL, format: .png)
let resized = ImageHelpers.resizedImage(image, width: 1024, height: 768)     // exact pixels
let fitted = ImageHelpers.scaledImageToCanvas(image, canvasWidth: 1024, canvasHeight: 1024, backgroundColor: nil)
```

Every helper has a `CGImage` form (exact pixels, `Sendable`) and a `PlatformImage` (`NSImage`/`UIImage`) form. Results are rendered at one pixel per point, so sizes don't depend on the screen's scale.

### Model families

Previews are latents whose colors depend on the model architecture. The client picks the family from the model file name (`ModelFamily.detect(from:)`); override it with `GenerationRequest.modelFamily`.

| Family | Models | Latent channels | FPS | Audio |
|---|---|---|---|---|
| `.sd1` | SD 1.x, SD 2.x, SVD | 4 | 30 (SVD) | |
| `.sdxl` | SDXL, SSD-1B, PixArt, AuraFlow | 4 | | |
| `.sd3` | Stable Diffusion 3 | 16 | | |
| `.flux` | Flux.1, HiDream-I1, SeedVR2 | 16 | | |
| `.flux2` | Flux.2, Ernie Image, Ideogram 4 | 32 | | |
| `.qwen` | Qwen Image, Qwen Image Edit, Cosmos 2.5, Krea 2 | 16 | | |
| `.qwen21` | Qwen Image 2.1 | 64 | | |
| `.zImage` | Z Image | 16 | | |
| `.wan21` | Wan 2.1 | 16 | 16 | |
| `.wan22` | Wan 2.2 5B | 48 | 24 | |
| `.hunyuanVideo` | HunyuanVideo | 16 | 30 | |
| `.ltx2` | LTX-2 | 16 | 25 | 24 kHz |
| `.ltx23` | LTX-2.3 | 16 | 25 | 48 kHz |
| `.minimaxH3` | MiniMax H3 | 24 | 24 | 32 kHz |
| `.longcatVideoAvatar` | LongCat-Video Avatar 1.5 | 16 | 25 | 16 kHz |
| `.hiDreamO1` | HiDream-O1 | 3072 (patch-packed) | | |
| `.kandinsky` | Kandinsky 2.1 | 4 (OKLab) | | |
| `.wurstchen` | Würstchen / Stable Cascade | 4 | | |

The FPS column is the family's usual rate; some models set their own in their spec (several Wan 2.1 14B and HunyuanVideo models run at 24 or 30), and the result's `media.frameRate` uses it. MiniMax H3 and LTX-2 pack audio latent rows below the video latent; they are stripped from previews automatically. Qwen Image 2.1 returns final images as RGBA from its transparent decoder.

## Errors

```swift
do {
    let result = try await service.generate(request)
} catch is CancellationError {
    // cancelled by the app
} catch let error as DrawThingsError {
    switch error {
    case .connectionFailed(let detail): ...          // unreachable, TLS mismatch, rejected certificate
    case .unauthenticated: ...                       // shared secret missing or wrong
    case .invalidConfiguration(let field, let reason): ...
    case .decodingFailed(let detail): ...
    case .incompleteResponse(let detail): ...        // stream ended early or returned no image
    case .server(let code, let message): ...         // gRPC error from the server
    }
}
```

## DrawThingsQueue

`GenerationQueue` runs requests one at a time, in order, on a `DrawThingsService`.

```swift
import DrawThingsQueue

let queue = GenerationQueue(
    service: service,
    storage: QueueStorage()       // optional: save pending jobs across launches
)
try await queue.restore()         // reload jobs saved by an earlier run

queue.enqueue(request)                                   // returns the QueueJob
queue.enqueue(contentsOf: requests)

for await result in queue.results {                      // each completed GenerationResult
    save(result.images)
}
```

| Property / method | |
|---|---|
| `pending`, `current`, `finished`, `jobs` | `QueueJob` values with `status` (`.pending`, `.running`, `.completed`, `.failed`, `.cancelled`), `result`, `error`, `retryCount` and timings |
| `progress`, `preview`, `remoteDownload` | the running job's progress |
| `pause()`, `resume()`, `isPaused`, `pauseReason` | pausing lets the running job finish |
| `cancel(_:)`, `cancelAll()` | pending or running jobs; cancelled jobs move to `finished` |
| `retry(_:)`, `canRetry(_:)`, `maxRetries` | puts a failed job back at the end |
| `movePending(fromOffsets:toOffset:)`, `remove(_:)` | same arguments as SwiftUI's `onMove` |
| `clearCompleted()`, `clearFailed()`, `clearFinished()`, `clearAll()`, `maxFinishedJobs` | housekeeping |
| `events`, `results` | `AsyncStream`s; each access starts a new subscription |

A configuration without a seed gets a random one when it is queued, so every result can be reproduced. If the server can't be reached, the job goes back to the front of the queue and the queue pauses with a `pauseReason`; set `queue.service` to another server if needed and call `resume()`. `QueueStorage` saves whole requests, including input images, masks and hints, and reads queues saved by DrawThingsQueue 0.x.

## DrawThingsVideoKit

`VideoProcessor` collects the frames and audio of video results and assembles them into a video file.

```swift
import DrawThingsVideoKit

let processor = VideoProcessor(configuration: VideoProcessorConfiguration(
    autoAssemble: true,
    defaultVideoConfiguration: VideoConfiguration(outputURL: outputURL),
    configurationProvider: { jobID in                    // optional: a file per job
        VideoConfiguration(outputURL: folder.appending(path: "\(jobID).mp4"))
    }
))
processor.connect(to: queue.results)                     // any AsyncSequence of GenerationResult
// or: processor.ingest(try await service.generate(request))

for await event in processor.events {
    if case .assemblyCompleted(_, let url) = event { print("Saved \(url)") }
}
```

Only video results are collected (`result.media.isVideo`), the video plays at the model's frame rate (`result.media.frameRate`), and the first audio track is muxed in. Automatic assemblies run one at a time, in order. `collectedFrames`, `isAssembling`, `assemblyProgress`, `lastOutputURL` and `lastError` are observable.

`VideoConfiguration` sets the codec (`.h264`, `.hevc`, `.proRes422`, `.proRes4444`), quality, and optional processing:

| Setting | Uses | Fallback |
|---|---|---|
| `interpolation: .enabled(factor:)` with `frameRate` | VTFrameProcessor motion-aware interpolation (macOS 15.4+, iOS 26+, not the simulator) | Core Image cross-dissolve |
| `interpolationPassMode: .multiPass` | two 2× passes for 4×, which can reduce artifacts in fast motion | |
| `superResolution: .enabled(factor:)` | VTSuperResolutionScaler (macOS 26+, iOS 26+, up to 1920×1080 input; Apple's model downloads on first use) | Lanczos scaling |

With interpolation, set `frameRate` to `sourceFrameRate × factor` to keep the duration. `VideoAssembler` can also be used directly with a `VideoFrameCollection` of `CGImage`s or image files, and `VideoFrameCollection.save(to:)` / `load(from:)` keep frames and audio for re-encoding later. Sandboxed macOS apps that save to a user-chosen folder need the `com.apple.security.files.user-selected.read-write` entitlement.

## DrawThingsKit

App-level state, all `@Observable` and `@MainActor`:

```swift
import DrawThingsKit

@State private var connection = ConnectionManager()      // saved servers; a localhost profile on first launch
@State private var configuration = ConfigurationManager()

await connection.connectToDefault()
let models = connection.modelsManager                     // what the server reported
configuration.selectedCheckpoint = models.baseModels.first
let request = configuration.makeRequest()                 // prompt, model, LoRAs and configuration
```

- **`ConnectionManager`** keeps `ServerProfile`s (host, port, TLS, shared secret), connects with an echo that checks the shared secret, and exposes `activeService`, `connectionState` and `serverRequiresSharedSecret`. Profiles are saved in `UserDefaults` and their shared secrets in the Keychain.
- **`ModelsManager`** lists the server's checkpoints, LoRAs, ControlNets, textual inversions and upscalers (with model browsing on). With `bridgeMode` it adds the official and community models available through Draw Things+, bundled as `CloudModels`. `compatibleLoRAs` and `compatibleControlNets` follow the selected checkpoint's version.
- **`ConfigurationManager`** holds the prompt, selected models, LoRAs and ControlNets, and the `DrawThingsConfiguration`. `loadFromJSON(_:)` and `exportToJSON()` read and write Draw Things JSON, for copy and paste with the app through the system pasteboard.
- **Presets**: `DimensionPresets`, `SamplerPresets` (display names for every sampler) and `SavedConfiguration` (a SwiftData model for saved configurations).

## Example app

[Examples/DrawThingsExample](Examples/DrawThingsExample) is a SwiftUI app for macOS and iOS: server profiles, generation with a configuration pasted from Draw Things, the queue with progress and reordering, and video assembly with a player. It rebuilds the views the earlier packages shipped, using only the public API. Open its `Package.swift` in Xcode and run.

## Logging

`DTLogger` is built on `os.log` and shared by all four products. It is off by default.

```swift
DTLogger.minimumLevel = .debug              // .debug, .info, .warning, .error, .fault, .none
DTLogger.shared.logToConsole = true         // mirror to stdout (default: DEBUG builds)
```

Categories: `.connection`, `.queue`, `.generation`, `.grpc`, `.models`, `.configuration`, `.images`, `.video`, `.general`. View them in Console.app (subsystem `com.drawthings`) or with:

```bash
log stream --predicate 'subsystem == "com.drawthings"' --level debug
```

## Development

```bash
swift build
swift test
```

The tests include an in-process gRPC server that stands in for Draw Things, so they need no running server. The four tests that encode video are skipped on GitHub Actions, where `AVAssetWriter` crashes intermittently on the hosted macOS VMs; run them locally.

- `Scripts/generate.sh <path-to-draw-things-community>` regenerates the protobuf, gRPC and FlatBuffers code in `Sources/DrawThingsClient/Generated` (and the test server stubs) from the protocol schemas in a local checkout of [draw-things-community](https://github.com/drawthingsai/draw-things-community). The schemas themselves are not stored in this repository. It needs `protoc` and `flatc` 25.9.23; the protoc plugins are built from the package's pinned dependencies.
- `Scripts/update-model-specs.sh` refreshes the bundled `models.json`. CI runs it weekly and opens a pull request when it changed.

## Credits

This Swift framework began as a port of the TypeScript implementation by KC Jerrell: [dt-grpc-ts](https://github.com/kcjerrell/dt-grpc-ts). Special thanks to KC for pioneering the TypeScript gRPC client for Draw Things, which served as the foundation for this Swift implementation.

## License

MIT License. See [LICENSE](LICENSE).

## Disclaimer

The "Draw Things" name is used in this project only because Draw Things is the application these libraries are designed to work with. The author is not affiliated with, endorsed by, or associated with the developers of Draw Things.

DrawThings-Swift is an independent client for the Draw Things gRPC protocol. To interoperate with Draw Things servers, its generated protocol code (`Sources/DrawThingsClient/Generated`) is produced from the protocol and configuration schemas published in [draw-things-community](https://github.com/drawthingsai/draw-things-community) (GPL-3.0), and parts of its tensor, preview and configuration handling follow the behavior of that project so that results match the Draw Things app. The schemas themselves are not included in this repository.
