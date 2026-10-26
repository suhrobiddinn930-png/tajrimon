"""Download verified Android CLI/JDK archives into ignored project-local .sdk.

Does not change global PATH or accept Android SDK licenses. Run sdkmanager --licenses
after reviewing Google's terms, then install the packages reported by Flutter doctor.
"""

import hashlib
import shutil
import urllib.request
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / ".sdk"


def download(url, target, checksum, algorithm="sha256"):
    if target.is_file():
        with target.open("rb") as stream:
            if hashlib.file_digest(stream, algorithm).hexdigest() == checksum:
                return
    print("Downloading", target.name, flush=True)
    with urllib.request.urlopen(url, timeout=120) as response, target.open("wb") as output:
        shutil.copyfileobj(response, output)
    with target.open("rb") as stream:
        actual = hashlib.file_digest(stream, algorithm).hexdigest()
    if actual != checksum:
        raise RuntimeError(f"Checksum mismatch: {target.name}")


def main():
    SDK.mkdir(exist_ok=True)
    java = SDK / "java"
    if not (java / "bin/java.exe").is_file():
        url = "https://aka.ms/download-jdk/microsoft-jdk-21-windows-x64.zip"
        with urllib.request.urlopen(url + ".sha256sum.txt", timeout=60) as response:
            checksum = response.read().decode().split()[0]
        archive = SDK / "jdk21.zip"
        download(url, archive, checksum)
        with zipfile.ZipFile(archive) as source:
            folder = source.namelist()[0].split("/")[0]
            source.extractall(SDK / "java-extract")
        shutil.copytree(SDK / "java-extract" / folder, java, dirs_exist_ok=True)
    android = SDK / "android"
    if not (android / "cmdline-tools/19.0/bin/sdkmanager.bat").is_file():
        with urllib.request.urlopen(
            "https://dl.google.com/android/repository/repository2-1.xml", timeout=60
        ) as response:
            repository = ET.fromstring(response.read())
        # The Java-based manager avoids native self-extraction on restricted Windows hosts.
        package = next(p for p in repository if p.get("path") == "cmdline-tools;19.0")
        archive = next(
            a for a in package.findall("archives/archive") if a.findtext("host-os") == "windows"
        )
        complete = archive.find("complete")
        target = SDK / "android-cli19.zip"
        checksum = complete.find("checksum")
        download(
            "https://dl.google.com/android/repository/" + complete.findtext("url"),
            target,
            checksum.text,
            checksum.get("type", "sha1"),
        )
        with zipfile.ZipFile(target) as source:
            source.extractall(SDK / "android-cli19-extract")
        shutil.copytree(
            SDK / "android-cli19-extract/cmdline-tools",
            android / "cmdline-tools/19.0",
            dirs_exist_ok=True,
        )
    print("Verified JDK:", java)
    print("Android SDK:", android)
    print("Next: set JAVA_HOME, ANDROID_HOME; review sdkmanager --licenses.")


if __name__ == "__main__":
    main()
