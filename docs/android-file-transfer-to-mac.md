# How to transfer files from Android to Mac

SwitchBoard is a native macOS Android file transfer app for browsing an Android phone and moving files to a Mac. This guide covers the three available connection methods—USB MTP, ADB, and local Wi-Fi—and when to use each one.

## Choose a transfer method

| Method | Best for | What to set up |
| --- | --- | --- |
| USB MTP | Straightforward wired file transfer | A data-capable USB cable; unlock the phone and choose **File transfer** in its USB notification. No USB debugging needed. |
| USB or wireless ADB | Android users comfortable enabling developer options; resumable wired transfers | Install Android SDK Platform-Tools, enable **USB debugging**, and authorize this Mac. For wireless ADB, pair through **Wireless debugging** first. |
| Wi-Fi browser portal | A quick wireless exchange without installing a phone app | Start sharing in Transfer Hub and open its QR-code link on the phone. Both devices must be on the same Wi-Fi network. |

For most people, start with USB MTP. If the phone is not detected, follow [the Android USB/MTP troubleshooting guide](android-mtp-not-working-on-mac.md). Choose ADB when you specifically need ADB access or its resumable file-transfer support. Choose the browser portal when you want to transfer without a cable or install on the phone.

## Transfer Android files to a Mac over USB MTP

1. Install Transfer Hub from the [SwitchBoard Releases page](https://github.com/adityarajpt/SwitchBoard/releases/latest). The current early-access build requires macOS 14 or later on Apple silicon. See [installation and Gatekeeper notes](../README.md#installing-the-non-notarized-build).
2. Connect the Android phone with a USB cable that supports data, not charging only.
3. Unlock the phone. Open its USB notification or USB preferences and select **File transfer** (sometimes named **Transferring files**).
4. In Transfer Hub, open **Devices** and choose **Scan for phone** or **Scan USB**.
5. Select the device and browse shared storage. Select one or more files, then choose the download action and a destination folder on the Mac.

MTP does not require Developer options or USB debugging. Keep the phone unlocked while browsing and transferring. Some MTP helpers on Apple silicon may need Rosetta; the app reports when its helper is unavailable.

## Transfer Android files to a Mac with ADB

1. Install [Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools) and make sure `adb` is available. Transfer Hub checks `PATH` and common Android SDK locations; use **Locate adb** if needed.
2. On the phone, enable **Developer options → USB debugging**.
3. Connect the phone, unlock it, and accept the prompt to allow USB debugging from this Mac.
4. In Transfer Hub, refresh or scan for devices, select the authorized Android device, and browse its shared storage.

ADB access is limited to the Android shared-storage area exposed by the app (commonly `/sdcard`). ADB transfer retries can resume partial file data where supported. For wireless ADB, first pair the Mac using Android's **Wireless debugging** screen; see [wireless file transfer over Wi-Fi](transfer-files-android-mac-wifi.md).

## Transfer files from Android to Mac over Wi-Fi

1. Connect the Mac and Android phone to the same Wi-Fi network.
2. In Transfer Hub, open **Shared** and start the sharing portal.
3. Scan the QR code with the phone camera, or open the displayed address in the phone's browser.
4. Select files in the phone browser to upload them to the Mac. The portal also lists files you explicitly shared from the Mac for download.

This is a local browser transfer; it does not require an Android companion app or cloud upload. Guest Wi-Fi, VPNs, firewalls, cellular-only connections, and router client isolation can prevent the devices from reaching one another. Read [Wi-Fi transfer setup and troubleshooting](transfer-files-android-mac-wifi.md) before using a network you do not trust.

## Move files between two Android phones

Connect both Android devices to the Mac, then use **Transfer** to select a source and destination. SwitchBoard stages the files through the Mac; it is not a direct phone-to-phone radio connection. For recurring folder workflows, set up a [preview-first sync rule](sync-folders-between-android-devices.md).

## Common questions

### Can I transfer Android files to Mac without an app on my phone?

Yes. Use USB MTP or ADB, or use Transfer Hub's local Wi-Fi browser portal. The Wi-Fi portal runs on the Mac; the Android phone only needs a browser and camera/QR scanner.

### Do I need USB debugging for Android file transfer?

No for USB MTP. USB debugging is only needed when using ADB.

### Can I transfer files from iPhone to Mac with SwitchBoard?

The current build supports upload and download through the same local browser portal on iPhone and iPad. It does not provide direct iOS storage browsing, a native iOS companion app, or iOS folder sync.

### Where are Wi-Fi uploads saved?

Received portal uploads are saved under `~/Downloads/Transfer Hub` on the Mac.

## Related guides

- [Fix Android USB/MTP detection on Mac](android-mtp-not-working-on-mac.md)
- [Transfer files over local Wi-Fi](transfer-files-android-mac-wifi.md)
- [Sync folders between Android devices](sync-folders-between-android-devices.md)
