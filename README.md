# DT Hub

App macOS che sostituisce l'interfaccia di Draw Things per preparare e lanciare le generazioni,
con un LLM locale (MLX) e plug-in (Prompt Master, Sphere Light Reference, …).

- Requisiti: macOS 26, Apple Silicon, Xcode 27, un server gRPC di Draw Things (l'app o `gRPCServerCLI`, che DT Hub può avviare da solo).
- Per compilare serve il componente Xcode Metal Toolchain (i shader di MLX): `xcodebuild -downloadComponent MetalToolchain`, una volta sola.
- Per l'LLM serve un modello MLX in una cartella (per esempio `mlx-community/Qwen3-VL-8B-Instruct-4bit`): si scarica dalle Preferenze › LLM, solo se lo chiedi.
- Progetto: apri `DTHub.xcodeproj`. La logica sta in `Packages/` (`swift test` da lì).
- Design: `docs/superpowers/specs/`.

Licenza: GPL-3.0, vedi `LICENSE`.
