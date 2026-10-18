# Android phone not showing on Mac over USB? Fix MTP detection

If your Android phone is not showing up on your Mac, SwitchBoard, or another file browser, the most common causes are a charge-only USB cable, a locked phone, or Android still using **Charging** instead of **File transfer** mode. Work through these checks in order.

## 1. Check the cable and USB port

- Use a cable that supports data transfer. Some USB cables only charge.
- Connect directly to the Mac when possible; temporarily remove hubs and adapters.
- Try another USB port and another known data-capable cable.
- Unlock the phone after connecting it.

## 2. Change Android USB mode to File transfer

Open the USB notification on Android and select **File transfer**, **Transferring files**, or the equivalent option shown by the phone. Names vary by Android version and manufacturer. MTP file browsing does not require USB debugging.

After changing the mode, open SwitchBoard's **Devices** page and scan for the phone again. If a permission or connection prompt appears on the phone, accept it.

## 3. Check the MTP helper

SwitchBoard uses the OpenMTP command-line helper for USB MTP. If the app says the helper is unavailable, install OpenMTP or rebuild the app with OpenMTP available at `/Applications/OpenMTP.app`. The helper is Intel-based; Apple silicon Macs may need Rosetta to run it.

If the app reports that MTP did not respond, keep the phone unlocked and in File transfer mode, disconnect and reconnect the cable, then retry the scan. Some phones stop exposing storage while locked or after a USB-mode change.

## 4. Try ADB as an alternative

If MTP is unavailable or unreliable on your phone, ADB is another USB transfer method:

1. Install Android SDK Platform-Tools so the `adb` command is available.
2. Enable **Developer options → USB debugging** on the phone.
3. Connect and unlock the phone, then accept the prompt authorizing this Mac.
4. In Transfer Hub, refresh devices. Use **Locate adb** if the app cannot find the Platform-Tools installation.

ADB requires a one-time authorization and is optional; MTP does not require developer settings. See [the complete Android-to-Mac transfer guide](android-file-transfer-to-mac.md).

## 5. Know the current MTP limitations

MTP is implemented through a helper process, so available behavior depends on that helper and the phone. In this early-access build, MTP is shown as a generic USB device because the helper does not expose a stable serial number. It is therefore not possible to reliably distinguish multiple MTP-only phones in the remembered-device list. MTP retries restart the current file where the helper does not support safe partial-file resume.

For resumable transfers where supported, try ADB or the Wi-Fi browser upload flow. For Wi-Fi issues, see [Android-to-Mac Wi-Fi transfer troubleshooting](transfer-files-android-mac-wifi.md).

## Quick checklist

- Phone is unlocked.
- USB mode is **File transfer**, not **Charging**.
- Cable supports data, and a direct Mac port has been tried.
- MTP helper is present and can launch (Rosetta may be needed on Apple silicon).
- After switching to ADB: Platform-Tools are installed and this Mac is authorized on the phone.
