"""Build a debug APK using public settings only; server credentials never enter the APK.

With USB debugging enabled, adb reverse tcp:8001 tcp:8001 connects the default
loopback API URL to scripts/run_web.py on the development PC.
"""

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path
from urllib.parse import urlsplit

from dotenv import dotenv_values

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-url", default="http://127.0.0.1:8001")
    parser.add_argument("--jdk-home", type=Path)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    uri = urlsplit(args.api_url)
    local = uri.scheme == "http" and uri.hostname in ("127.0.0.1", "localhost", "10.0.2.2")
    if not uri.hostname or (uri.scheme != "https" and not local) or uri.username or uri.password:
        raise SystemExit("Use HTTPS or the documented local USB/emulator HTTP addresses.")
    sdk = ROOT / ".sdk"
    flutter = sdk / "flutter/bin" / ("flutter.bat" if os.name == "nt" else "flutter")
    executable = str(flutter) if flutter.is_file() else shutil.which("flutter")
    if not executable:
        raise SystemExit("Flutter SDK not found.")
    if not (ROOT / "mobile/android").is_dir():
        raise SystemExit("Run python scripts/bootstrap_mobile.py first.")
    values = dotenv_values(ROOT / ".env")
    keys = ("SUPABASE_URL", "SUPABASE_ANON_KEY")
    if any(not values.get(key) for key in keys):
        raise SystemExit("Public Supabase settings are missing from .env.")
    config = {key: values[key] for key in keys}
    config.update(API_URL=args.api_url.rstrip("/"), ALLOW_INSECURE_LOCAL_DEV=str(local).lower())
    defines = ROOT / "mobile/.dart-defines.android.local.json"
    defines.write_text(json.dumps(config), encoding="utf-8")
    env = dict(os.environ)
    env.pop("DEBUG", None)  # Gradle's Windows launcher otherwise echoes every build argument.
    if (sdk / "java/bin/java.exe").is_file():
        env["JAVA_HOME"] = str(sdk / "java")
    if args.jdk_home:
        env["JAVA_HOME"] = str(args.jdk_home.resolve())
    if (sdk / "android").is_dir():
        env["ANDROID_HOME"] = str(sdk / "android")
    # Keep build/download caches in the project rather than the user's global profile.
    env["GRADLE_USER_HOME"] = str(sdk / "gradle")
    env["ANDROID_USER_HOME"] = str(sdk / "android-user")
    for arguments in (
        ["pub", "get"],
        [
            "build",
            "apk",
            "--debug",
            f"--dart-define-from-file={defines}",
            *(["--verbose"] if args.verbose else []),
        ],
    ):
        subprocess.run(
            [executable, "--no-version-check", *arguments], cwd=ROOT / "mobile", env=env, check=True
        )
    print("APK:", ROOT / "mobile/build/app/outputs/flutter-apk/app-debug.apk")


if __name__ == "__main__":
    main()
