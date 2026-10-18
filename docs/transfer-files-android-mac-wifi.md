# Transfer files from Android to Mac over Wi-Fi

SwitchBoard can transfer files between an Android phone and a Mac over the local network using a browser-based portal. There is no Android app to install: start the portal on the Mac, scan its QR code with the phone, then upload or download selected files in the phone's browser.

## Before you start: connect both devices to the same Wi-Fi

The Mac and phone must be on the same local Wi-Fi network so the phone can reach the portal running on the Mac. A phone using cellular data while the Mac is on Wi-Fi is not on the same network. Guest Wi-Fi, VPN routing, firewall rules, and router **AP/client isolation** can also block device-to-device traffic even when both devices show the same network name.

Use a trusted private network. The portal uses a temporary tokenized HTTP link on the local network, not end-to-end encrypted HTTPS. Anyone who can reach the link while the portal is active may upload files or download files that you explicitly shared. Stop sharing when finished.

## Upload Android files to your Mac

1. Join the Mac and Android phone to the same Wi-Fi network.
2. In Transfer Hub, open **Shared** and select **Start sharing**.
3. Scan the QR code shown on the Mac with the Android camera, or type the displayed address into the phone's browser.
4. In the page that opens, choose the files to upload. The browser reports transfer progress; received files are saved in `~/Downloads/Transfer Hub` on the Mac.
5. Select **Stop portal** in Transfer Hub when done.

Uploads are local to the Mac and are not sent to a cloud service. The browser upload flow can retry from saved chunks when the same file is selected again in the same phone browser.

## Download Mac files to your phone

In Transfer Hub, share the Mac files you want available in the portal's download list. Open or refresh the portal page on the phone and tap a listed file to download it. Only explicitly shared files appear for download.

## If the QR page will not open

1. Confirm both devices are connected to the same Wi-Fi network; disable cellular temporarily while testing.
2. Avoid guest Wi-Fi. Guest networks commonly block communication between connected devices.
3. If both are on the same private network, check whether a VPN is active on either device and temporarily disconnect it for diagnosis.
4. Check the macOS firewall prompt for Transfer Hub and allow the connection on the trusted network.
5. Check the router for **AP isolation**, **client isolation**, or similar settings that prevent Wi-Fi devices from communicating.
6. Stop and restart the portal to generate a fresh link and QR code.

If you need file browsing rather than a browser upload/download page, connect over USB MTP or ADB. The Wi-Fi portal does not make the phone a paired device endpoint in Transfer Hub and cannot be selected for Android-to-Android transfer or folder sync.

## Android and iPhone compatibility

The browser portal can also be opened from an iPhone or iPad browser for basic upload/download. Direct iOS storage browsing, background iOS sync, and a native iOS app are not part of the current build.

For wired Android transfers, see [the Android-to-Mac file transfer guide](android-file-transfer-to-mac.md). For connection setup problems, see [Android USB/MTP troubleshooting](android-mtp-not-working-on-mac.md).
