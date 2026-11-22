# Getting Started

Connect to a Draw Things server and generate your first image.

## Enable the server

In the Draw Things app, open the API server settings and enable the gRPC server (default port
7859), or run the standalone `gRPCServerCLI`. Note whether TLS and a shared secret are enabled,
and match them in ``ConnectionOptions``.

## Connect

```swift
let service = try DrawThingsService(address: "localhost:7859", options: ConnectionOptions(
    security: .tls(),          // .plaintext if the server has TLS off
    sharedSecret: nil
))
let reply = try await service.echo()
print(reply.files.count, "model files installed")
```

The default TLS policy accepts Draw Things' self-signed certificate on local networks and verifies
public servers. See ``TransportSecurity/CertificateVerification``.

## Generate

```swift
let configuration = DrawThingsConfiguration(
    width: 1024, height: 1024, steps: 8,
    model: "z_image_turbo_1.0_q8p.ckpt",
    sampler: .unipctrailing, guidanceScale: 1, shift: 3, resolutionDependentShift: false
)
let result = try await service.generate(GenerationRequest(prompt: "A red fox in fresh snow", configuration: configuration))
try ImageHelpers.saveImage(result.images[0], to: outputURL)
```

To show progress and previews, iterate ``DrawThingsService/stream(_:)`` instead:

```swift
for try await event in service.stream(request) {
    switch event {
    case .progress(let progress): progressBar.value = progress.fractionCompleted ?? 0
    case .preview(let preview): imageView.image = preview
    case .completed(let result): finish(result)
    default: break
    }
}
```

Leaving the loop, or cancelling its task, cancels the generation on the server.

## Inputs

Image-to-image and inpainting take `CGImage`s: ``GenerationRequest/image`` is the canvas and
``GenerationRequest/mask`` marks the area to regenerate with transparent pixels. Control hints
are built with ``HintBuilder``, and LoRAs and ControlNets are part of the configuration.

## Finish

```swift
await service.shutdown()
```
