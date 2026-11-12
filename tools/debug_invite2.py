import sys, tempfile
sys.path.insert(0, 'tools')
from db_harness import DB, apply_migrations
srv, db = DB.start(data_dir=tempfile.mkdtemp(prefix='ib_dbg4_'))
apply_migrations(db.conn)
owner=db.make_user('+919000000001','Owner'); staff=db.make_user('+919000000003','Ravi')
db.privileged(); db.execute("update profiles set role='OWNER' where id=%s",(owner,))
db.as_user(owner)
inv=db.call('owner_create_staff_invite','+919000000003','OWN_DELIVERY_STAFF','Ravi Kumar',None,False)
db.as_user(staff)
print(db.call('redeem_staff_invite', inv['activation_code']))
db.conn.close()
