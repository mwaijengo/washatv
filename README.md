# washa

Flutter client/admin project with a Node.js + PostgreSQL backend (`backend/`) for Railway deployment.

## Admin app (device)

Build/run from `admin/` so the APK stays lightweight (avoids “App isn’t responding” from video/Firebase plugins):

```bash
cd admin && ./run_android.sh
# or
cd admin && ./build_apk.sh && adb install -r build/app/outputs/flutter-apk/app-release.apk
```

See `admin/README.md`.
