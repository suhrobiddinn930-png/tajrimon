"""Generate SDK-owned runners without overwriting the handwritten application.

Run from repository root with Flutter on PATH. Works on Windows/macOS/Linux.
The temporary scaffold is retained (gitignored) so no recursive delete is needed.
"""

import os
import plistlib
import re
import shutil
import subprocess
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / "mobile"
SCAFFOLD = ROOT / ".platform-scaffold"


def main():
    local = ROOT / ".sdk/flutter/bin" / ("flutter.bat" if os.name == "nt" else "flutter")
    flutter = str(local) if local.is_file() else shutil.which("flutter")
    if not flutter:
        raise SystemExit("Install Flutter stable and add flutter to PATH first.")
    if any((MOBILE / platform).exists() for platform in ("android", "ios")):
        raise SystemExit("Runners already exist. Refusing to overwrite native project changes.")
    subprocess.run(
        [
            flutter,
            "create",
            "--platforms=android,ios",
            "--org=com.ailivetranslator",
            "--project-name=ai_live_translator",
            "--no-pub",
            str(SCAFFOLD),
        ],
        check=True,
    )
    for platform in ("android", "ios"):
        shutil.copytree(SCAFFOLD / platform, MOBILE / platform)
    ns = "http://schemas.android.com/apk/res/android"
    ET.register_namespace("android", ns)
    manifest = MOBILE / "android/app/src/main/AndroidManifest.xml"
    tree = ET.parse(manifest)
    root = tree.getroot()
    for permission in [
        "INTERNET",
        "RECORD_AUDIO",
        "MODIFY_AUDIO_SETTINGS",
        "BLUETOOTH_CONNECT",
        "CAMERA",
    ]:
        ET.SubElement(
            root, "uses-permission", {f"{{{ns}}}name": f"android.permission.{permission}"}
        )
    application = root.find("application")
    application.set(f"{{{ns}}}label", "AI Live Translator")
    activity = application.find("activity")
    # supabase_flutter/app_links owns OAuth/recovery deep links.
    ET.SubElement(
        activity,
        "meta-data",
        {f"{{{ns}}}name": "flutter_deeplinking_enabled", f"{{{ns}}}value": "false"},
    )
    intent = ET.SubElement(activity, "intent-filter")
    ET.SubElement(intent, "action", {f"{{{ns}}}name": "android.intent.action.VIEW"})
    for category in ("DEFAULT", "BROWSABLE"):
        ET.SubElement(intent, "category", {f"{{{ns}}}name": f"android.intent.category.{category}"})
    ET.SubElement(
        intent, "data", {f"{{{ns}}}scheme": "ai.live.translator", f"{{{ns}}}host": "auth-callback"}
    )
    tree.write(manifest, encoding="utf-8", xml_declaration=True)
    for name in ("build.gradle.kts", "build.gradle"):
        gradle = MOBILE / "android/app" / name
        if gradle.exists():
            text = gradle.read_text(encoding="utf-8")
            text = text.replace("minSdk = flutter.minSdkVersion", "minSdk = 23")
            text = text.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 23")
            gradle.write_text(text, encoding="utf-8")
    info_path = MOBILE / "ios/Runner/Info.plist"
    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
    info.update(
        {
            "CFBundleDisplayName": "AI Live Translator",
            "NSMicrophoneUsageDescription": "Translate your speech for your conversation partner.",
            "NSCameraUsageDescription": "Scan your partner’s invitation QR code.",
            "NSBluetoothAlwaysUsageDescription": "Play translations through connected headphones.",
            "FlutterDeepLinkingEnabled": False,
            "CFBundleURLTypes": [{"CFBundleURLSchemes": ["ai.live.translator"]}],
        }
    )
    with info_path.open("wb") as stream:
        plistlib.dump(info, stream)
    project = MOBILE / "ios/Runner.xcodeproj/project.pbxproj"
    project.write_text(
        re.sub(
            r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;",
            "IPHONEOS_DEPLOYMENT_TARGET = 15.5;",
            project.read_text(),
        ),
        encoding="utf-8",
    )
    podfile = MOBILE / "ios/Podfile"
    if podfile.exists():
        podfile.write_text(
            re.sub(r"#?\s*platform :ios, '[0-9.]+'", "platform :ios, '15.5'", podfile.read_text()),
            encoding="utf-8",
        )
    print(
        "Created mobile/android and mobile/ios. Next: cd mobile; "
        "flutter pub get; flutter analyze; flutter test"
    )


if __name__ == "__main__":
    main()
