import sys, tempfile
sys.path.insert(0, 'tools')
from db_harness import DB, apply_migrations
srv, db = DB.start(data_dir=tempfile.mkdtemp(prefix='ib_dbg3_'))
apply_migrations(db.conn)
print("pattern", db.one("select '$shim$abc$' like '$shim$%$'"))
print("gen matches", db.one("select extensions.gen_salt('bf',8) like '$shim$%$'"))
print("crypt", db.one("select extensions.crypt('ABC', '$shim$abc$')"))
db.conn.close()
