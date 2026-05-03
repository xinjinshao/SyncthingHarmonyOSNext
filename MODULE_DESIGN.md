# SyncthingHarmonyOSNext — Module Design Document

## Module Inventory

### 1. Common Module (`common/`)
| File | Type | Description | Dependencies |
|---|---|---|---|
| `Logger.ets` | Utility | Unified logging via @ohos.hilog | `@kit.PerformanceAnalysisKit` |
| `ServiceLocator.ets` | DI Container | Simple singleton service registry | None |
| `EventBus.ets` | Event System | Emitter-based event bus with typed event names | `@kit.BasicServicesKit` |
| `Utils.ets` | Utility | Format functions, base64, retry logic | `@kit.ArkTS` |

### 2. Data Module (`data/`)
| File | Type | Description | Dependencies |
|---|---|---|---|
| `PreferencesManager.ets` | Repository | Key-value preferences via @ohos.data.preferences | `@kit.ArkData`, `../common/Logger`, `../service/Constants` |

### 3. Service Module (`service/`)
| File | Type | Description | Dependencies |
|---|---|---|---|
| `Constants.ets` | Config | All preference keys, file paths, defaults (ported from Android Constants.java) | None |
| `SyncthingService.ets` | Orchestrator | Core service lifecycle, polling, state management | `../network/RestApi`, `./EventProcessor`, `../common/EventBus` |
| `SyncthingProcessManager.ets` | Process | Native binary lifecycle (NAPI bridge interface) | `../network/RestApi`, `./Constants` |
| `FolderLocationManager.ets` | Storage mapping | Persists Harmony folder picker URI to Syncthing sandbox mirror path mappings and prepares `.stfolder` markers | `../data/PreferencesManager`, `./Constants` |
| `FolderMirrorService.ets` | Storage bridge | Manual incremental import/export between a selected folder location and the Syncthing sandbox mirror | `@ohos.file.fs`, `./FolderLocationManager`, `./Constants` |
| `FolderMirrorScheduler.ets` | Storage scheduler | Periodically imports external phone folders into the sandbox mirror for send-capable folder types | `../network/RestApi`, `./FolderLocationManager`, `./FolderMirrorService` |
| `EventProcessor.ets` | Event Pump | Polls REST API events, dispatches typed events | `../network/RestApi`, `../common/EventBus`, `../data/PreferencesManager` |
| `RunConditionMonitor.ets` | Decision | Evaluates when sync should run based on preferences | `../data/PreferencesManager`, `../common/EventBus` |
| `NotificationManager.ets` | Notification | Persistent and info notification management | `@kit.NotificationKit`, `../common/Logger` |

### 4. Network Module (`network/`)
| File | Type | Description | Dependencies |
|---|---|---|---|
| `ApiRequest.ets` | HTTP Client | Wraps @ohos.net.http for REST API calls (GET/POST/PUT/PATCH/DELETE) | `@kit.NetworkKit`, `../common/Logger` |
| `RestApi.ets` | API Facade | Full Syncthing REST API client (~40 endpoints) | `./ApiRequest`, `../model/Index`, `../data/PreferencesManager` |
| `SyncthingTrustManager.ets` | SSL Trust | Manages self-signed certificate trust | `@kit.DeviceCertificateKit` |

### 5. Model Module (`model/`)
| File | Type | Description |
|---|---|---|
| `SyncthingConfig.ets` | Interface | Full config structure (folders, devices, gui, options, LDAP) |
| `Device.ets` | Interface | Device configuration, pending devices |
| `GuiConfig.ets` | Interface | GUI/Web UI configuration |
| `Options.ets` | Interface | Global options configuration |
| `SystemStatus.ets` | Interface | System status model |
| `SystemVersion.ets` | Interface | Version info model |
| `Connection.ets` | Interface | Connection/connections models |
| `Event.ets` | Interface | Event models |
| `FolderStatus.ets` | Interface | Per-folder status model |
| `Completion.ets` | Interface | Completion info model |
| `ClusterConfig.ets` | Interface | Pending device/folder models |
| `DeviceStat.ets` | Interface | Device stats model |
| `FolderCompletion.ets` | Interface | Folder completion model |
| `IgnoredFolder.ets` | Interface | Ignored folder model |
| `Index.ets` | Barrel | Re-exports all models |

### 6. Pages Module (`pages/`)
| File | Role | UI Components |
|---|---|---|
| `Index.ets` | Splash/loading | Progress indicator, error state |
| `MainPage.ets` | Main tabbed view | Tabs (Devices/Folders/Status) |
| `FirstStartPage.ets` | Onboarding wizard | 4-step wizard (intro, privacy, identity, ready) |
| `DeviceListPage.ets` | Device list | List of configured devices |
| `FolderListPage.ets` | Folder list | List of configured folders with status |
| `DeviceDetailPage.ets` | Device config | Device detail/edit form |
| `FolderDetailPage.ets` | Folder config | Folder detail/edit form |
| `SettingsPage.ets` | Settings | Preference toggles and sections |
| `WebGuiPage.ets` | WebView | Embedded Syncthing Web GUI |
| `RecentChangesPage.ets` | Recent changes | Recent file change list |
| `LogPage.ets` | Log viewer | Log message list |

### 7. Native Module (`cpp/`)
| File | Role |
|---|---|
| `CMakeLists.txt` | CMake build config for NAPI library |
| `syncthing_napi_bridge.cpp` | NAPI bridge to Go-compiled libsyncthingnative.so |

### 8. Build Scripts
| File | Role |
|---|---|
| `build_syncthing_harmonyos.py` | Cross-compiles Go Syncthing to .so for HarmonyOS |

---

## Data Flow Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                        UI Layer (ArkUI)                       │
│  Index → MainPage → DeviceList/FolderList/Settings/WebGui   │
│  Uses @State, @Prop, @Link for reactive updates              │
└────────────────────────┬─────────────────────────────────────┘
                         │ calls RestApi methods
                         ▼
┌──────────────────────────────────────────────────────────────┐
│                     Service Layer                             │
│  SyncthingService ──► RestApi ──► @ohos.net.http             │
│         │                  │                                  │
│         ▼                  ▼                                  │
│  EventProcessor    ApiRequest                                 │
│  (polls /rest/events)                                        │
│         │                                                     │
│         ▼                                                     │
│  EventBus.emit() ──► Pages receive via emitter.on()           │
└────────────────────────┬─────────────────────────────────────┘
                         │ HTTPS localhost:8384
                         ▼
┌──────────────────────────────────────────────────────────────┐
│                   Native Engine (NAPI)                        │
│  syncthing_napi.so ──► libsyncthingnative.so (Go)           │
│  - dlopen at runtime                                          │
│  - Starts Syncthing (REST API + Sync Engine)                  │
│  - config.xml, certs, index-v2 DB                             │
└──────────────────────────────────────────────────────────────┘
```

---

## State Management Strategy

### Service State Machine
```
  ┌─────────┐    startService()    ┌──────────┐
  │ stopped │ ──────────────────► │ starting  │
  └─────────┘                     └────┬─────┘
       ▲                               │ success
       │                               ▼
       │                          ┌──────────┐
       │   stopService()          │  active  │
       │ ◄──────────────────────── │          │
       │                          └────┬─────┘
       │                               │ error
       │                               ▼
       │                          ┌──────────┐
       └──────────────────────────│  error   │
               stopService()      └──────────┘
```

### Run Condition Decisions
```
RunConditionMonitor.checkConditions()
  → Check force start/stop button state
  → Check alwaysRunInBackground preference
  → Check time schedule (sync/sleep intervals)
  → Return: SHOULD_RUN | SHOULD_NOT_RUN | FORCE_START | FORCE_STOP
```

### Polling Strategy
```
SyncthingService.pollStatus()
  → GET /rest/system/status  (every 3s)
  → GET /rest/system/connections (every 3s)
  → GET /rest/config (every 3s)

EventProcessor.pollEvents()
  → GET /rest/events?since=<lastId>&limit=100 (every 3s)
  → Process events → emit typed events via EventBus
```

### Folder Storage Strategy

```text
FolderDetailPage
  -> App Storage
     -> Syncthing folder.path = /data/storage/el2/base/files/{folderId}
  -> System Folder (only when FolderSelection syscap is available)
     -> DocumentViewPicker returns Harmony URI
     -> FolderLocationManager stores URI + sandbox mirror path
     -> Syncthing folder.path = /data/storage/el2/base/files/{folderId}
     -> FolderMirrorService can manually import selected-folder files into
        the sandbox mirror and trigger a Syncthing scan
     -> FolderMirrorScheduler periodically imports send-capable mapped folders
        while SyncthingService is active
```

The embedded Go core must operate on filesystem paths it can scan directly.
Harmony picker URIs are therefore treated as app-level storage grants, not as
Syncthing paths. Manual import/export is now available as a migration step; the
next module needed for full public-folder sync is a background mirror worker
plus a picker-URI write bridge.

On the current phone profile,
`SystemCapability.FileManagement.UserFileService.FolderSelection` is not
available, so the UI disables the System Folder action and keeps App Storage as
the stable storage path. Devices that expose the syscap can still enter the URI
mirror path.

### Implemented Feature UI Management

StatusPage is the implemented-feature hub. It displays core/REST health,
configured and connected devices, pending pairing, recent core logs, and a
feature availability card. The card distinguishes always-available migrated
features from platform-gated features such as system folder selection.

DeviceListPage reads `/rest/system/connections` and marks configured devices as
Connected, Waiting, or Paused. SettingsPage persists local run-condition and
debug preferences through PreferencesManager, while Syncthing option settings
continue to write through `/rest/config/options`.

---

## API Coverage Map

### Fully Implemented
| Method | Endpoint | Implemented |
|---|---|---|
| `ping()` | GET /rest/noauth/health | Yes |
| `getSystemStatus()` | GET /rest/system/status | Yes |
| `getVersion()` | GET /rest/system/version | Yes |
| `getConnections()` | GET /rest/system/connections | Yes |
| `getDiscoveryInfo()` | GET /rest/system/discovery | Yes |
| `getSystemErrors()` | GET /rest/system/error | Yes |
| `clearSystemErrors()` | POST /rest/system/error/clear | Yes |
| `getSystemPaths()` | GET /rest/system/paths | Yes |
| `getSystemUpgrade()` | GET /rest/system/upgrade | Yes |
| `getSystemLog()` | GET /rest/system/log | Yes |
| `getLogLevels()` | GET /rest/system/loglevels | Yes |
| `shutdownSyncthing()` | POST /rest/system/shutdown | Yes |
| `restartSyncthing()` | POST /rest/system/restart | Yes |
| `upgradeSyncthing()` | POST /rest/system/upgrade | Yes |
| `resetDatabase()` | POST /rest/system/reset | Yes |
| `pauseDevice()` | POST /rest/system/pause | Yes |
| `resumeDevice()` | POST /rest/system/resume | Yes |
| `getConfigFull()` | GET /rest/config | Yes |
| `getFolders()` | GET /rest/config/folders | Yes |
| `getFolder()` | GET /rest/config/folders/:id | Yes |
| `putFolder()` | PUT /rest/config/folders/:id | Yes |
| `patchFolder()` | PATCH /rest/config/folders/:id | Yes |
| `deleteFolder()` | DELETE /rest/config/folders/:id | Yes |
| `getDevices()` | GET /rest/config/devices | Yes |
| `getDevice()` | GET /rest/config/devices/:id | Yes |
| `putDevice()` | PUT /rest/config/devices/:id | Yes |
| `patchDevice()` | PATCH /rest/config/devices/:id | Yes |
| `deleteDevice()` | DELETE /rest/config/devices/:id | Yes |
| `getOptions()` | GET /rest/config/options | Yes |
| `putOptions()` | PUT /rest/config/options | Yes |
| `getGuiConfig()` | GET /rest/config/gui | Yes |
| `putGuiConfig()` | PUT /rest/config/gui | Yes |
| `getFolderStatus()` | GET /rest/db/status | Yes |
| `getCompletion()` | GET /rest/db/completion | Yes |
| `getFileInfo()` | GET /rest/db/file | Yes |
| `getNeedFiles()` | GET /rest/db/need | Yes |
| `browseFolder()` | GET /rest/db/browse | Yes |
| `getIgnorePatterns()` | GET /rest/db/ignores | Yes |
| `putIgnorePatterns()` | POST /rest/db/ignores | Yes |
| `triggerRescan()` | POST /rest/db/scan | Yes |
| `overrideChanges()` | POST /rest/db/override | Yes |
| `revertChanges()` | POST /rest/db/revert | Yes |
| `getEvents()` | GET /rest/events | Yes |
| `getDiskEvents()` | GET /rest/events/disk | Yes |
| `getDeviceStats()` | GET /rest/stats/device | Yes |
| `getFolderStats()` | GET /rest/stats/folder | Yes |
| `getPendingDevices()` | GET /rest/cluster/pending/devices | Yes |
| `getPendingFolders()` | GET /rest/cluster/pending/folders | Yes |

---

## Test Coverage Plan

### Unit Tests
| Module | Test File | Coverage |
|---|---|---|
| Utils | Common.test.ets | formatBytes, formatDuration, completionPercent, compareDeviceIds, isEmpty |
| ServiceLocator | Common.test.ets | register, get, getOrThrow, remove |
| Constants | Common.test.ets | default values, path generators, dynamic pref keys |
| ApiRequest | Network.test.ets | URL building, base URL change |
| RestApi | Network.test.ets | initialization, availability, connected devices |
| RunConditionMonitor | Service.test.ets | state checking, button state |
| EventBus | Service.test.ets | emit/receive cycle |
| NotificationManager | Service.test.ets | singleton pattern |

### Integration Tests
| Scenario | Test File | Coverage |
|---|---|---|
| Service lifecycle | SyncthingIntegration.test.ets | init, start, stop, destroy |
| App flow | SyncthingIntegration.test.ets | config constants, dynamic keys |
| EntryAbility | Ability.test.ets | context registration |

---

## Permissions Required

| Permission | Reason |
|---|---|
| `ohos.permission.INTERNET` | P2P sync and REST API communication |
| `ohos.permission.GET_NETWORK_INFO` | Detect WiFi/mobile data for run conditions |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | File sync in background |
| `ohos.permission.WRITE_USER_STORAGE` | Write synced files |
| `ohos.permission.READ_USER_STORAGE` | Read synced files |
| `ohos.permission.NOTIFICATION` | Sync status notifications |

---

## File Count Summary

| Category | Files |
|---|---|
| Types | 1 |
| Common utilities | 4 |
| Data layer | 1 |
| Service layer | 6 |
| Network layer | 3 |
| Model (data) | 13 |
| Pages (UI) | 10 |
| Native (C++) | 2 |
| Build scripts | 1 |
| Tests | 8 |
| Configuration | 7 |
| Documentation | 2 |
| **Total** | **58** |

---

## Native Core Module Design Update

### Go Export Layer (`syncthing/cmd/syncthing`)

| File | Responsibility |
|---|---|
| `harmony_exports.go` | Harmony-only C ABI exports for starting and observing Syncthing core |
| `process_exit_default.go` | Default non-Harmony process exit behavior |
| `main.go` | Calls `syncthingMainExit()` at normal shutdown instead of hardcoding `os.Exit()` |

Exported ABI:

| Symbol | Signature | Purpose |
|---|---|---|
| `Start` | `(homeDir, logFile, guiAddress, apiKey) -> int` | Start Syncthing in a goroutine |
| `Stop` | `() -> int` | Stop hint; graceful stop is REST shutdown |
| `IsRunning` | `() -> int` | Native running flag |
| `Version` | `() -> char*` | Go core long version |
| `LastError` | `() -> char*` | Last startup/runtime bridge error |
| `FreeCString` | `(char*) -> void` | Release C strings returned by Go |

### C++ NAPI Layer (`entry/src/main/cpp`)

| File | Responsibility |
|---|---|
| `syncthing_napi_bridge.cpp` | Loads Go library via `dlopen`, resolves C ABI symbols, exposes ArkTS functions |
| `CMakeLists.txt` | Builds `libsyncthing_napi.so` and copies `libsyncthingnative.so` into the packaged native libs |

NAPI API:

| Function | Purpose |
|---|---|
| `loadLibrary(path)` | Load Go shared library by name or path |
| `startSyncthing(homeDir, logFile, guiAddress, apiKey)` | Start Go core |
| `stopSyncthing()` | Call Go stop hint |
| `isRunning()` | Check Go running state |
| `getVersion()` | Read Go version |
| `getLastError()` | Read Go bridge error |

### ArkTS Native Wrapper

| File | Responsibility |
|---|---|
| `native/SyncthingNative.ets` | Typed wrapper around `libsyncthing_napi.so` |
| `types/libsyncthing_napi.d.ts` | NAPI module declaration for ArkTS compilation |

### Service Integration

| File | Current Behavior |
|---|---|
| `SyncthingProcessManager.ets` | Loads native libs, starts Go core, waits for REST health, stops via REST shutdown |
| `SyncthingService.ets` | Uses process manager before entering `active` state |
| `RestApi.ets` | Uses `http://127.0.0.1:8384` and stored local API key |
| `Constants.ets` | Defines native file name, REST base URL, API key preference, path helpers |

### Validation Checklist

| Check | Status |
|---|---|
| Go SDK used from E drive | Passed |
| Go module/cache/temp paths on E drive | Passed |
| `libsyncthingnative.so` builds for ARM64 | Passed |
| Go exports `Start/Stop/Version/IsRunning/LastError/FreeCString` | Passed |
| ArkTS and C++ NAPI compile | Passed |
| HAP includes Go core shared library | Passed |
| Device/emulator runtime start test | Pending |
