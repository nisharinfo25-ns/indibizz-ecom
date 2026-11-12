"""Shared embedded-PostgreSQL harness for IndiaBizz SQL/RLS integration tests."""
from __future__ import annotations

import os
import re
import tempfile
from pathlib import Path

import pgserver
import psycopg
from psycopg.types.json import Jsonb

ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS = ROOT / "supabase" / "migrations"
PRELUDE = ROOT / "tools" / "local_prelude.sql"


def apply_migrations(conn: psycopg.Connection) -> None:
    with conn.cursor() as cur:
        cur.execute(PRELUDE.read_text(encoding="utf-8"))
        for path in sorted(MIGRATIONS.glob("*.sql")):
            sql = path.read_text(encoding="utf-8")
            sql = re.sub(
                r"create\s+extension\s+if\s+not\s+exists\s+pgcrypto[^;]*;",
                "-- pgcrypto provided by local shim",
                sql,
                flags=re.IGNORECASE,
            )
            cur.execute(sql)


class DB:
    """Autocommit connection with helpers to impersonate API roles."""

    def __init__(self, conn: psycopg.Connection):
        self.conn = conn
        self.conn.autocommit = True

    def reset(self) -> None:
        with self.conn.cursor() as cur:
            cur.execute("reset role")
            cur.execute(
                "select set_config('request.jwt.claim.sub','',false), "
                "set_config('request.jwt.claim.role','',false), "
                "set_config('indibizz.privileged','off',false)"
            )

    def privileged(self) -> None:
        self.reset()
        with self.conn.cursor() as cur:
            cur.execute("select set_config('indibizz.privileged','on',false)")

    def as_user(self, user_id: str) -> None:
        self.reset()
        with self.conn.cursor() as cur:
            cur.execute("set role authenticated")
            cur.execute(
                "select set_config('request.jwt.claim.sub',%s,false), "
                "set_config('request.jwt.claim.role','authenticated',false)",
                (str(user_id),),
            )

    def as_anon(self) -> None:
        self.reset()
        with self.conn.cursor() as cur:
            cur.execute("set role anon")
            cur.execute("select set_config('request.jwt.claim.role','anon',false)")

    def as_service(self) -> None:
        self.reset()
        with self.conn.cursor() as cur:
            cur.execute("set role service_role")
            cur.execute("select set_config('request.jwt.claim.role','service_role',false)")

    def one(self, sql: str, params: tuple = ()):
        with self.conn.cursor() as cur:
            if params:
                cur.execute(sql, params)
            else:
                cur.execute(sql)
            row = cur.fetchone()
            return row[0] if row else None

    def row(self, sql: str, params: tuple = ()):
        with self.conn.cursor() as cur:
            if params:
                cur.execute(sql, params)
            else:
                cur.execute(sql)
            return cur.fetchone()

    def rows(self, sql: str, params: tuple = ()):
        with self.conn.cursor() as cur:
            if params:
                cur.execute(sql, params)
            else:
                cur.execute(sql)
            return cur.fetchall()

    def execute(self, sql: str, params: tuple = ()):
        with self.conn.cursor() as cur:
            if params:
                cur.execute(sql, params)
            else:
                cur.execute(sql)
            return cur.rowcount

    def call(self, fn: str, *args):
        placeholders = ", ".join(["%s"] * len(args))
        return self.one(f"select public.{fn}({placeholders})", args)

    def make_user(self, phone: str, full_name: str = "") -> str:
        self.privileged()
        return self.one(
            "insert into auth.users (phone, raw_user_meta_data) values (%s, %s) returning id",
            (phone, Jsonb({"full_name": full_name})),
        )

    @staticmethod
    def start(data_dir: str | None = None, cleanup_mode: str = "delete"):
        data_dir = data_dir or os.path.join(tempfile.gettempdir(), "ib_pg_integration")
        srv = pgserver.get_server(data_dir, cleanup_mode=cleanup_mode)
        conn = psycopg.connect(srv.get_uri(), autocommit=True)
        return srv, DB(conn)
