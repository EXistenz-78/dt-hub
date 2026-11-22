# ``DrawThingsClient``

Generate images, video and audio with a Draw Things gRPC server.

## Overview

DrawThingsClient speaks the Draw Things gRPC protocol. Create a ``DrawThingsService`` for a
server, describe a generation with a ``GenerationRequest``, and either stream its
``GenerationEvent``s or await the ``GenerationResult``:

```swift
let service = try DrawThingsService(address: "localhost:7859")
let request = GenerationRequest(
    prompt: "A lighthouse on a rocky coast at sunset",
    configuration: DrawThingsConfiguration(
        width: 1024, height: 1024, steps: 8, model: "z_image_turbo_1.0_q8p.ckpt",
        sampler: .unipctrailing, guidanceScale: 1, shift: 3, resolutionDependentShift: false
    )
)
for try await event in service.stream(request) {
    if case .completed(let result) = event { save(result.images) }
}
```

For SwiftUI, ``DrawThingsSession`` mirrors the service's events into observable properties. The
library itself contains no views; see <doc:BuildingAUserInterface>.

The package's other products build on this one: DrawThingsQueue (`GenerationQueue`, many requests
in order), DrawThingsVideoKit (`VideoProcessor`, video results to video files) and DrawThingsKit
(saved servers, the model catalog and configuration state for apps).

## Topics

### Essentials

- <doc:GettingStarted>
- ``DrawThingsService``
- ``GenerationRequest``
- ``GenerationEvent``
- ``GenerationResult``

### SwiftUI

- <doc:BuildingAUserInterface>
- ``DrawThingsSession``

### Connecting

- ``ServerEndpoint``
- ``ConnectionOptions``
- ``TransportSecurity``
- ``ClientIdentity``

### Configuration

- <doc:ConfigurationJSON>
- ``DrawThingsConfiguration``
- ``LoRAConfig``
- ``ControlConfig``
- ``HintBuilder``
- ``HintType``

### Progress and media

- ``GenerationProgress``
- ``GenerationStage``
- ``RemoteDownloadProgress``
- ``MediaProfile``
- ``GeneratedAudio``
- ``ModelFamily``

### Model specifications

- <doc:ModelSpecifications>
- ``ModelSpecStore``
- ``ModelSpec``
- ``ModelSpecSource``

### Images and tensors

- ``ImageHelpers``
- ``AudioHelpers``

### Errors

- ``DrawThingsError``
- ``ServerEndpointError``
- ``HintBuildError``
- ``ImageError``

### Logging

- ``DTLogger``
- ``DTLogLevel``
- ``DTLogCategory``
