# SwitchBoard

SwitchBoard is a native macOS hub for moving files between this Mac and connected Android devices, with a browser-based local Wi-Fi bridge for phones and tablets. The app is currently named **Transfer Hub** in the UI.

## Product direction

Transfer Hub is organized around **endpoints**, not around a single “current phone”: choose a source, choose a destination, then move files. With two authorized devices, the app suggests that pair; with more, the user chooses explicitly. Transfers between devices are staged through this Mac, recorded with both endpoints, and can be retried after reconnecting. Device profiles and activity are local to this Mac; clearing activity does not delete device files. Previously completed files are marked in the browser.

The current pairing flow supports individual files between Android devices exposed through ADB or MTP, Mac↔device transfers, and manual folder sync between connected Android devices. Sync rules save a device pair, folder roots, and a per-pair baseline; each run scans both trees and requires a preview followed by explicit apply. One-way mode treats the source as authoritative but flags destination edits made since the baseline. Two-way mode routes a single-side edit to the other endpoint and offers an explicit keep-source/keep-destination choice when both changed. Deletions are never propagated, and background sync is off. iPhone currently participates through the local browser portal; direct iOS folder browsing/sync requires a separate iOS-compatible adapter and is not claimed by this build.

Sync compares relative paths, file sizes, and modification times where the transport provides them; it does not hash every file, so same-size changes with unavailable/equal timestamps may not be detected. Keep the same pair/rule/preview model when adding an iOS adapter, while allowing each transport to declare its actual capabilities.

ADB serials provide stable Android identities. The current OpenMTP helper does not expose a unique device serial through the integration, so MTP is represented as one remembered USB connection; switching between multiple MTP-only phones cannot yet be distinguished reliably. ADB can distinguish multiple connected Android devices. Activity and remembered profiles can be cleared/forgotten from the UI.

## Current build

- Discovers Android devices over USB or wireless ADB and scans USB MTP storage.
- Browses phone storage, queues transfers in either direction, and keeps transfer history across launches.
- Resumes interrupted ADB file transfers from a temporary partial file, and retries Wi-Fi browser uploads from the last saved chunk.
- Provides a QR-based local browser portal for Android and iOS: phones can upload to this Mac or download files selected for sharing.
- Shows per-transfer progress and setup guidance for missing ADB, MTP, and Android Wireless Debugging.
- Uses a platform-neutral connected-device model and separates the shared transfer queue from the Android connection methods, leaving room for additional device adapters.
- The device browser supports current-folder search, multi-select, bulk download to a chosen folder, preview through Quick Look, copy/paste between phone folders, and file-URL clipboard exchange with Finder. Upload from Mac accepts multiple files in one selection.
- Transfer history is stored locally, filterable by status, and recovers in-progress entries as retryable after an app restart.

The main navigation is **Transfer**, **Sync**, **Devices**, **Activity**, and **Shared**. The first-run screen leads with the straightforward USB option; developer-oriented ADB setup is under **More connection methods**. **Shared** explains local-network access before the portal is started and keeps the QR flow separate from device browsing. Appearance can follow macOS automatically or be set to Light or Dark.

ADB transfers require Android SDK Platform-Tools and USB debugging authorization. The app checks `PATH` and common macOS SDK locations for `adb`; if it is elsewhere, choose **Locate adb** in the app. Install Platform-Tools from Android Studio or the Android developer site, connect and unlock the phone, enable USB debugging, then approve the Mac's key on the phone. Wireless ADB requires pairing from Android's Wireless debugging settings; once paired, the app discovers the device.

MTP uses the MIT-licensed OpenMTP command-line helper. `build-app.sh` bundles it from `/Applications/OpenMTP.app` when available; the helper is also detected from a standard OpenMTP installation at runtime. On Apple Silicon, the x86_64 helper requires Rosetta. MTP devices should be unlocked and in File transfer mode. MTP retries restart the current file because the helper does not expose a safe partial-file resume interface; queued jobs and their history remain available.

The QR portal runs only after you start it in the app. It uses plain HTTP on your local network (port 8765 when available) with a temporary, unguessable URL token; use it only on a trusted network. Uploads are saved under `~/Downloads/Transfer Hub`. If the Mac firewall prompts, allow incoming connections. Phone-to-Mac uploads checkpoint in 1 MiB chunks and can resume when the same file is selected again in that phone browser.

## Build and launch

From this directory, run:

```sh
./build-app.sh
open "Transfer Hub.app"
```

The app targets macOS 14 or newer. The build creates a custom app icon. The generated app is ad-hoc signed for local use and is not notarized for distribution. A physical Android device is needed to verify USB/MTP behavior.
