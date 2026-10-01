# API 26 storage validation

Validation date: 2026-10-01 (Asia/Dubai).

Scope: this report describes the locally built and installed API 26 working copy, including implementation changes not included in the documentation-only publication. It is not evidence that the previously committed API 20 revision implements these features.

## Latest acceptance summary

| Check | Result |
|---|---|
| Signed Debug/Release build and package checks | Passed |
| Replacement installation, unlocked app launch, REST health | Passed; health returns OK |
| App access to Shared and temporary native scan | Passed |
| File Manager donation visibility | Failed user acceptance; no Syncthing or application-files entry |
| Automatic Gallery visibility | Not observed; not guaranteed by donation configuration |
| Download/Photos picker | Selection succeeded; persistent authorization rejected (13900001 / PERSISTENCE_FORBIDDEN) |
| Manual Save to Gallery | Runtime acceptance pending |
| Donation database registration | Unverified; installation enters UpdateShareFileInfo |
| System donation implementation | Related parser/database/query markers confirmed in device binary |
| File Manager consumer integration | Leading investigation hypothesis; not a confirmed defect |

## Implemented

- Only /el2/base/files/Shared is shared/donated, with r+w access.
- EntryAbility prepares Shared. New folder defaults are Shared/<folder-id>.
- Existing sync paths are retained; no data migration occurs.
- Sandbox Files offers user-confirmed Save to Gallery for supported media.
- Gallery export copies bytes to the granted media URI and closes descriptors; it is not automatic Gallery synchronization.

## Verified on device

- HarmonyOS SDK 26.0.0.105; packaged minimum and target API 26.
- Signed Debug HAP builds, validates, installs and starts. Signed Release clean build and package verification also pass. The phone retains the Debug build for interactive checks.
- HDC debug-file transfer to Shared/api26-test.png and readback match SHA-256 EC00D46357A1FC842AED79916CE967DBB6E00EA49C5D9F9644CA3B3FF1A51694.
- A temporary unshared Syncthing folder api26-shared-validation indexes Shared. REST reports idle, five files, 82,818 bytes, zero errors. Test fixtures include earlier transfer probes; these counts do not represent user files.
- Existing configured sync folders retained their original paths.

## Remaining acceptance checks

1. File Manager visibility has failed on this build. Retest the PNG/text only after a concrete consumer-integration change or vendor-supported registration check.
2. Automatic Gallery visibility was not observed. A successful build or File Manager access alone is insufficient evidence; the donation guide does not promise Gallery indexing.
3. Sandbox Files -> Shared -> api26-test.png -> Save to Gallery: cancel once, then approve; verify the saved image opens in Gallery.
4. Change/delete a disposable file in File Manager and rescan: verify Syncthing observes it. Do not test deletion against user data.
5. Repeat with a video and nested directories. Verify whether albums preserve hierarchy; do not infer it from file paths.
6. Exported Gallery copies do not follow source edits/deletions. Repeated saves can duplicate media. Automatic propagation is not implemented.

No end-to-end peer transfer or Gallery UI acceptance has yet been established for this change. Test fixture insertion used HDC, not Syncthing peer reception.

## Reference

https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/share-app-file-configuration

API 26 uses /el2-prefixed scope paths. sharingOSPath must equal a configured scope; sharingOSSubpath may be empty; donation is supported on phone/tablet. The documented system consumers are File Manager and FilePicker. Gallery indexing is not promised by this guide.

## Reference comparison and phone result (2026-10-01)

User observation: the donated directory is absent in File Manager and the test image is absent in Gallery. Directory donation is therefore NOT accepted on this phone; successful package checks and native indexing do not establish system UI visibility.

Reference: https://github.com/forwardz666/Syncthing-for-HarmonyOS/tree/6c77381883cbceae4d8fde769d48d94044191d15

The reference has no module.shareFiles/sharingOS configuration. PublicFolderGrant.ets uses Environment.getUserDownloadDir()/Syncthing on supported devices, or DocumentViewPicker FOLDER selection with fileShare.persistPermission. Its README reports tablet/public Download validation and explicitly excludes Gallery directory-tree sync. This is public-directory access, not sandbox donation.

Phone runtime evidence (retrieved from app-produced storage-diagnostics.json):

- System API: 26; OpenHarmony-7.0.0.105; vendor software 7.0.0.109(SP6C00E105R6P2).
- Shared is readable by the application.
- FolderObtain capability: false.
- Environment.getUserDownloadDir(): BusinessError code 801.
- FolderSelection capability: true.

No demonstrated scope syntax error was found in the donation profile. The runtime/system-consumer cause of absent File Manager integration is still unresolved. API number alone is insufficient to assume every storage capability is present.

Added a separate Choose Public Folder action for NEW folders. The user selects the exact directory; the app obtains a native FileUri path, persists the full directory policy, checks persistence, activates it, and verifies listing. The URI is retained and reactivated on launch. Failure prevents selecting the public path. Existing sync paths/data are not migrated. FILE_ACCESS_PERSIST is declared; no broad Download/Documents permissions are added. This branch requires interactive selection and restart/core scan acceptance before being called verified.

Removed the temporary api26-shared-validation Syncthing configuration after probing to avoid a parent-root sync overlapping future Shared child folders. Test files remain; user data was not removed.

Signed Debug build, install, package verification, app startup and REST health pass after these changes. Public-picker runtime acceptance and Gallery export acceptance remain pending.

Picker observation: the user reports that the system keeps prompting to select a directory and does not allow completing selection. No persistent grant success or public core scan has been established. FolderSelection=true only indicates the advertised capability; it is not evidence of a successful directory grant.

## Download/Photos failure localized

The user tested Download/Photos. Device logs at 09:43:44 show picker resultCode=0 with one URI and the application receiving file://docs/storage/Users/currentUser/Download/Photos. The subsequent persistPermission call fails with BusinessError 13900001, policy code 1, message URI forbid to be persisted. Therefore the earlier inference that selection never returned was incorrect: this attempt completed selection and failed at persistent authorization. This result proves rejection of this URI/policy on this device; it does not prove all directories or all API 26 phones are unsupported, nor does it establish the cause of missing sandbox donation UI.

Added explicit error handling for PERSISTENCE_FORBIDDEN so the application reports the selected directory was rejected for persistent access and keeps the existing sync path. No session-only fallback is silently accepted. The updated signed Debug build succeeds.

## Sandbox donation investigation: explicit subpath control

- The original narrow profile uses /el2/base/files/Shared with an empty sharingOSSubpath. It conforms to the current documented syntax, but the user reports no File Manager visibility.
- A legacy /base/files + /Shared profile was tried locally and rejected by SDK 26 PreBuild schema. It was not installed. No validator bypass was used.
- A valid control uses scope/sharingOSPath /el2/base/files and sharingOSSubpath /Shared. The final donated directory remains Shared. This broadens the scope eligible for explicit cross-app file sharing, but does not donate the parent directory. This control is experimental pending visual acceptance; the previous narrow profile is saved in .local/validation/donation-baseline.json.
- The control signed Debug HAP builds and installs. Installed bundle dump retains module.shareFiles, packaged profile contains the expected control fields, and app diagnostics show Shared readable. File Manager version is 7.0.51.270.
- No TransAndSetToMapInner rejection was observed in the collected installation log. Absence of a log is not proof of system registration. CrossAppSharedConfig=false is a different sharing feature and is not treated as evidence against sandbox donation.
- No root escalation, uninstall, user-data deletion, system modification, or certificate change was performed.
- Next acceptance signal: whether reopening File Manager now exposes Syncthing. Pending that result, there is no confirmed fix or confirmed OS defect.
Explicit-subpath outcome: no Syncthing directory and no application-files entry in File Manager. The control did not resolve visibility. The narrow Shared-only profile was restored, rebuilt, installed and started. No private-parent scope remains enabled. Backend registration and system-consumer support remain unresolved; see DONATION_REPRO.md.

## Further source investigation (2026-10-01)

Current official GitCode Sandbox Manager source accepts both tested paths and the empty subpath. It separates shared-scope map registration from donation database registration. A fresh replacement installation logs our bundle's UpdateShareFileInfo call, but the captured log does not establish the database result. Current public source also gates donation-list consumers on system-app status and ACCESS_SHARED_FILE; the installed File Manager is a system app but its dump contains no such permission. This is a consumer-integration lead, not a confirmed firmware defect. Details, exact source commits and log locations are recorded in DONATION_REPRO.md. No further speculative profile edits or business-code changes were made. Replacement installation succeeded; runtime relaunch is pending because the phone is locked.

Unlocked follow-up: Syncthing launch and REST health pass; fresh diagnostics confirm Shared readable. File Manager launches and refreshes storage locations, with no donation query/grant entries found in this capture. Read-only examination of the device Sandbox Manager binary confirms donation-related parser, database and query markers exist, but its success-log text differs from public source. Absence of the public source success message is therefore not evidence of failed registration. Consumer integration remains the leading hypothesis; registration database contents are unverified. See DONATION_REPRO.md for evidence limits. No business code or system files were modified.
