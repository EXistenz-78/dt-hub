# DT Hub

App macOS che sostituisce l'interfaccia di Draw Things per preparare e lanciare le generazioni,
con un LLM locale (MLX) e plug-in (Prompt Master, Sphere Light Reference, …).

- Requisiti: macOS 26, Apple Silicon, Xcode 27, un server gRPC di Draw Things.
- Progetto: apri `DTHub.xcodeproj`. La logica sta in `Packages/` (`swift test` da lì).
- Design: `docs/superpowers/specs/`.

Licenza: GPL-3.0, vedi `LICENSE`.
