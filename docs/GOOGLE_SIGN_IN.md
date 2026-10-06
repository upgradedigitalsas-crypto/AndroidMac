# Signing in to Google on the emulator

If Google sign-in fails ("Couldn't sign in", "There was a problem communicating
with Google servers", or a silent loop back to the account screen), work through
these in order. Most emulators only need steps 1–3.

## 1. You must be on a Play Store image
`AndroidMac` installs `system-images;android-<latest>;google_apis_playstore;arm64-v8a`,
which is correct. A plain `google_apis` image has no Play Store and cannot sign in.
Confirm the Play Store app is present in the launcher.

## 2. DNS (handled automatically)
The emulator now launches with `-dns-server 8.8.8.8,8.8.4.4`. Inheriting a
split-tunnel VPN or corporate resolver is the most common cause of the
"communicating with Google servers" error. If you're on a VPN that blocks
`8.8.8.8`, disconnect it or change the servers in `AndroidConfig.emulatorLaunchArgs`.

## 3. Cold boot once, then update Play services
A half-initialized Play Services (from a stale snapshot) blocks sign-in.

- In `AndroidMac`, press **STOP ANDROID**, then **START ANDROID** again, or
- From a terminal: `~/Library/Android/sdk/emulator/emulator -avd Antigravity_Phone -no-snapshot-load`

Open the Play Store and let it sit for a minute so it can self-update before you
add an account. Check **Settings → System → Date & time → Set automatically** is on.

## 4. Register the device (Play Protect certification)
If you see "This device isn't Play Protect certified" or sign-in still fails:

1. In `AndroidMac`, click **Register device** in the Google sign-in row. It opens
   <https://www.google.com/android/uncertified> and tries to read the ID.
2. If no ID appears, get it from the emulator: open the Phone/Dialer and dial
   `*#*#8255#*#*` to open GTalk Service Monitor — the `aid` value is the GSF ID
   (it may be hex; convert to decimal before submitting).
3. Paste the ID on that Google page while signed in to the Google account you
   want to use, and submit.
4. Wait ~5 minutes, then click **Reset & reboot** in `AndroidMac` (clears
   `com.google.android.gsf.login` + Play Store data and reboots).
5. Add the account again.

## 4b. It's asking for a passkey / "Scan this QR code"

The emulator has **no real Bluetooth**, so the hybrid passkey flow (scan the QR
with your phone, confirm over BLE proximity) can't complete — and enabling the
emulator's virtual Bluetooth doesn't help, because that's emulator-to-emulator
only, not host or real devices.

Use a different second factor instead:

- On the passkey screen, click **Try another way** →
  - **Enter your password**, or
  - **Get a verification code** (SMS / Google Authenticator) and type the 6 digits
    with your Mac keyboard, or
  - **Tap Yes on your phone** (Google prompt) — this is a push over the internet
    and needs no Bluetooth.
- If the account has *only* passkeys registered, add a password or an authenticator
  app to it temporarily at <https://myaccount.google.com/security>.

## 5. Still stuck
- Recreate the AVD (delete `~/.android/avd/Antigravity_Phone.avd*`, relaunch the
  app) to get a clean image, then repeat 3–4.
- Try a slightly older API level by setting `AndroidConfig.preferredAPILevel` and
  removing the dynamic resolver bump — brand-new platform images occasionally
  ship before their Play services are fully rolled out.
