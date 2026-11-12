import pgserver, tempfile, os, psycopg
srv = pgserver.get_server(os.path.join(tempfile.gettempdir(), "ib_pg_integration"), cleanup_mode="stop")
conn = psycopg.connect(srv.get_uri(), autocommit=True)
cur=conn.cursor()
try:
    cur.execute("select now() at time zone 'Asia/Kolkata'")
    print(cur.fetchone())
except Exception as e:
    print("AT TZ ERROR", e)
try:
    cur.execute("set timezone='Asia/Kolkata'")
    print("set ok")
except Exception as e:
    print("SET ERROR", e)
conn.close()
