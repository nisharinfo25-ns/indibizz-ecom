import pgserver, tempfile, os, psycopg
srv = pgserver.get_server(os.path.join(tempfile.gettempdir(), "ib_pg_validation"), cleanup_mode="stop")
conn = psycopg.connect(srv.get_uri(), autocommit=True)
cur = conn.cursor()
cur.execute("select tablename from pg_tables where schemaname='public' order by 1")
print('\n'.join(r[0] for r in cur.fetchall()))
conn.close()
