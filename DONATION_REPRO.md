# Sandbox donation: reproducible failure

Date: 2026-10-01. Status: unresolved; not a confirmed system defect.

Scope: the locally built API 26 working copy. This documentation-only publication does not include the pending implementation changes or local diagnostic artifacts.

## Environment

- Phone software: ALT-AL10E 7.0.0.109(SP6C00E105R6P2).
- Device API 26; OpenHarmony-7.0.0.105; security patch 2026/09/01.
- File Manager: com.huawei.hmos.filemanager, version 7.0.51.270.
- DevEco Studio 26.0.0.851; SDK 26.0.0.105; signed Debug HAP, minimum/target API 26.

## Relevant configuration

module.shareFiles points to $profile:share_files. The profile scopes and sharingOSPath use /el2/base/files/Shared; sharingOSSubpath is empty; permissions are r+w. EntryAbility prepares /data/storage/el2/base/files/Shared. A PNG and text file exist there; native listing and PNG round-trip hash verification succeed. The installed module records shareFiles; packaged resources contain the profile; Syncthing can scan the directory.

## Controls and results

1. Narrow Shared root with empty subpath: builds/installs; user reports no File Manager visibility.
2. Parent root /el2/base/files with explicit /Shared subpath: same final donated directory; builds/installs; still no Syncthing directory or application-files entry. Reverted to the narrow profile.
3. Legacy /base/files root: SDK schema rejects it before installation. No validator bypass was used.

No path-validation rejection matching TransAndSetToMapInner was found in captured installation logs. This does not establish successful donation database registration. Current official GitCode source now exposes the relevant OpenHarmony implementation; its equivalence to this commercial firmware remains unverified.

## Source and device evidence from further investigation

- Official accesscontrol_sandbox_manager commit `346747d45dec5622fe4984a8a16f7e1afe83fdde` (2026-09-21), `services/sandbox_manager/main/cpp/src/share/share_files.cpp`: PathCompose accepts the current EL-prefixed path; ValidateSharingOSSubPath accepts an empty string. Both tested profiles resolve to `/storage/Users/currentUser/appdata/el2/base/com.syncthing.syncthingharmonyosnext/files/Shared`. No further path rewrite is justified by this source.
- The scopes map (`TransAndSetToMapInner`/`AddToMap`) and donation database (`ProcessShareFileInfo`/`WriteShareFileToDb`) are separate. A successful AddToShareMap log cannot establish successful donation registration.
- Official bundlemanager_bundle_framework commit `4dc1d2c4e787194444e15eba9ffaaf64c0d1de6a` (2026-09-30): replacement installation calls UpdateShareFileInfo. Processing may report an error while installation still succeeds. The helper is conditional on BMS_ACCESSCONTROL_SANDBOX_MANAGER. Therefore successful HAP installation alone is insufficient evidence.
- A fresh replacement install at 10:56:59 on this device logs SandboxManagerKit.UpdateShareFileInfo for our bundle/user 100 and later AddToShareMap. No ShareFile set success or donation database rejection was found in the captured log. This confirms entry into the update client, not the database result. Log: `.local/validation/donation-registration-reinstall.log` (local diagnostic artifact, not committed).
- In the inspected source, GetSharedDirectoryInfo and GrantSharedDirectoryPermission require a system application with `ohos.permission.ACCESS_SHARED_FILE`. They read the donation database by user. These are consumer privileges, not permissions to add to Syncthing.
- The installed File Manager bundle dump reports isSystemApp=true, but contains no ACCESS_SHARED_FILE permission. The local API 26 SDK includes that permission. This is a concrete consumer-integration lead; it does not prove the commercial implementation follows the identical gate, or exclude another system service acting as consumer.
- Relaunching Syncthing after replacement installation was blocked by the locked screen (10106102). No app code changed in this investigation; runtime relaunch is pending unlock.

Sources: https://gitcode.com/openharmony/accesscontrol_sandbox_manager and https://gitcode.com/openharmony/bundlemanager_bundle_framework . Source inspection was performed locally; no operating-system code was modified or built.

## Unlocked device follow-up

After unlock, Syncthing EntryAbility starts successfully, REST health returns OK, and freshly retrieved storage-diagnostics.json confirms Shared readable. File Manager MainAbility also starts successfully. Its settled logs show StorageDeviceList refresh and location preference handling (safeBox, samba, cloudDisk), but no GetSharedDirectoryInfo, QuerySharedFileInfoByUserId or GrantSharedDirectoryPermission entries. This is an observation for this launch, not proof that the app never calls them. Log: `.local/validation/filemanager-donation-settled.log`.

Read-only retrieval of `/system/lib64/libsandbox_manager_service.z.so` confirms this exact firmware binary contains sharingOSPath/sharingOSSubpath, WriteShareFileToDb, shared_file_info_table, GetSharedDirectoryInfo and ACCESS_SHARED_FILE strings. Therefore the firmware includes donation-related implementation; this narrows the investigation beyond merely checking the API version. String presence does not establish execution, database contents or complete source equivalence. The binary lacks the public source's `ShareFile set success` text, so absence of that success log on this device is not meaningful evidence of failed registration. No system binary was modified.

Current leading hypothesis: File Manager consumer integration/version mismatch. Remaining alternative: donation registration did not produce the expected row. An authorized system consumer query is needed to distinguish them; normal Syncthing application privileges cannot query the system-only list. No ACCESS_SHARED_FILE permission is added to Syncthing. Automatic Gallery indexing remains a separate, unpromised behavior.

Gallery does not automatically show the PNG, but automatic Gallery indexing is not promised by the configuration guide. Public directory selection is separate: Download/Photos is returned successfully, then persistPermission fails with 13900001 / PERSISTENCE_FORBIDDEN. That failure is not evidence of the cause of donation failure.

## Questions requiring vendor evidence

- Does File Manager 7.0.51.270 expose sandbox donation, and where is its entry?
- Is the exact phone software build supported, or is a later firmware/system-app build required?
- How can developers inspect the registered donation root of an installed app?
- Are there debug-signing, distribution or provisioning requirements absent from the guide?

No evidence establishes a missing permission, need for uninstall, or an OS defect. No user data was removed. Only Shared remains in the active sharing scope.

Reference: https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/share-app-file-configuration
