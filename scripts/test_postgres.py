"""Test migrations/RLS using an isolated PostgreSQL cluster with a minimal Supabase Auth shim.

Requires PostgreSQL bin directory and psycopg on PYTHONPATH. Never connects to an existing database.
The shim covers auth.uid()/auth.jwt()/roles, not Supabase Auth or Realtime services.
"""

import argparse
import os
import socket
import subprocess
from pathlib import Path
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]

SHIM = """
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
grant usage on schema auth to anon, authenticated, service_role;
create table auth.users(id uuid primary key, email text);
create function auth.jwt() returns jsonb language sql stable as
$$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as
$$ select (auth.jwt()->>'sub')::uuid $$;
create publication supabase_realtime;
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin", required=True, type=Path)
    args = parser.parse_args()
    import psycopg

    cluster = ROOT / ".test-postgres" / uuid4().hex
    cluster.mkdir(parents=True)
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    startupinfo = None
    if os.name == "nt":
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startupinfo.wShowWindow = subprocess.SW_HIDE

    def pg(name, *values):
        # On Windows pg_ctl children can inherit pipe handles. Use a file, not PIPE.
        log = cluster / f"{name}.log"
        with log.open("w", encoding="utf-8") as output:
            result = subprocess.run(
                [str(args.bin / name), *map(str, values)],
                check=True,
                startupinfo=startupinfo,
                stdout=output,
                stderr=subprocess.STDOUT,
            )
        result.stdout = log.read_text(encoding="utf-8", errors="replace")
        return result

    print(
        pg(
            "initdb",
            "-D",
            cluster / "data",
            "-U",
            "postgres",
            "-A",
            "trust",
            "--encoding=UTF8",
            "--locale=C",
        ).stdout
    )
    started = False
    try:
        print(
            pg(
                "pg_ctl",
                "-D",
                cluster / "data",
                "-l",
                cluster / "postgres.log",
                "-o",
                f"-p {port} -h 127.0.0.1 -c wal_level=logical",
                "-w",
                "start",
            ).stdout
        )
        started = True
        dsn = f"postgresql://postgres@127.0.0.1:{port}/postgres"
        with psycopg.connect(dsn, autocommit=True) as conn:
            conn.execute(SHIM)
            for migration in sorted((ROOT / "supabase/migrations").glob("*.sql")):
                conn.execute(migration.read_text(encoding="utf-8"))
                print("Applied", migration.name)
        env = {**os.environ, "TEST_DATABASE_URL": dsn}
        result = subprocess.run(
            [
                os.sys.executable,
                "-m",
                "pytest",
                "-q",
                "-m",
                "integration",
                "--tb=short",
                "-p",
                "no:cacheprovider",
            ],
            cwd=ROOT,
            env=env,
        )
        raise SystemExit(result.returncode)
    finally:
        if started:
            print(pg("pg_ctl", "-D", cluster / "data", "-m", "fast", "-w", "stop").stdout)


if __name__ == "__main__":
    main()
