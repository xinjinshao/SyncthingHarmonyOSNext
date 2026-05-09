# SyncthingHarmonyOSNext Architecture

This document records the current API 20 architecture after the HarmonyOS Next migration cleanup.

## Goals

- Keep Syncthing protocol, indexing, discovery, TLS identity, block exchange, and conflict handling inside the upstream Go core.
- Rebuild the Android app workflow with HarmonyOS Next ArkTS UI and services.
- Use Harmony platform capabilities only at the app boundary: lifecycle, storage grants, background task, notification, WebView, and QR scanning.
- Keep ordinary HAP builds independent from the patched Go toolchain by checking in the required native/core artifacts.

## Source Architecture Constraints

| Constraint | Android source | HarmonyOS Next design |
|---|---|---|
| Long running sync | Foreground service plus notification | Continuous background task with system notification |
| Core lifecycle | Android native process/library wrapper | Harmony NAPI bridge to patched Go core |
| Control plane | Syncthing REST on localhost | Same REST API on `127.0.0.1:8384` |
| UI state | Activities/fragments observing service state | ArkUI pages observing service/rest/event state |
| Settings | SharedPreferences | `@kit.ArkData` preferences |
| Storage | Direct filesystem paths | App sandbox paths plus optional picker URI mirror |
| Device pairing | Manual ID and QR scan | Manual ID and ScanKit guarded by syscap |

## Runtime Architecture

```text
EntryAbility
  -> pages/Index.ets
  -> SyncthingService.initialize()
  -> SyncthingProcessManager.initialize()
  -> SyncthingService.startService()
  -> SyncthingNative.startSyncthing()
  -> libsyncthing_napi.so
  -> patched Go Syncthing core
  -> REST API on 127.0.0.1:8384
  -> ArkTS RestApi/EventProcessor/pages
```

ArkTS owns UI, lifecycle, app preferences, background task management, notification integration, storage mapping, and REST polling. The Go core owns all Syncthing protocol behavior.

## API 20 Baseline

The project targets HarmonyOS `6.0.0(20)`:

```json5
"targetSdkVersion": "6.0.0(20)",
"compatibleSdkVersion": "6.0.0(20)"
```

App source uses modern Kit imports:

| Area | API 20 import |
|---|---|
| File APIs | `@kit.CoreFileKit` |
| Network APIs | `@kit.NetworkKit` |
| Preferences | `@kit.ArkData` |
| Logging | `@kit.PerformanceAnalysisKit` |
| Ability/context/want agent | `@kit.AbilityKit` |
| Background tasks | `@kit.BackgroundTasksKit` |
| Notifications | `@kit.NotificationKit` |
| Battery and power state | `@kit.BasicServicesKit` |
| ScanKit | `@kit.ScanKit` |

There are no remaining `@ohos.*` imports in `entry/src/main/ets`.

## Native Core Integration

HarmonyOS Next cannot reuse the Android `libsyncthingnative.so` directly. This app packages a Harmony-compatible NAPI bridge and patched Syncthing core artifacts:

- `entry/src/main/cpp/syncthing_napi_bridge.cpp`
- `entry/src/main/libs/arm64-v8a/libsyncthingnative.a`
- `entry/src/main/resources/rawfile/syncthing_core`
- `entry/src/main/ets/native/SyncthingNative.ets`
- `entry/src/main/ets/types/libsyncthing_napi.d.ts`

`SyncthingProcessManager` prepares the app sandbox, local API key, log path, and Go core home directory. It starts the core through `SyncthingNative`, waits for REST health, and records diagnostics.

## Storage Architecture

The Go core scans normal filesystem paths under app storage:

```text
/data/storage/el2/base/files/<folder-id>
```

HarmonyOS picker APIs may return authorized URIs rather than stable POSIX-like paths. The current production-safe compromise is:

```text
Harmony selected folder URI
  <-> FolderLocationManager mapping
  <-> FolderMirrorService import/export
  <-> sandbox mirror path used by Syncthing core
```

This design is compatible with the current core but can duplicate storage. A true zero-copy design would require a Syncthing filesystem backend that can operate on Harmony URI/file APIs through ArkTS/NAPI.

## Background Sync Architecture

`BackgroundSyncManager` requests a continuous background task using `dataTransfer` and `multiDeviceConnection`. It uses the system-provided continuous-task notification and records diagnostics for enable, disable, heartbeat, task snapshot, cancel, suspend, and active callbacks.

All background task calls are guarded with `SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask`. Devices without this syscap keep foreground sync behavior and report a clear unsupported state.

## Optional Capability Guards

| Feature | Syscap / condition | Runtime behavior when unavailable |
|---|---|---|
| Continuous background sync | `SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask` | Disable background mode and keep diagnostics |
| QR scan pairing | `SystemCapability.Multimedia.Scan.ScanBarcode` | Disable/guard Scan button and keep manual input |
| System folder picker | `SystemCapability.FileManagement.UserFileService.FolderSelection` | Disable System Folder and use App Storage |
| Battery/power run conditions | `SystemCapability.PowerManager.BatteryManager.Core` and `SystemCapability.PowerManager.PowerManager.Core` | Skip unsupported checks and keep other run conditions active |

The API 20 compiler may still warn about these optional APIs. The warnings are accepted because the app needs those features on capable devices while degrading safely on unsupported device profiles.

## Current Verification

- API 20 HAP build passes with `scripts/build-hap-e.ps1`.
- Signed HAP installs on device `22N0223B15011897`.
- App starts at `pages/MainPage`.
- Go core starts and REST probe succeeds for status, connections, and config.
- A desktop Syncthing peer is visible as `Connected` in the Devices tab.
- Continuous background task starts on the test phone and reports `notificationId=300`, `continuousTaskId=323`.
