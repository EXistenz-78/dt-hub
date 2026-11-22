# Configuration JSON

Read and write the configuration JSON the Draw Things app copies and pastes.

## Overview

``DrawThingsConfiguration`` is `Codable` in Draw Things' own format:

```swift
let configuration = try DrawThingsConfiguration.fromJSON(json)
let json = try configuration.toJSON()
```

The app produces two shapes of this JSON:

- **Copy Configuration** writes a compact subset, the settings relevant to the current model.
  Pasting it into the app only changes those settings, so treat it as an overlay and apply it with
  ``DrawThingsConfiguration/mergeJSON(_:)`` on a base configuration.
- **Complete exports** contain every key. ``DrawThingsConfiguration/toJSON(includeSeed:)`` writes
  this shape, so its output reproduces the whole configuration when pasted into the app.

``DrawThingsConfiguration/fromJSON(_:)`` accepts both; keys that are missing take the
configuration's defaults.

## Values

Sizes are in pixels. A negative `seed` means random (``DrawThingsConfiguration/seed`` is `nil`).
LoRA modes, control importance, compression and color calibration are strings (`"all"`,
`"balanced"`, `"h264"`, `"none"`...), and samplers and seed modes are integers. Names such as
`upscaler` use `""` or `null` for "none".

## Validation

``DrawThingsConfiguration/validateJSON(_:)`` parses and validates text, returning a readable
error for the first problem, which suits configuration editors. ``DrawThingsConfiguration/validate()``
checks a configuration directly.
