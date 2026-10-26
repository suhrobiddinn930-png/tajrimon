# Flutter mobile app

Requires Flutter >=3.35 / Dart >=3.9, Android SDK/JDK, and macOS + Xcode for iOS.
See `docs/TEST_RESULTS.md` for executed build checks. Android/iOS device testing is separate
from the local browser build.

## Interface language

The interface opens in Uzbek by default. The language button in every page's top bar offers
O‘zbekcha, English, Русский and Device language. The choice is saved on this browser/device and
takes effect immediately without leaving the current page or clearing form fields. Device language
matches Uzbek, English or Russian and falls back to Uzbek for unsupported device locales.
This setting is separate from the languages selected for speech translation in a room.
UI translations live in `lib/core/translations.dart`; locale selection and persistence are in
`lib/core/localization.dart`. Flutter Material controls use the same selected locale.

## Local browser app

From the repository root, run `python scripts/run_web.py`. It finds Flutter on PATH or in
`.sdk/flutter`, builds this same Flutter application and serves it with FastAPI at
`http://127.0.0.1:8001/app/`. Use `--no-build` to serve an existing build. The browser and API use
the same origin, so no broad CORS exception is needed. Only `SUPABASE_URL`, the public anon key,
the local API URL and a local-development flag are passed into the client build. The entire
server `.env` must never be used as a Dart define file. Browser credentials persist per origin;
use this exact host/port consistently during testing.

For email confirmation/password recovery in the browser, add `http://127.0.0.1:8001/app/` to the
Supabase Auth redirect allowlist. Native callbacks continue to use the app scheme. Bluetooth
pairing/routing in the browser uses browser/system settings; native route discovery is skipped.
The local browser build is not an Android APK or an iOS release. Supabase migrations and valid
OpenAI billing are still required for live room/translation features.

## Android debug APK from Windows

Native Android/iOS runners are now included. Do not rerun the bootstrap over existing runners.
The optional `python scripts/setup_android.py` downloads checksum-verified Microsoft JDK 21
and Java-based Android command-line tools 19.0 into ignored `.sdk/`; it leaves global PATH
unchanged. Set `JAVA_HOME=.sdk/java`, `ANDROID_HOME=.sdk/android`, and
`ANDROID_USER_HOME=.sdk/android-user` using absolute paths. Review/accept SDK licenses and install
`platform-tools`, `platforms;android-36`, `build-tools;36.0.0`, and `ndk;28.2.13676358`
with `.sdk/android/cmdline-tools/19.0/bin/sdkmanager.bat`.

Run `python scripts/build_android.py` from the repository root. It builds a **debug** APK using
an explicit allowlist of public `.env` settings and project-local Java/SDK/Gradle caches.
The checked-in Gradle settings limit the heap to 2 GB and use two workers, with a separate
768 MB Kotlin daemon limit, to keep builds practical on an 8 GB development PC. Initial builds
can download additional Android SDK/CMake packages and require internet access.
The default API is `http://127.0.0.1:8001`; start `python scripts/run_web.py --no-build`
on the PC, enable USB debugging on the phone, then run:

```powershell
.\.sdk\android\platform-tools\adb.exe devices
.\.sdk\android\platform-tools\adb.exe reverse tcp:8001 tcp:8001
.\.sdk\android\platform-tools\adb.exe install -r mobile/build/app/outputs/flutter-apk/app-debug.apk
```

Approve the USB debugging prompt on your phone. Reapply `adb reverse` after reconnecting USB.
Both the phone and PC need internet access to Supabase. If two phones are attached, use
`adb -s SERIAL reverse tcp:8001 tcp:8001` and `adb -s SERIAL install -r ...` for each serial
listed by `adb devices`.
For an emulator use `python scripts/build_android.py --api-url http://10.0.2.2:8001`.
For a hosted API use `--api-url https://YOUR_API_HOST`. Local cleartext exceptions are limited
to loopback/emulator hosts in the debug manifest; release builds retain HTTPS requirements.
Debug signing is for testing. Store signing, a public HTTPS deployment and physical-device
audio acceptance remain separate release steps.

From repository root:

```powershell
python scripts/bootstrap_mobile.py
cd mobile
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_KEY --dart-define=API_URL=https://YOUR_API_HOST
```

Use the public `anon` JWT key for current server configuration; `service_role` is server only.
The bootstrap generates SDK-owned Android/iOS runners in an ignored temporary folder, copies only
the runners, adds microphone/camera/Bluetooth declarations, auth callback schemes and platform
minimums (Android 23 / iOS 15.5). It refuses to overwrite existing runners. Inspect the generated
projects and commit them after a successful build. Android's Bluetooth connect runtime permission
is requested; pairing is performed in system settings. No foreground/background recording service.

Supabase Auth must allow `ai.live.translator://auth-callback/` for signup and password recovery.
Production should move to verified app/universal links to reduce custom-scheme interception.
The QR scanner requests camera access only when opened. Microphone access is requested when speaking.

Local emulator development: API `http://10.0.2.2:8000` on Android, `http://127.0.0.1:8000` on iOS.
Use `--dart-define=ALLOW_INSECURE_LOCAL_DEV=true` **only** in local debug builds and add a debug-only
Android cleartext network configuration or iOS ATS localhost exception if needed. Physical phones
need a reachable LAN address or trusted HTTPS endpoint; their `localhost` is not your PC.
Release builds require HTTPS; never ship debug cleartext exceptions.

```powershell
flutter build apk --debug --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=API_URL=https://...
flutter build appbundle --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=API_URL=https://...
```

On macOS, configure Signing & Capabilities in `ios/Runner.xcworkspace`, then run
`flutter build ipa --release` with the same public defines. Release signing and store publication
have not been performed. Commit `pubspec.lock` after dependency resolution for reproducible builds.
