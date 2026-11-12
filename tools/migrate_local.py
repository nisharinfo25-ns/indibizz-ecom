"""Apply IndiaBizz migrations to an embedded PostgreSQL for validation.

Usage: python tools/migrate_local.py [--keep]
Creates a throwaway cluster under the temp directory, installs Supabase
compatibility shims, then applies supabase/migrations/*.sql in filename order.
Exits non-zero on the first failing migration and prints the offending file.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
from pathlib import Path

import pgserver
import psycopg

ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS = ROOT / "supabase" / "migrations"
PRELUDE = ROOT / "tools" / "local_prelude.sql"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--keep", action="store_true", help="keep the data directory")
    parser.add_argument("--db", default=None, help="reuse an existing pgserver data dir")
    args = parser.parse_args()

    data_dir = args.db or os.path.join(tempfile.gettempdir(), "ib_pg_validation")
    cleanup = "stop" if args.keep else "delete"
    srv = pgserver.get_server(data_dir, cleanup_mode=cleanup)
    conn = psycopg.connect(srv.get_uri(), autocommit=True)
    try:
        with conn.cursor() as cur:
            if args.db:
                # Fresh application schema for repeated runs.
                cur.execute("drop schema if exists app_private cascade")
                for table in ("public",):
                    cur.execute(f"drop schema if exists {table} cascade")
                cur.execute("create schema public")
                cur.execute("grant all on schema public to postgres")
                cur.execute("grant usage on schema public to anon, authenticated, service_role")
            cur.execute(PRELUDE.read_text(encoding="utf-8"))
            files = sorted(MIGRATIONS.glob("*.sql"))
            for path in files:
                sql = path.read_text(encoding="utf-8")
                sql = re.sub(
                    r"create\s+extension\s+if\s+not\s+exists\s+pgcrypto[^;]*;",
                    "-- pgcrypto provided by local shim",
                    sql,
                    flags=re.IGNORECASE,
                )
                try:
                    cur.execute(sql)
                    print(f"OK   {path.name}")
                except Exception as exc:  # noqa: BLE001
                    print(f"FAIL {path.name}")
                    print(exc)
                    return 1
        print(f"\nAll {len(files)} migrations applied. URI: {srv.get_uri()}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
