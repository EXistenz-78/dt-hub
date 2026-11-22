# ``DrawThingsVideoKit``

Turn Draw Things video generations into video files.

## Overview

A video model returns its frames as images and, for some models, an audio track.
``VideoProcessor`` collects them from `GenerationResult`s and encodes a video at the model's frame
rate with the audio muxed in. ``VideoAssembler`` does the encoding and can raise the frame rate
with ``FrameInterpolator`` and the resolution with ``SuperResolutionScaler``.

```swift
import DrawThingsClient
import DrawThingsQueue
import DrawThingsVideoKit

let processor = VideoProcessor(configuration: VideoProcessorConfiguration(
    autoAssemble: true,
    defaultVideoConfiguration: VideoConfiguration(outputURL: outputURL),
    configurationProvider: { jobID in
        VideoConfiguration(outputURL: videosFolder.appending(path: "\(jobID).mp4"))
    }
))
processor.connect(to: queue.results)   // or any AsyncSequence of GenerationResult

for await event in processor.events {
    if case .assemblyCompleted(_, let url) = event { print("Saved \(url)") }
}
```

Only video results are collected (`result.media.isVideo`); set
``VideoProcessorConfiguration/collectAllCompletedJobs`` to collect every result. The source frame
rate comes from `result.media.frameRate`, and the first audio track is muxed in unless the
configuration names its own audio. Automatic assemblies run one at a time, in order.

Without a queue, pass results in directly:

```swift
let result = try await service.generate(request)
processor.ingest(result)
```

Or assemble frames yourself:

```swift
let url = try await VideoAssembler().assemble(
    frames: VideoFrameCollection(cgImages: result.images),
    configuration: VideoConfiguration(outputURL: outputURL, sourceFrameRate: result.media.frameRate ?? 16)
)
```

### Frame rate and interpolation

Without interpolation the video plays at ``VideoConfiguration/sourceFrameRate``. With
``InterpolationMode/enabled(factor:)`` the frame count is multiplied and the video plays at
``VideoConfiguration/frameRate``; choose `sourceFrameRate × factor` to keep the duration.

Interpolation uses VTFrameProcessor's motion-aware interpolation where available (macOS 15.4+,
iOS 26+, not the simulator) and a Core Image cross-dissolve elsewhere. For 4× interpolation,
``InterpolationPassMode/multiPass`` runs two 2× passes, which can reduce artifacts in fast motion.

### Super resolution

``SuperResolutionMode/enabled(factor:)`` upscales frames before interpolation. It uses
VTSuperResolutionScaler on macOS 26+ and iOS 26+ (inputs up to 1920×1080; Apple's model is
downloaded on first use, see ``SuperResolutionScaler/modelStatus(forWidth:height:scaleFactor:)``
and ``SuperResolutionScaler/downloadModels(forWidth:height:scaleFactor:progress:)``) and Lanczos
scaling elsewhere.

### Saving frames

``VideoFrameCollection/save(to:format:jpegQuality:progress:)`` writes frames, audio and metadata to
a folder that ``VideoFrameCollection/load(from:loadImagesImmediately:progress:)`` reads back, so
the same frames can be re-encoded with different settings later.

### Sandboxed macOS apps

Writing videos to a folder the user picks needs the
`com.apple.security.files.user-selected.read-write` entitlement.

## Topics

### Processing results

- ``VideoProcessor``
- ``VideoProcessorConfiguration``
- ``VideoProcessorEvent``
- ``VideoConfigurationProvider``

### Encoding

- ``VideoAssembler``
- ``VideoConfiguration``
- ``VideoCodec``
- ``VideoQuality``
- ``VideoAssemblerError``

### Frames

- ``VideoFrameCollection``
- ``VideoFrame``
- ``VideoFrameMetadata``
- ``FrameFormat``
- ``VideoFrameCollectionError``

### Interpolation

- ``FrameInterpolator``
- ``InterpolationMode``
- ``InterpolationMethod``
- ``InterpolationPassMode``
- ``FrameInterpolatorError``

### Super resolution

- ``SuperResolutionScaler``
- ``SuperResolutionMode``
- ``SuperResolutionMethod``
- ``SuperResolutionModelStatus``
- ``SuperResolutionError``
