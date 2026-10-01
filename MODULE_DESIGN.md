# SyncthingHarmonyOSNext Module Design

This document describes the current module layout and API 26 responsibilities.

## Common

| File | Responsibility | Key dependencies |
|---|---|---|
| `common/Logger.ets` | Unified hilog wrapper | `@kit.PerformanceAnalysisKit` |
| `common/ServiceLocator.ets` | Lightweight singleton registry | none |
| `common/EventBus.ets` | In-process typed event dispatch | app types |
| `common/Utils.ets` | Formatting, base64, retry helpers | `@kit.ArkTS` |

## Data

| File | Responsibility | Key dependencies |
|---|---|---|
| `data/PreferencesManager.ets` | App preference persistence and typed settings access | `@kit.ArkData` |

## Network

| File | Responsibility | Key dependencies |
|---|---|---|
| `network/ApiRequest.ets` | HTTP helper for Syncthing REST requests | `@kit.NetworkKit` |
| `network/RestApi.ets` | Syncthing REST facade for config, status, db, events, logs, stats | `ApiRequest`, models |
| `network/SyncthingTrustManager.ets` | Trust handling placeholder for local Syncthing TLS work | certificate APIs |

## Native Bridge

| File | Responsibility |
|---|---|
| `native/SyncthingNative.ets` | Typed ArkTS wrapper around `libsyncthing_napi.so` |
| `types/libsyncthing_napi.d.ts` | NAPI declaration for ArkTS compilation |
| `cpp/syncthing_napi_bridge.cpp` | C++ NAPI bridge into the patched Go core |
| `cpp/syncthing_core_bridge.cpp` | Native helper layer for bundled core startup |
| `cpp/CMakeLists.txt` | Builds native bridge and packages required artifacts |

## Services

| File | Responsibility | Notes |
|---|---|---|
| `service/Constants.ets` | Preference keys, REST constants, paths, defaults | Ported from Android concepts |
| `service/SyncthingService.ets` | Top-level runtime owner | Starts core, polling, events, and run conditions |
| `service/SyncthingProcessManager.ets` | Go core lifecycle | Starts NAPI core, waits for REST health, handles async core file installation |
| `service/EventProcessor.ets` | Syncthing event polling | Polls `/rest/events` and emits app events |
| `service/RunConditionMonitor.ets` | Run-condition evaluation | Uses `@kit.NetworkKit` and `@kit.BasicServicesKit`; network, power source, and battery saver checks are syscap guarded |
| `service/BackgroundSyncManager.ets` | Continuous background task wrapper | Guards background APIs by syscap and records diagnostics |
| `service/NotificationManager.ets` | App info/error notifications | System continuous-task notification is preferred for background sync |
| `service/BackgroundDiagnostics.ets` | Diagnostic event log | Uses `@kit.CoreFileKit` |

## File Sync Limitation

The current product uses app-sandbox POSIX sync with an API 26 donated Shared root for new folders. Existing private paths remain unchanged. Sandbox Files now includes user-confirmed Gallery export. A public-directory picker with persistent grant checks is now available for new folders; automatic mirror modules remain absent.

| Requirement | Status | Blocking point |
|---|---|---|
| Sync `/data/storage/el2/base/files/Shared/<folder-id>` | Implemented | Native Syncthing path inside the API 26 donated root |
| Sync a user-selected public directory | Implemented for testing; runtime acceptance pending | Persist/check/activate the picker URI and pass its native path to the core |
| Sync a real Gallery directory tree | Not implemented | `photoAccessHelper` exposes albums/assets, not nested directory creation |
| Same-file access through File Manager | Donation configured; user reports no File Manager visibility | System reads the donated sandbox directory |

### Removed Prototype Modules

The following prototype modules were removed because they did not satisfy the real directory-tree requirement:

| Removed module | Previous role | Removal reason |
|---|---|---|
| `FolderLocationManager.ets` | Stored external URI to sandbox path mappings | Mapping enabled mirror behavior only |
| `FolderMirrorService.ets` | Recursive import/export between URI folders and sandbox paths | Duplicated storage and could not create a real Gallery tree |
| `FolderMirrorScheduler.ets` | Periodically ran mirror passes while the core was active | Depended on removed mirror service |

Folder UI defaults to Shared and offers Choose Public Folder for new folders. Persistent authorization must succeed; existing folders are not moved.

## Pages

| File | Responsibility |
|---|---|
| `pages/Index.ets` | Startup/loading and first-run routing |
| `pages/FirstStartPage.ets` | First-run wizard |
| `pages/MainPage.ets` | Main tab shell for Devices, Folders, Status |
| `pages/DeviceListPage.ets` | Tab child component listing configured remote devices |
| `pages/FolderListPage.ets` | Tab child component listing configured folders and status |
| `pages/StatusPage.ets` | Core health, local ID, connections, pending items, logs, feature status |
| `pages/DeviceDetailPage.ets` | Add/edit device, QR scan pairing, folder sharing |
| `pages/FolderDetailPage.ets` | Add/edit folder, path selection, sharing, versioning, rescan |
| `pages/SettingsPage.ets` | App settings and Syncthing options |
| `pages/SyncConditionsPage.ets` | Background sync and run-condition controls |
| `pages/SandboxViewPage.ets` | Sandbox file viewer and user-confirmed Gallery copies |
| `pages/WebGuiPage.ets` | Embedded Syncthing Web GUI |
| `pages/RecentChangesPage.ets` | Recent file changes from events |
| `pages/LogPage.ets` | Syncthing/system log view |

`DeviceListPage` and `FolderListPage` are not route pages. They are exported child components used by `MainPage`, so they are intentionally removed from `main_pages.json` and do not carry `@Entry`.

## Route Pages

`entry/src/main/resources/base/profile/main_pages.json` contains only pages that are directly navigated to by router:

- `pages/Index`
- `pages/MainPage`
- `pages/FirstStartPage`
- `pages/SandboxViewPage`
- `pages/SyncConditionsPage`
- `pages/DeviceDetailPage`
- `pages/FolderDetailPage`
- `pages/SettingsPage`
- `pages/WebGuiPage`
- `pages/RecentChangesPage`
- `pages/LogPage`

## SDK Compatibility Rules

- App source uses `@kit.*` imports instead of legacy `@ohos.*` imports.
- Optional features are guarded by `canIUse()` before user-visible actions and before runtime calls.
- `throw err` is avoided because ArkTS API 20 restricts throwing arbitrary values; errors are wrapped in `new Error(...)`.
- File operations that may fail are kept out of page render paths and handled with explicit error reporting.
- Large synchronous file work should stay out of page render paths; new writes in `SyncthingProcessManager` use async file APIs.

## Feature Coverage

| Area | Status |
|---|---|
| Core startup through NAPI | Implemented |
| REST status/config/connections/events | Implemented |
| Device list/detail/add/delete/share | Implemented |
| QR device pairing | Implemented, syscap guarded |
| Folder list/detail/add/delete/share/rescan | Implemented |
| App sandbox folder sync | Implemented |
| API 26 Shared storage | Donation configured and core scanning verified; File Manager visibility failed on the test phone |
| Sandbox viewer | Implemented |
| Web GUI/logs/recent changes | Implemented |
| Background sync | Implemented on devices with continuous-task syscap |
| Network run condition | Implemented |
| Battery/power run conditions | Implemented, syscap guarded |

## Validation Baseline

| Check | Status |
|---|---|
| API 26 HAP build | Verified on the migrated Windows environment |
| No `@ohos.*` imports in app source | Passed |
| HAP install on test phone | Passed |
| App starts at `pages/MainPage` | Passed |
| Go core starts | Passed |
| REST status/connections/config probe | Passed |
| Desktop peer shown connected | Passed |
| Continuous background task on test phone | Passed |

## API 26 storage update

New sync folders now use the donated Shared root. Existing folders keep their paths. Sandbox Files supports user-confirmed Gallery copies; automatic Gallery indexing and two-way media synchronization are not established. Earlier API 20 storage restrictions describe the previous baseline. See STORAGE_VALIDATION.md for current implementation and device evidence.

Latest runtime results: unlocked app launch/REST health and Shared access pass; File Manager donation visibility fails user acceptance; Download/Photos selection completes but persistent access is rejected with 13900001 / PERSISTENCE_FORBIDDEN. Manual Gallery export remains unverified. Consumer-integration evidence and registration uncertainties are recorded in DONATION_REPRO.md. These notes concern the local API 26 working copy; its code changes are outside this documentation-only publication.
