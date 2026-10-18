# Sync folders between Android devices with a Mac

SwitchBoard can compare and sync selected folders between two Android devices connected to a Mac. The Mac coordinates and stages file transfers between the devices. Sync is manual and preview-first: it does not run in the background, and deletions are never propagated.

## What Android folder sync does

- Save a sync rule with a source device, destination device, folder paths, and one-way or two-way mode.
- Scan both folders and preview the proposed changes before applying them.
- Mark differing files as conflicts when the app cannot safely choose a version.
- Apply only after explicit confirmation. Unresolved conflicts are skipped.

The Wi-Fi browser portal is not a paired device endpoint, so it cannot be used as one side of a folder sync rule. Both endpoints must be available to SwitchBoard as Android devices over MTP or ADB.

## Create a folder sync rule

1. Connect both Android devices to the Mac. For USB MTP, unlock each phone and set USB mode to **File transfer**. Alternatively, connect one or both devices with authorized ADB.
2. In Transfer Hub, open **Sync** and choose the source and destination devices.
3. Enter the source and destination folder paths. You can browse a device and use a folder as a sync source or destination. ADB paths are limited to shared storage (commonly `/sdcard`). For MTP, scanning `/` covers shared storage and may take time.
4. Choose **One-way** or **Two-way** mode and save the rule.
5. Preview the plan. Inspect file copies, folder creation, and any conflicts before applying changes.
6. Choose a resolution for conflicts where offered, then confirm **Apply safe changes**.

## Choose one-way or two-way sync

**One-way** treats the configured source as authoritative for files that exist on both sides. Source-only files are copied to the destination. Destination-only files are kept; they are not removed. If a destination file changed after the saved baseline, the app flags it rather than silently overwriting it.

**Two-way** copies new files found on either side. If the same path contains different versions, or both copies changed since the last baseline, SwitchBoard reports a conflict and asks you to choose which side to keep. It does not automatically merge file contents.

## Safety and known limitations

- Sync is run manually; saved rules do not run in the background.
- Deletions are never propagated. Sync is not a backup or a two-way delete mirror.
- Applying a planned copy can replace a file at the destination. Review the plan and keep a separate backup of important data.
- The app compares relative paths, file sizes, and available modification times rather than hashing all file contents. Same-size edits with unavailable or indistinguishable timestamps may not be detected.
- Both devices need to be connected for each scan and apply. Transfers are staged through the Mac.
- MTP currently appears as one generic USB device because its helper does not provide a unique serial. Multiple MTP-only phones may not have reliably separate remembered identities.

For a one-time move instead of a recurring manual rule, see [how to transfer files from Android to Mac](android-file-transfer-to-mac.md). For USB discovery issues, see [Android USB/MTP troubleshooting](android-mtp-not-working-on-mac.md).
