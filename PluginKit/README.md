# DTHubPluginKit

The package a DT Hub plug-in is written with. It does not depend on DT Hub: the app and a plug-in only talk through
Objective-C selectors and JSON messages (see `docs/superpowers/specs/2026-10-03-plugin-design.md`).

## Writing a plug-in

1. A Swift package with a **dynamic** library product that depends on `DTHubPluginKit` (copy `Examples/Sample`).
2. A class conforming to `DTHubPlugin` (`manifest`, `makeViewController()`, `start(host:)`, `handle(_:)`).
3. A subclass of `DTHubPluginEntry` with an Objective-C name, overriding `makePlugin()`:

        @objc(MyPluginEntry)
        public final class MyPluginEntry: DTHubPluginEntry {
          public override func makePlugin() -> any DTHubPlugin { MyPlugin() }
        }

4. `swift build`, then wrap the library into a bundle:

        Scripts/make-bundle.sh .build/out/Products/Debug/libMyPlugin.dylib MyPlugin.dthubplugin com.you.myplugin MyPlugin 1.0 MyPluginEntry

   The arguments are the library, the bundle to make, the identifier (it must equal `manifest.id`), the name, the
   version, the principal class and, optionally, the contract version (default 1).

The bundle is added in DT Hub › Preferences › Plug-ins.

## Messages (contract 1)

JSON objects with a `type`. App → plug-in: `context` (model, family, parameters, a temporary folder), `activate`,
`deactivate`. Plug-in → app: `notice` (`text`, `isError`). An unknown type gets `{"type":"unsupported"}`.
