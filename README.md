# Syncthing HarmonyOS Next

Syncthing HarmonyOS Next is a HarmonyOS Next client that embeds the Syncthing core and brings the Android app workflow to Harmony phones and tablets. This repository is prepared as a 1.0 migration baseline: pairing, status, device management, folder management, the Web GUI, logs, recent changes, and continuous background sync are wired to the embedded core, while platform-specific storage constraints are documented clearly below.

## Upstream References

- Syncthing core: [github.com/syncthing/syncthing](https://github.com/syncthing/syncthing)
- Syncthing Android app: [github.com/syncthing/syncthing-android](https://github.com/syncthing/syncthing-android)
- HarmonyOS app development guide: [HarmonyOS Application Development Guide](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/application-dev-guide)

## Architecture

The Android project depends on an Android-specific `libsyncthingnative.so`. HarmonyOS Next cannot reuse that artifact directly, so this project uses a Harmony NAPI bridge and bundled native/core artifacts:

- ArkTS UI and services manage lifecycle, settings, background tasks, and page routing.
- `SyncthingProcessManager` prepares the app sandbox, API key, configuration, and core home directory.
- `SyncthingNative` calls the Harmony NAPI module that starts the patched Syncthing Go core.
- `RestApi` talks to the embedded core through `127.0.0.1:8384` with Syncthing's local REST API.
- `BackgroundSyncManager` requests HarmonyOS continuous background running with `dataTransfer` and `multiDeviceConnection` modes, using the system-provided background notification.
- Folder storage uses sandbox paths for the Go core and a mirror/import/export layer for Harmony picker URIs.

The repository intentionally tracks the patched prebuilt artifacts under `entry/src/main/libs/` and `entry/src/main/resources/rawfile/`. These are part of the release source because a stock upstream Android `.so` cannot be built or reused as-is on HarmonyOS Next. The Harmony-compatible build includes native bridge and Go runtime adaptations, including TLS/runtime handling needed by the embedded Syncthing core on this platform.

## Core Call Flow

```text
EntryAbility
  -> pages/Index.ets
  -> SyncthingService.initialize()
  -> SyncthingProcessManager.initialize()
  -> RestApi.initialize()
  -> SyncthingService.startService()
  -> SyncthingProcessManager.start()
  -> SyncthingNative.getVersion()/startSyncthing()
  -> libsyncthing_napi.so
  -> libsyncthing_core_bridge.so
  -> Go exported Start(homeDir, logFile, guiAddress, apiKey)
  -> Syncthing core starts REST on 127.0.0.1:8384
  -> ArkTS pages consume status/config/events through RestApi
```

The app keeps the Android architecture boundary: ArkTS owns UI, lifecycle, settings, and Harmony platform integration; Syncthing's Go core owns discovery, TLS identity, BEP, indexing, block exchange, conflict handling, and sync semantics. Reimplementing the protocol in ArkTS is intentionally out of scope for this 1.0 baseline.

## Native Core Notes

The embedded core has been validated on a HarmonyOS Next phone. The important migration fixes are:

- Harmony-loadable Go runtime TLS behavior for the Go-backed native artifact.
- A c-archive startup path that is safe when loaded from Harmony NAPI.
- A minimal app runtime environment for the Go core before Syncthing package initialization.
- Defensive fixes for Harmony cgo thread startup and relay nil-state handling observed during real-device testing.

Validated runtime behavior includes NAPI registration, bridge loading, Go `Start` entry, local REST health, `127.0.0.1:8384` Web GUI/API listener, `:22000` sync listener, and UDP local discovery sockets.

## Feature Status

Implemented and wired to the embedded core:

- First start flow and main tab shell.
- Status page with local device ID, connection status, pending devices/folders, discovery errors, and recent logs.
- Add/edit/delete devices, QR scan device ID pairing, dynamic addresses, introducer, auto-accept, compression, pause, untrusted, and folder sharing.
- Add/edit/delete folders, folder type, watch changes, ignore permissions, pause, pull order, versioning options, rescan, and per-folder status.
- Folder sharing between the phone core and a desktop Syncthing peer.
- Web GUI, logs, and recent changes views.
- Sync condition settings, network-state monitoring, background sync toggle, background diagnostics, and system continuous-task notification integration.
- Sandbox file viewer for checking files accessible to the embedded core.

Partial or platform-limited:

- Public folder sync is constrained by HarmonyOS storage. Syncthing's Go core expects normal POSIX paths, while Harmony picker APIs often return authorized URIs. The current design maps selected external folders to sandbox mirror paths and provides import/export passes. This can use additional storage because files may exist once in the public folder and once in the app sandbox mirror.
- True bidirectional public-folder sync without duplication would require a deeper filesystem abstraction or a supported platform API that exposes stable POSIX-like access to the selected directory. This project does not replace Syncthing's full filesystem layer.
- Battery, power, and other system run-condition gates are represented in UI but remain guarded until the corresponding HarmonyOS APIs are connected and validated on target devices.
- Android share extension, camera/photo shoot workflow, and quick settings tile equivalents are not complete.

Android migration status:

| Android surface | HarmonyOS Next status |
|---|---|
| Main tabs, status, devices, folders | Implemented |
| Add/edit devices and QR pairing | Implemented |
| Add/edit folders, sharing, rescan, versioning, pull order | Implemented |
| Settings, Web GUI, logs, recent changes | Implemented |
| Run conditions and background sync | Partially implemented; network/background paths are active, several power/battery gates remain platform-gated |
| Folder picker/public folder sync | Partially implemented through sandbox mirror import/export |
| Share extension, camera/photo shoot, quick settings tiles | Not implemented |

## Filesystem Model

HarmonyOS Next protects app data and user files differently from Android. The embedded Syncthing core can reliably scan and write paths under the app sandbox, for example:

```text
/data/storage/el2/base/files/<folder-id>
```

When the user selects a system folder, the app stores the external URI separately and gives Syncthing a sandbox mirror path. Manual and scheduled mirror workers then import files into the sandbox and export files back when the platform accepts the target URI operation. This is the safest current compromise, but it is not the same as direct shared-folder access and may temporarily duplicate storage.

## Build

The normal HAP build does not rebuild the Syncthing Go core. The repository already includes the required native/core artifacts:

- `entry/src/main/libs/arm64-v8a/libsyncthingnative.a`
- `entry/src/main/libs/arm64-v8a/libsyncthingnative.h`
- `entry/src/main/resources/rawfile/syncthing_core`

That means other developers should be able to build the HAP with DevEco Studio or a correctly configured HarmonyOS command-line build environment, without installing the patched Go toolchain. They still need the usual HarmonyOS Next dependencies such as DevEco Studio, Node.js, Hvigor, and the matching HarmonyOS SDK/API level.

The checked-in E-drive scripts are maintainer-local convenience scripts. They keep Go, SDK, cache, and temp usage on the E drive to avoid filling the C drive on the original development machine:

```powershell
cd E:\Programming\SyncthingHarmonyOSNext
.\scripts\build-hap-e.ps1
```

These scripts may not run unchanged on another machine because they reference local toolchain paths. Developers who only want to build the app should use DevEco Studio or adapt the command-line build path to their own SDK installation.

Expected output:

- Signed HAP: `entry/build/default/outputs/default/entry-default-signed.hap`
- Native NAPI library produced by the Harmony build.
- Bundled core/native artifacts retained from `entry/src/main/libs/` and `entry/src/main/resources/rawfile/`.

Rebuilding the Go core is optional and advanced. It currently requires the patched Go/toolchain setup used for HarmonyOS Next native loading and is not required for ordinary HAP builds. Only maintainers changing the embedded Syncthing core or native bridge should run `scripts/build-go-core-archive-e.ps1`.

## Validation

The current validation baseline is:

- ArkTS/HAP build succeeds with API 21 configuration.
- The signed HAP installs and starts on a HarmonyOS Next phone.
- Embedded Syncthing core starts, exposes `127.0.0.1:8384`, and reports local device ID through REST.
- A desktop Syncthing instance and the phone instance can add each other and show an active LAN connection.
- Folder creation, sharing, scan, and status rendering are validated through the app UI and REST polling.
- Continuous background task creation and heartbeat diagnostics are visible in hilog when background sync is enabled.

## Repository Contents

- `entry/src/main/ets/`: ArkTS UI, services, REST client, and native wrapper.
- `entry/src/main/cpp/`: Harmony NAPI bridge source.
- `entry/src/main/libs/`: required prebuilt native artifacts for the embedded core bridge.
- `entry/src/main/resources/rawfile/`: bundled Syncthing core artifact used by the app at runtime.
- `scripts/`: E-drive build, install, and validation helpers.
- `ARCHITECTURE.md`, `MODULE_DESIGN.md`: detailed architecture and module design notes.

## License

This project is a HarmonyOS Next migration effort built around Syncthing. Keep upstream Syncthing and Syncthing Android license obligations intact when redistributing source or binaries.
