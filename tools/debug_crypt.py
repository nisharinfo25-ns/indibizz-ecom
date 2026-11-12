import sys, tempfile
sys.path.insert(0, 'tools')
from db_harness import DB
srv, db = DB.start(data_dir=tempfile.mkdtemp(prefix='ib_dbg2_'))
for sql in ["select '$shim$abc$' like '$shim$%$'", "select extensions.crypt('ABC', '$shim$abc$')", "select extensions.gen_salt('bf',8) like '$shim$%$'"]:
    try: print(sql, '=>', db.one(sql))
    except Exception as e: print('ERR',e)
db.conn.close()
