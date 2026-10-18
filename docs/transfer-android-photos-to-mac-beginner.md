# Move photos and files from Android to Mac: a beginner-friendly guide

Want to copy your Android photos to a Mac without learning technical terms? This guide walks through the simplest option: connect your phone with a USB cable, tap **File transfer**, and save the files you choose. You can copy several photos at once. Saving a copy to the Mac does not delete the originals from your phone.

The app is called **Transfer Hub** on your Mac. It is the macOS app for the SwitchBoard project. You do not need to install anything on your Android phone.

## Before you begin

- Install Transfer Hub from the [SwitchBoard download page](https://github.com/adityarajpt/SwitchBoard/releases/latest). This early-access version needs macOS 14 or later and an Apple silicon Mac.
- Have your Android phone and a USB cable nearby. Some cables only charge the phone; if the phone never appears, try a different cable.
- Keep the phone unlocked while you connect and copy files.

If macOS warns that it cannot verify the app, that is because this early build has not been notarized by Apple. The [installation instructions](../README.md#installing-the-non-notarized-build) explain how to open it if you trust that you downloaded it from the official SwitchBoard release.

## Copy photos from your Android phone to your Mac with a cable

1. Plug the phone into the Mac.
2. Unlock the phone and look for a notification about USB or charging. Tap it. If it offers USB choices, choose **File transfer** or **Transferring files**. The wording varies by phone. If you do not see a notification, skip to [the quick fixes](#if-your-phone-does-not-show-up).
3. Open **Transfer Hub** on the Mac.
4. Click **Devices** on the left, then **Scan for phone** or **Scan USB**.
5. When your phone appears, select it. To find camera pictures, open the **DCIM** folder, then **Camera**. Pictures from messaging apps may be in **Pictures** or **Download**.
6. Click the small circle beside each photo or file you want. To choose every file currently shown, click **Select all**.
7. Click **Save selected** or **Save to Mac**, then choose where on your Mac to put the copies. A good first choice is **Downloads** or **Pictures**.

To check a photo before copying it, click its eye-shaped preview button. You can select multiple files and save them together.

![Transfer Hub connection screen](images/transfer-endpoints.jpg)

## If your phone does not show up

Try these simple fixes one at a time:

1. Unlock the phone and leave its screen on.
2. Unplug the cable, plug it back in, and check the phone for a USB notification. Choose **File transfer** if it appears.
3. Try another cable. A cable that charges the phone may still not carry files.
4. Try another USB port on the Mac. If you are using a USB adapter or hub, connect directly if possible.
5. In Transfer Hub, click **Scan USB** again.

You do **not** need to enable Developer options or USB debugging for the regular cable method. If it still will not connect, see the [step-by-step USB troubleshooting guide](android-mtp-not-working-on-mac.md), or use the [wireless beginner guide](share-files-android-mac-without-cable-beginner.md).

## Transfer without a cable

You can use your phone's web browser instead. The Mac and phone need to be connected to the same home Wi-Fi network. Open **Shared** in Transfer Hub, start sharing, then scan the QR code with your phone's camera. The phone's browser opens a page where you can choose files to send. Follow the [plain-language Wi-Fi guide](share-files-android-mac-without-cable-beginner.md) for all the steps.

## Common questions

### Will copying photos delete them from my phone?

No. **Save to Mac** makes a copy on the Mac. It leaves the original photo on the phone.

### Can I copy lots of photos at once?

Yes. Click the circle beside each item, or choose **Select all**, then click **Save selected**.

### Where should I look for my photos?

On many Android phones, camera photos are in **DCIM → Camera**. Photos saved by other apps may be in **Pictures**, **Movies**, or **Download**.

### Do I have to pay for cloud storage or create an account?

No cloud account is needed to copy files directly over USB or through the local Wi-Fi sharing page. Your Wi-Fi transfer goes to the Mac running Transfer Hub, not to a SwitchBoard cloud account.

## Want more detail?

- [Full Android-to-Mac transfer guide](android-file-transfer-to-mac.md)
- [USB connection troubleshooting](android-mtp-not-working-on-mac.md)
- [Wi-Fi transfer in plain language](share-files-android-mac-without-cable-beginner.md)
