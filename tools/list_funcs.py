import pgserver, tempfile, os, psycopg
srv = pgserver.get_server(os.path.join(tempfile.gettempdir(), "ib_pg_validation"), cleanup_mode="stop")
conn = psycopg.connect(srv.get_uri(), autocommit=True)
cur = conn.cursor()
cur.execute("""select p.proname, pg_get_function_identity_arguments(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' order by 1""")
for name,args in cur.fetchall(): print(f"{name}({args})")
conn.close()
