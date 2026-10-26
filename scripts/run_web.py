"""Build the real Flutter app for local browser use, then serve it with its backend.

Only public Supabase config is passed to Flutter. Server secrets stay in .env.
Requires Flutter on PATH or the project-local .sdk/flutter installation.
"""

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path

from dotenv import dotenv_values

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8001)
    parser.add_argument("--no-build", action="store_true")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        raise SystemExit("Choose a local port between 1024 and 65535.")
    if not args.no_build:
        local = ROOT / ".sdk/flutter/bin" / ("flutter.bat" if os.name == "nt" else "flutter")
        flutter = str(local) if local.is_file() else shutil.which("flutter")
        if not flutter:
            raise SystemExit("Flutter SDK not found.")
        values = dotenv_values(ROOT / ".env")
        required = ("SUPABASE_URL", "SUPABASE_ANON_KEY")
        if any(not values.get(key) for key in required):
            raise SystemExit("Public Supabase settings are missing in .env.")
        # Explicit allowlist. Never pass the entire .env to a client build.
        config = {key: values[key] for key in required}
        config.update(
            {"API_URL": f"http://127.0.0.1:{args.port}", "ALLOW_INSECURE_LOCAL_DEV": "true"}
        )
        defines = ROOT / "mobile/.dart-defines.local.json"
        defines.write_text(json.dumps(config), encoding="utf-8")
        subprocess.run(
            [flutter, "--no-version-check", "pub", "get"], cwd=ROOT / "mobile", check=True
        )
        subprocess.run(
            [
                flutter,
                "--no-version-check",
                "build",
                "web",
                "--base-href=/app/",
                "--no-web-resources-cdn",
                f"--dart-define-from-file={defines}",
            ],
            cwd=ROOT / "mobile",
            check=True,
        )
    if not (ROOT / "mobile/build/web/index.html").is_file():
        raise SystemExit("Web build missing. Run without --no-build first.")
    print(f"Open the app: http://127.0.0.1:{args.port}/app/", flush=True)
    subprocess.run(
        [
            os.sys.executable,
            "-m",
            "uvicorn",
            "backend.api.app:app",
            "--env-file",
            str(ROOT / ".env"),
            "--host",
            "127.0.0.1",
            "--port",
            str(args.port),
            "--workers",
            "1",
            "--ws-max-size",
            "500000",
            "--ws-max-queue",
            "1",
            "--no-access-log",
        ],
        cwd=ROOT,
        check=True,
    )


if __name__ == "__main__":
    main()
