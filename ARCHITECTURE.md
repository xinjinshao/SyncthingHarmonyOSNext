# SyncthingHarmonyOSNext Architecture

This document records the current API 26 architecture after the HarmonyOS Next migration cleanup.

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
| Storage | Direct filesystem paths | App sandbox paths only |
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

ArkTS owns UI, lifecycle, app preferences, background task management, notification integration, app-sandbox path preparation, and REST polling. The Go core owns all Syncthing protocol behavior.

## API 26 Baseline

The project targets HarmonyOS `26.0.0`:

```json5
"targetSdkVersion": "26.0.0",
"compatibleSdkVersion": "26.0.0"
```

App source uses modern Kit imports:

| Area | SDK import |
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

The Go core scans ordinary POSIX paths. New folders use `/data/storage/el2/base/files/Shared/<folder-id>`. Only Shared is donated through the API 26 `module.shareFiles` profile with read/write access. Private configuration, TLS keys, databases and logs remain outside Shared. Existing folder paths are preserved.

Directory donation supports system File Manager/FilePicker on phone/tablet. Configuration compiles and Shared indexing passes on the test phone; the user reports no File Manager visibility on this phone. It does not establish automatic Gallery indexing or nested albums.

Sandbox Files offers user-confirmed Save to Gallery, using `photoAccessHelper.showAssetsCreationDialog` and descriptor-based copying to the returned URI. Exported assets are separate copies and do not follow source edits/deletions. Runtime dialog and Gallery appearance verification are pending. No broad media read permission, URI-backed Go filesystem, automatic media mirror, or folder migration is introduced.

The earlier API 20 experiments did not provide usable public directory access. API 26 donation supersedes that conclusion for app-owned Shared storage. New folders may use the public-directory picker with persist/check/activate authorization through PublicFolderAccess. This branch and automatic two-way Gallery sync remain unvalidated. See STORAGE_VALIDATION.md for exact evidence and pending checks.

## Background Sync Architecture

`BackgroundSyncManager` requests a continuous background task using `dataTransfer` and `multiDeviceConnection`. It uses the system-provided continuous-task notification and records diagnostics for enable, disable, heartbeat, task snapshot, cancel, suspend, and active callbacks.

All background task calls are guarded with `SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask`. Devices without this syscap keep foreground sync behavior and report a clear unsupported state.

## Optional Capability Guards

| Feature | Syscap / condition | Runtime behavior when unavailable |
|---|---|---|
| Continuous background sync | `SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask` | Disable background mode and keep diagnostics |
| QR scan pairing | `SystemCapability.Multimedia.Scan.ScanBarcode` | Disable/guard Scan button and keep manual input |
| Public/system folder sync | FolderSelection and FolderAuthorization, then persistent grant verification | Keep the current path if selection or authorization fails; Download/Photos persistence failed on the test phone |
| Battery/power run conditions | `SystemCapability.PowerManager.BatteryManager.Core` and `SystemCapability.PowerManager.PowerManager.Core` | Skip unsupported checks and keep other run conditions active |

The compiler may still warn about these optional APIs. The warnings are accepted because the app needs those features on capable devices while degrading safely on unsupported device profiles.

## Current Verification

- API 26 HAP build is verified with `scripts/build-hap.ps1`.
- Signed HAP installs on the test phone.
- App starts at `pages/MainPage`.
- Go core starts and REST probe succeeds for status, connections, and config.
- A desktop Syncthing peer is visible as `Connected` in the Devices tab.
- Continuous background task starts on the test phone and reports `notificationId=300`, `continuousTaskId=323`.

## API 26 storage update

New sync folders now use the donated Shared root. Existing folders keep their paths. Sandbox Files supports user-confirmed Gallery copies; automatic Gallery indexing and two-way media synchronization are not established. Earlier API 20 storage restrictions describe the previous baseline. See STORAGE_VALIDATION.md for current implementation and device evidence.

Latest unlocked validation passes app launch, REST health and Shared readability. Donation visibility remains unsuccessful. Shared-scope map registration and donation database registration are separate system flows; AddToShareMap is not proof of donation registration. The device contains donation-related implementation, while File Manager consumer integration remains under investigation. These implementation/validation notes describe the local API 26 working copy; this documentation-only publication does not publish its pending code changes. See DONATION_REPRO.md.
