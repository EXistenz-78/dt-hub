# Patch to DrawThings-Swift 2.2.0

Upstream: https://github.com/euphoriacyberware-ai/DrawThings-Swift (MIT, see LICENSE), revision e1cef4ba (2.2.0).
Examples, Assets and skills are left out; the library code is as it was except for one field.

`GenerationConfiguration` gets `scheduler: int = 0`, a field appended after `solAttentionTau` (vtable offset 188), so
`DrawThingsConfiguration.scheduler` reaches the server. 0 is the sampler's own schedule, then 1 simple, 2 sgm_uniform,
3 normal, 4 karras, 5 exponential, 6 linear_quadratic, 7 beta. The Atelier fork of the Draw Things engine
(`ianiv/draw-things-community`, the server DT Hub ships) reads it per request; servers without it ignore the field.

Changed files: `Generated/config_generated.swift`, `Configuration/DrawThingsConfiguration.swift`,
`Configuration/DrawThingsConfiguration+FlatBuffer.swift`. Not added to the JSON coding.

## Ming-Image family (24 November 2026)

`ModelFamily.detect` maps `ming_image` (version string and file names) to `.zImage`. Ming-Image's final images are
4-channel ARGB tensors (its decoder is the transparent one); without a known family whose latent is not 4-channel the
client took them for an SDXL latent and drew them in wrong colours. Changed file: `Models/ModelFamily.swift`.
