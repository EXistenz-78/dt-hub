# Model Specifications

How the client tells a server about models it doesn't have built in.

## Overview

A Draw Things server needs each model's specification (its version, latent space and sampling
objective) to run it. Built-in models, including quantized variants, are known to every server. For
newer models, each request carries the specification in its `MetadataOverride`; without it the
server falls back to SD 1.x defaults and produces noise.

``ModelSpecStore`` resolves specifications in this order:

1. specs registered with ``ModelSpecStore/register(_:)``
2. the live Draw Things list, only when ``ModelSpecSource/bundledAndRemote(_:)`` is chosen
3. the snapshot bundled with the package, refreshed before each release
4. the specs the server reported in its echo reply (none when model browsing is off)

The request's override also includes specs for the refiner, any stage models and each LoRA. A
LoRA without a known spec gets a minimal one using the model's version, because the server skips
LoRAs it has no spec for.

To bypass the store, set ``GenerationRequest/override``.
