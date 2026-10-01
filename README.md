# Syncthing HarmonyOS Next

Syncthing HarmonyOS Next is a HarmonyOS Next client that embeds the Syncthing core and brings the Android app workflow to Harmony phones and tablets. This repository is prepared as a 1.0 migration baseline: pairing, status, device management, folder management, the Web GUI, logs, recent changes, and continuous background sync are wired to the embedded core, while platform-specific storage constraints are documented clearly below.

Documentation update (2026-10-01): API 26 environment/storage implementation and test results below describe the local development working copy. This documentation-only commit does not include the pending implementation changes; the committed build configuration may still use the earlier API baseline.

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
- Folder storage uses native sandbox paths. New folders are created under the API 26 donated Shared directory for system file management; visibility has not succeeded on the current test phone.

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
- Sync condition settings, network/power-state monitoring, run-condition driven pause/resume, background sync toggle, background diagnostics, and system continuous-task notification integration.
- Sandbox file viewer for checking files accessible to the embedded core.

Partial or platform-limited:

- New sync folders use `/data/storage/el2/base/files/Shared/<folder-id>`. This directory is donated to system file management on API 26 phone/tablet devices. Existing folder paths remain unchanged. Gallery automatic indexing is being verified separately.
- New folders can optionally use Choose Public Folder with checked persistent URI authorization and native path access; this branch awaits runtime acceptance. The donated directory is still native sandbox storage. Sandbox Files provides a user-confirmed Save to Gallery action for supported images/videos; it creates an independent media-library copy, not bidirectional Gallery sync.
- Roaming, SSID whitelist, master sync, flight mode, and other Android-specific run-condition gates remain disabled until equivalent HarmonyOS signals are validated on target devices.
- Android share extension, camera/photo shoot workflow, and quick settings tile equivalents are not complete.

Android migration status:

| Android surface | HarmonyOS Next status |
|---|---|
| Main tabs, status, devices, folders | Implemented |
| Add/edit devices and QR pairing | Implemented |
| Add/edit folders, sharing, rescan, versioning, pull order | Implemented |
| Settings, Web GUI, logs, recent changes | Implemented |
| Run conditions and background sync | Partially implemented; Wi-Fi/mobile-data, metered Wi-Fi, power source, battery saver, timed schedule, force start/stop, and continuous background task control are active; roaming, SSID whitelist, master sync, and flight mode remain platform-gated |
| System file management | API 26 donated Shared directory configured; not visible on the current test phone; public-directory picker added for separate testing |
| Gallery | User-confirmed media export implemented; automatic donated-directory indexing and export runtime verification pending |
| Share extension, camera/photo shoot, quick settings tiles | Not implemented |

## Filesystem Model

API 26 supports donating an application sandbox directory to system applications on phone/tablet devices. The app configures `module.shareFiles` with `resources/base/profile/share_files.json`. Only `/el2/base/files/Shared` is eligible for sharing and donation with read/write access. A parent-scope/explicit-subpath control also failed to appear on the test phone and was reverted. Syncthing configuration, TLS keys, databases and logs remain outside that root.

New folders use `/data/storage/el2/base/files/Shared/<folder-id>`. The Go core still scans ordinary POSIX paths; no filesystem backend rewrite or mirror storage is introduced. Existing folders are not moved automatically because changing a folder path can trigger rescans and affect synchronization state. Their original private paths remain functional.

The official [application shared-directory guide](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/share-app-file-configuration) documents access by File Manager and FilePicker. It does not establish Gallery automatic indexing or a directory-to-album mapping. Those behaviors must be verified on the target device.

Sandbox Files provides **Save to Gallery** for JPG/JPEG/PNG/WebP/HEIC images and MP4/MOV videos. It uses `photoAccessHelper.showAssetsCreationDialog`, then writes to the returned media URI after user confirmation. No broad photo-library read permission is requested. The saved asset is an independent copy: later Syncthing edits/deletions do not update/delete it, and repeated exports may create duplicates. This action does not preserve a nested directory tree as Gallery albums.

Latest device validation (2026-10-01): signed HAP installation, unlocked launch and REST health pass; Shared is readable, test PNG round-trip hashes match, and Syncthing indexes Shared with zero scan errors. File Manager does not show Syncthing or an application-files entry, and Gallery does not automatically show the test image. Download/Photos selection returns a URI, but persistent authorization fails with 13900001 / PERSISTENCE_FORBIDDEN. Manual Gallery export remains unverified.

The device Sandbox Manager binary contains donation parser/database/query markers. File Manager refresh logs contain no donation-list query in the captured launch, and its permission dump lacks ACCESS_SHARED_FILE, which current public source requires for system consumers. Consumer integration is the leading hypothesis; donation database registration remains unverified. These observations do not establish a firmware defect. See [STORAGE_VALIDATION.md](STORAGE_VALIDATION.md) and [DONATION_REPRO.md](DONATION_REPRO.md) for evidence and limitations.

The earlier API 20 rejection of sandbox exposure is superseded by API 26 directory donation. Arbitrary public folders and automatic two-way Gallery synchronization remain outside the validated implementation.

## Build

The normal HAP build does not rebuild the Syncthing Go core. The repository already includes the required native/core artifacts:

- `entry/src/main/libs/arm64-v8a/libsyncthingnative.a`
- `entry/src/main/libs/arm64-v8a/libsyncthingnative.h`
- `entry/src/main/resources/rawfile/syncthing_core`

That means other developers should be able to build the HAP with DevEco Studio or a correctly configured HarmonyOS command-line build environment, without installing the patched Go toolchain. They still need the usual HarmonyOS Next dependencies such as DevEco Studio, Node.js, Hvigor, and the matching HarmonyOS SDK/API level. The current app baseline targets HarmonyOS API 26:

```json5
"targetSdkVersion": "26.0.0",
"compatibleSdkVersion": "26.0.0"
```

The PowerShell helpers discover DevEco Studio in its standard Windows installation directory (or `DEVECO_STUDIO_HOME`) and use its bundled Node, Java, OHPM, Hvigor and SDK. Standard user cache and temporary directories are retained; no D/E drive is required.

```powershell
.\scripts\build-hap.ps1 -Clean
.\scripts\build-hap.ps1 -BuildMode release -Clean
.\scripts\verify-hap.ps1
```

Override `DEVECO_SDK_HOME` when using a separately installed SDK. The old `*-e.ps1` names remain compatibility entry points.

The repository has no default signing material. Without a local signing configuration, the output is `entry/build/default/outputs/default/entry-default-unsigned.hap`. For installation, configure automatic signing in DevEco Studio using your Huawei developer account and the connected device, or migrate valid certificates, provisioning profile and keystore from the previous computer. Do not commit signing credentials.

The project requires API 26 for the planned FileShare integration. Both the target and minimum compatible API are 26; API 20 devices are no longer in the supported build baseline. The October 2026 environment check uses the bundled HarmonyOS 26.0.0 SDK. FileShare business functionality is not implemented by this environment change.

Rebuilding the Go core is optional and advanced, and requires the patched HarmonyOS Go runtime plus patched Syncthing source. Ordinary HAP builds use the checked-in artifacts and do not require Go. Maintainers may use `scripts/build-go-core-archive.ps1 -SyncthingRoot <source-path>` with the patched Go toolchain on PATH. The Python shared-library builder is a separate legacy path, not the validated c-archive build.

## Validation

The current validation baseline is:

- ArkTS/HAP build succeeds with API 26 configuration.
- The signed HAP installs and starts on a HarmonyOS Next phone.
- Embedded Syncthing core starts, exposes `127.0.0.1:8384`, and reports local device ID through REST.
- A desktop Syncthing instance and the phone instance can add each other and show an active LAN connection.
- Folder creation, sharing, scan, and status rendering are validated through the app UI and REST polling.
- Continuous background task creation, heartbeat diagnostics, run-condition decisions, and Syncthing pause/resume actions are visible in hilog when background sync is enabled.

The compatibility cleanup keeps app source imports on the modern `@kit.*` path. Optional device capabilities such as continuous background tasks, ScanKit QR scanning, and folder picker access are guarded with runtime syscap checks. The build can still emit static syscap warnings for those optional APIs because the features remain compiled in and degrade safely at runtime when the device profile does not expose them. The NAPI bridge warning for `libsyncthing_napi.so` is expected with the current SDK; the module has a checked-in `.d.ts` declaration.

## Repository Contents

- `entry/src/main/ets/`: ArkTS UI, services, REST client, and native wrapper.
- `entry/src/main/cpp/`: Harmony NAPI bridge source.
- `entry/src/main/libs/`: required prebuilt native artifacts for the embedded core bridge.
- `entry/src/main/resources/rawfile/`: bundled Syncthing core artifact used by the app at runtime.
- `scripts/`: portable Windows build and validation helpers.
- `ARCHITECTURE.md`, `MODULE_DESIGN.md`: detailed architecture and module design notes.

## License

This project is a HarmonyOS Next migration effort built around Syncthing. Keep upstream Syncthing and Syncthing Android license obligations intact when redistributing source or binaries.

The reference project [Syncthing-for-HarmonyOS](https://github.com/forwardz666/Syncthing-for-HarmonyOS) validates public Download access on tablet devices, not directory donation or Gallery sync. This phone reports no FolderObtain capability (Environment returns 801), but supports FolderSelection. Choose Public Folder uses the latter and checks persistent authorization before accepting a path.
