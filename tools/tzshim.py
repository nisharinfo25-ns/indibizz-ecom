import pgserver, tempfile, os, psycopg
srv = pgserver.get_server(os.path.join(tempfile.gettempdir(), "ib_pg_integration"), cleanup_mode="stop")
conn = psycopg.connect(srv.get_uri(), autocommit=True)
cur=conn.cursor()
try:
    cur.execute("create or replace view pg_catalog.pg_timezone_names as select 'UTC'::text as name, 'UTC'::text as abbrev, interval '0' as utc_offset, false as is_dst union all select 'Asia/Kolkata','IST', interval '5:30', false")
    cur.execute("select * from pg_catalog.pg_timezone_names")
    print(cur.fetchall())
except Exception as e:
    print("ERROR", e)
conn.close()
