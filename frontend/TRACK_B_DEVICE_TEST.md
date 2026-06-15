# Track B — Mobile Anti-Capture Verification Checklist

This is a manual verification plan to test the anti-capture and anti-exfiltration protections on an Android device or emulator.

## Prerequisites
- A physical Android device or emulator
- Android Debug Bridge (`adb`) installed and connected

## 1. Screenshot Prevention
**Steps:**
1. Open the Aegis Secure Messenger app and navigate to a chat room or open a secure media attachment.
2. Attempt to take a screenshot using the device's hardware buttons (e.g., Power + Volume Down).
**Expected Result:**
- The screenshot should be blocked by the OS.
- You should see a system toast/notification indicating that taking screenshots is not allowed by the app.
**Result:** [ ] PASS / [ ] FAIL

## 2. Screen Recording Prevention
**Steps:**
1. Start a screen recording using the device's built-in screen recorder or a third-party app.
2. Open the Aegis Secure Messenger app and navigate through chats and media.
3. Stop the recording and view the recorded video.
**Expected Result:**
- The recorded video should show black or blocked frames whenever the Aegis app was in the foreground.
**Result:** [ ] PASS / [ ] FAIL

## 3. App Switcher / Recent Apps Security
**Steps:**
1. Open the Aegis Secure Messenger app.
2. Swipe up or press the "Recent Apps" button to enter the app switcher view.
**Expected Result:**
- The app's preview card in the switcher should be blank, black, or otherwise obscured (thanks to `FLAG_SECURE`).
**Result:** [ ] PASS / [ ] FAIL

## 4. Watermark Overlay Visibility
**Steps:**
1. Open a secure media file or enter a screen where `SecureScreen` / `WatermarkOverlay` is used.
**Expected Result:**
- A faint repeating watermark displaying the user's identifier (e.g., `TEST-USER-123`) should be tiled diagonally across the entire screen over the content.
**Result:** [ ] PASS / [ ] FAIL

## 5. Root/Jailbreak Detection Handling
**Steps:**
1. Install and run the app on a known rooted device or an emulator (which may trigger the developer mode/root checks).
2. Open the debug diagnostics view (`Profile Dashboard` -> `Bug Icon` if in debug mode).
**Expected Result:**
- The "Device Integrity" check should report "Compromised (Rooted/Jailbroken)".
- The app should correctly restrict secure media actions based on this status.
**Result:** [ ] PASS / [ ] FAIL

## 6. Zero-Disk-Persistence Verification
**Steps:**
1. Open the app and view a decrypted secure media file.
2. Keep the app open. Connect the device to your computer.
3. Run the following `adb` command to inspect the app's private storage (cache and files directories):
   ```bash
   adb shell "run-as com.ibemcom.aegis_chat ls -R files cache"
   ```
4. Look for any plaintext media files (e.g., `.jpg`, `.mp4`) that you just viewed.
**Expected Result:**
- NO plaintext media files should be found on disk. Decrypted bytes must exist only in memory and be zeroed upon disposal.
**Result:** [ ] PASS / [ ] FAIL
