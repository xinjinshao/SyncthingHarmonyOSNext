# SyncthingHarmonyOSNext — Architecture Design Document

## 1. Source Architecture Analysis (syncthing-android)

### 1.1 Architectural Pattern
- **Wrapper Pattern**: Android app wraps the Go-based Syncthing binary as a native process
- **Communication**: HTTPS REST API on localhost:8384 to the running Syncthing process
- **DI Framework**: Dagger 2 (constructor injection, singleton scope)
- **UI Pattern**: MVVM-like (Activities/Fragments observe RestApi → EventProcessor → LocalBroadcast)
- **Persistence**: SharedPreferences for app settings; Syncthing's own config.xml + index DB for sync data

### 1.2 Component Hierarchy
```
Application (SyncthingApp)
  ├── SyncthingService (Foreground Service)
  │   ├── SyncthingRunnable (Manages native Go binary process)
  │   ├── RestApi (HTTP client for Syncthing REST API)
  │   ├── EventProcessor (Polls events, broadcasts to UI)
  │   ├── RunConditionMonitor (Decides when sync runs)
  │   └── NotificationHandler (Persistent notification)
  ├── Activities (17, extending SyncthingActivity which binds to Service)
  │   ├── FirstStartActivity (Onboarding)
  │   ├── MainActivity (ViewPager: Folders, Devices, Status)
  │   ├── FolderActivity, DeviceActivity (Detail/Config)
  │   ├── WebGuiActivity (WebView for Syncthing GUI)
  │   └── SettingsActivity (Compose-based settings)
  ├── Fragments (DeviceList, FolderList, Status, Drawer, Dialogs)
  └── Receivers (BootReceiver, AppConfigReceiver)
```

### 1.3 Key Architecture Constraints from Android
| Constraint | Android Implementation | HarmonyOS Equivalent |
|---|---|---|
| C1: Background execution | Foreground Service (startForeground) | ContinuousTask + background task |
| C2: Native binary execution | ProcessBuilder on libsyncthingnative.so | NAPI shared library + TaskPool |
| C3: REST API client | Volley HTTP library | @ohos.net.http (HttpRequest) |
| C4: Local HTTPS with self-signed cert | Custom TrustManager | certificatePinning / custom ca |
| C5: App settings storage | SharedPreferences | @ohos.data.preferences |
| C6: File system access | java.io.File | @ohos.file.fs |
| C7: Event bus for UI updates | LocalBroadcastManager | @ohos.events.emitter or State management |
| C8: Dependency injection | Dagger 2 | Manual DI or simple service locator |
| C9: JSON parsing | Gson | Built-in JSON or @ohos.util |
| C10: UI framework | XML Layouts + Jetpack Compose | ArkUI declarative (ArkTS) |

---

## 2. HarmonyOS Migration Architecture

### 2.1 Technology Mapping

| Layer | Android Technology | HarmonyOS Technology |
|---|---|---|
| Language | Java + Kotlin | ArkTS (extended TypeScript) |
| UI | XML Layouts + Compose | ArkUI declarative components |
| Background | Foreground Service | ContinuousTask (long-running) |
| HTTP Client | Volley | @ohos.net.http |
| Preferences | SharedPreferences | @ohos.data.preferences |
| DI | Dagger 2 | Service Locator (singleton map) |
| JSON | Gson | Native JSON.parse/stringify + typed interfaces |
| File I/O | java.io.File | @ohos.file.fs |
| Native Code | ProcessBuilder (exec) | NAPI (native shared library) |
| Events | LocalBroadcast | @ohos.events.emitter |
| Logging | android.util.Log | @ohos.hilog |
| Navigation | Fragment transactions | @ohos.arkui.router |

### 2.2 Module Structure Design

```
entry/src/main/ets/
├── entryability/
│   └── EntryAbility.ets              # Main UIAbility (app entry)
├── service/
│   ├── SyncthingService.ets          # Core sync service (ContinuousTask)
│   ├── SyncthingProcessManager.ets   # Native Go binary lifecycle (NAPI)
│   ├── RunConditionMonitor.ets       # Sync run conditions
│   ├── EventProcessor.ets            # Event polling & distribution
│   ├── NotificationManager.ets       # Local notifications
│   └── Constants.ets                 # Constants & config keys
├── network/
│   ├── RestApi.ets                   # Syncthing REST API client
│   ├── ApiRequest.ets                # HTTP request wrapper
│   └── SyncthingTrustManager.ets     # SSL certificate trust
├── model/
│   ├── Config.ets                    # Syncthing configuration model
│   ├── Device.ets                    # Device model
│   ├── Folder.ets                    # Folder model
│   ├── Event.ets                     # Event model
│   ├── SystemStatus.ets              # System status model
│   ├── Connection.ets                # Connection model
│   └── Index.ets                     # Barrel export
├── data/
│   ├── PreferencesManager.ets        # App preferences wrapper
│   └── ConfigXmlManager.ets          # Config XML read/write
├── pages/
│   ├── Index.ets                     # Splash/Loading page
│   ├── FirstStartPage.ets            # Onboarding wizard
│   ├── MainPage.ets                  # Main tabbed page
│   ├── DeviceListPage.ets            # Device list
│   ├── FolderListPage.ets            # Folder list
│   ├── DeviceDetailPage.ets          # Device config
│   ├── FolderDetailPage.ets          # Folder config
│   ├── WebGuiPage.ets                # Embedded WebView
│   ├── SettingsPage.ets              # App settings
│   ├── RecentChangesPage.ets         # Recent file changes
│   └── LogPage.ets                   # Log viewer
├── components/
│   ├── DeviceListItem.ets            # Device list item component
│   ├── FolderListItem.ets            # Folder list item component
│   ├── StatusCard.ets                # Status display card
│   ├── SyncProgressBar.ets           # Sync progress component
│   └── CommonDialog.ets              # Reusable dialog
├── common/
│   ├── ServiceLocator.ets            # Simple DI container
│   ├── EventBus.ets                  # Internal event bus
│   ├── Logger.ets                    # Logging utility
│   └── Utils.ets                     # General utilities
└── types/
    └── index.ets                     # Shared TypeScript type definitions
```

### 2.3 Process Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    EntryAbility (UIAbility)               │
│  - App lifecycle management                              │
│  - UI window creation                                    │
│  - Starts SyncthingService                               │
└──────────────────────┬───────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────┐
│              SyncthingService (Service Layer)             │
│  - Manages native Syncthing process via NAPI             │
│  - ContinuousTask for background execution               │
│  ┌─────────────────┐  ┌──────────────────┐              │
│  │ ProcessManager   │  │ RunConditionMon. │              │
│  │ (NAPI lifecycle) │  │ (WiFi/power/etc) │              │
│  └────────┬────────┘  └──────────────────┘              │
│  ┌────────▼────────┐  ┌──────────────────┐              │
│  │  EventProcessor  │  │    RestApi       │              │
│  │  (SSE polling)  │  │  (HTTP client)   │              │
│  └─────────────────┘  └────────┬─────────┘              │
└────────────────────────────────┼─────────────────────────┘
                                 │ HTTPS (localhost:8384)
┌────────────────────────────────▼─────────────────────────┐
│              Native Syncthing Engine (NAPI)               │
│  libsyncthing.so (Go → cross-compiled → .so)            │
│  - REST API + Web GUI server                             │
│  - File sync engine                                      │
│  - config.xml, certs, index DB                          │
└──────────────────────────────────────────────────────────┘
```

### 2.4 Key Design Decisions

**D1: NAPI for Native Integration**
- Compile syncthing Go code to a shared library via CGo + HarmonyOS NDK cross-compilation
- Use NAPI to call `SyncthingMain()` as a library function
- The Go library will start its own HTTP server on localhost:8384
- This is analogous to Android's ProcessBuilder approach but adapted for HarmonyOS's NAPI model

**D2: ContinuousTask for Background**
- Use HarmonyOS ContinuousTask API for long-running background sync
- Similar to Android's Foreground Service
- Provides persistent notification to user

**D3: @ohos.events.emitter for Event Bus**
- Replace Android's LocalBroadcastManager
- Use emitter for decoupled communication between layers

**D4: Service Locator over DI Framework**
- Manual singleton service locator instead of Dagger
- Simpler for the HarmonyOS ecosystem

**D5: Declarative UI with ArkUI**
- Replace XML layouts and Compose with ArkUI declarative components
- Use @State, @Prop, @Link for reactive UI
- Router for page navigation

**D6: @ohos.data.preferences for Settings**
- Direct equivalent to SharedPreferences
- Key-value storage with same API pattern

---

## 3. Data Flow Architecture

### 3.1 REST API Communication Flow
```
User Action → UI Page → RestApi.getFolders()
  → @ohos.net.http.createHttp()
  → GET https://localhost:8384/rest/config/folders
  → Parse JSON → Folder[] models
  → Return to UI → @State update → Re-render
```

### 3.2 Event Polling Flow
```
EventProcessor.start()
  → RestApi.getEvents(sinceEventId)
  → Parse SSE events
  → @ohos.events.emitter.emit('syncthing:event', eventData)
  → DeviceListPage/FolderListPage subscribe
  → Update @State → Re-render
```

### 3.3 Config Update Flow
```
User modifies config on UI
  → FolderDetailPage.onSave(folderConfig)
  → RestApi.updateFolder(folderId, folderConfig)
  → PUT/POST /rest/config/folders/:id
  → Syncthing native engine processes config change
  → EventProcessor detects ConfigSaved event
  → UI updates automatically
```

---

## 4. APIs to Restore (Syncthing REST endpoints used)

### Status/System
| Endpoint | Purpose |
|---|---|
| GET /rest/system/status | Overall system status (uptime, version, stats) |
| GET /rest/system/version | Syncthing version |
| GET /rest/system/connections | Active device connections |
| GET /rest/system/error | Current errors |
| GET /rest/system/ping | Health check |
| GET /rest/system/upgrade | Available upgrade |
| POST /rest/system/shutdown | Shutdown Syncthing |
| POST /rest/system/restart | Restart Syncthing |
| POST /rest/system/pause | Pause devices |
| POST /rest/system/resume | Resume devices |
| POST /rest/system/reset | Reset database |
| POST /rest/system/error/clear | Clear errors |

### Config
| Endpoint | Purpose |
|---|---|
| GET /rest/config | Full configuration |
| GET /rest/config/folders | All folders |
| GET/PUT/PATCH/DELETE /rest/config/folders/:id | Single folder CRUD |
| GET/PUT /rest/config/devices | All devices |
| GET/PUT/PATCH/DELETE /rest/config/devices/:id | Single device CRUD |
| GET/PUT /rest/config/options | Global options |
| GET/PUT /rest/config/gui | GUI settings |

### Database
| Endpoint | Purpose |
|---|---|
| GET /rest/db/status | Folder DB status |
| GET /rest/db/completion | Completion percentage |
| GET /rest/db/file | File metadata |
| GET /rest/db/need | Files needed |
| GET /rest/db/browse | Browse folder contents |
| POST /rest/db/scan | Trigger rescan |
| POST /rest/db/override | Override changes |
| POST /rest/db/revert | Revert changes |

### Events
| Endpoint | Purpose |
|---|---|
| GET /rest/events | Event stream (since, limit) |

---

## 5. Implementation Phases

### Phase 0: Architecture & Setup ✓ (This document)
- Architecture analysis and design
- Project structure setup
- Configuration files (module.json5, build-profile, oh-package)

### Phase 1: Core Infrastructure
- EntryAbility (lifecycle, logging, service startup)
- ServiceLocator (DI container)
- PreferencesManager (data persistence)
- Logger (unified logging)
- Constants (all configuration keys)

### Phase 2: Network Layer
- RestApi (REST API client with all endpoints)
- SyncthingTrustManager (SSL trust for self-signed certs)
- Type definitions for all API responses

### Phase 3: Service Layer
- SyncthingService (core orchestration)
- SyncthingProcessManager (native binary lifecycle)
- RunConditionMonitor (run conditions)
- EventProcessor (event polling)
- NotificationManager (persistent notification)

### Phase 4: Native Integration
- Go cross-compilation script for HarmonyOS (ARM64)
- NAPI bridge module
- Build integration with hvigor

### Phase 5: UI Layer
- Main page with tab navigation
- Device/Folder list and detail pages
- Settings page
- WebGui page (embedded WebView)
- Onboarding/first-start wizard

### Phase 6: Testing & Verification
- Unit tests for service and network layers
- Integration tests for UI flows
- Mock services for testing

---

## 6. Current Native Core Integration Update

### 6.1 Runtime Architecture

The HarmonyOS Next app now embeds Syncthing core as a Go `c-shared` library:

```
ArkTS UI / Service
  -> SyncthingProcessManager
  -> SyncthingNative.ets
  -> libsyncthing_napi.so
  -> dlopen("libsyncthingnative.so")
  -> Go Syncthing core
  -> REST API on http://127.0.0.1:8384
```

The app still uses Syncthing's REST API as the main control plane. NAPI is only
responsible for process-like lifecycle operations: load, start, stop hint,
version, running state, and last error.

### 6.2 Go Core Constraints

- The Go core is built from the upstream `syncthing/cmd/syncthing` package with
  build tags `harmonyos,purego,noassets`.
- `harmonyos` adds the exported C ABI functions `Start`, `Stop`, `IsRunning`,
  `Version`, `LastError`, and `FreeCString`.
- `noassets` intentionally excludes Syncthing's bundled Web UI assets because
  the Harmony app owns the primary UI. The REST API remains available.
- Normal Syncthing shutdown is adapted so REST `/rest/system/shutdown` does not
  call `os.Exit(0)` on the whole Harmony app process.
- Fatal early-start failures in the upstream core may still call `os.Exit`.
  This is an explicit risk to remove in the next hardening iteration.

### 6.3 Packaging Constraints

- Go SDK, Go module cache, Go build cache, OHPM cache, NPM cache, and temp paths
  are redirected to `E:\Programming`.
- The Go shared library is emitted to
  `entry/src/main/libs/arm64-v8a/libsyncthingnative.so`.
- CMake copies that library into the native output directory so hvigor packages
  it alongside `libsyncthing_napi.so`.
- The signed HAP must contain:
  - `libs/arm64-v8a/libsyncthing_napi.so`
  - `libs/arm64-v8a/libsyncthingnative.so`

### 6.4 Service Startup Flow

1. `SyncthingService.initialize()` creates and registers
   `SyncthingProcessManager`.
2. `SyncthingProcessManager` ensures a stable local REST API key in
   preferences.
3. `startService()` loads `libsyncthingnative.so` through NAPI.
4. NAPI calls Go `Start(homeDir, logFile, guiAddress, apiKey)`.
5. The service waits for `/rest/noauth/health`.
6. After REST is available, polling and event processing begin.

### 6.5 Current Verification

- `python build_syncthing_harmonyos.py --target arm64`: passed.
- `powershell -ExecutionPolicy Bypass -File scripts\build-hap-e.ps1`: passed.
- `llvm-nm -D libsyncthingnative.so`: confirmed exported symbols.
- HAP archive inspection: confirmed both native libraries are packaged.
