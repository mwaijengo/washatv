# WASHA Admin

Lightweight Flutter admin for WASHA TV. **Build and run from this folder** so the APK does not pull in the viewer’s video/Firebase plugins (those caused “App isn’t responding” on device).

## Quick start (Android device)

```bash
cd admin
./run_android.sh
```

Or build an installable APK:

```bash
cd admin
./build_apk.sh
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Login with your admin email/password (JWT is saved on the device). Optional: set `WASHA_ADMIN_API_KEY` in `dev_defines.json` to skip login for CI/release builds only.

## Chrome / desktop

```bash
cd admin
./run_admin_chrome.sh
```

## Config

Copy `dev_defines.json.example` → `dev_defines.json` if missing:

```json
{
  "WASHA_API_BASE_URL": "https://washatv-production.up.railway.app",
  "WASHA_ADMIN_API_KEY": ""
}
```

## Do not

Do **not** ship admin by running `flutter run -t lib/main_admin.dart` from the **repo root** onto a phone — that embeds the full viewer plugin set and can ANR. Root `main_admin.dart` is fine for Chrome/desktop only.
