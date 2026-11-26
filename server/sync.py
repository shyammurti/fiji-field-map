"""Private append-only Fiji trail exchange. Nginx authenticates the key page."""
import hmac,json,math,os,sqlite3,uuid
from pathlib import Path
from urllib.parse import quote
DATA=Path(os.getenv('FIELD_DATA','/mnt/media4/field-map-data'))
MAX=12*1024*1024

def canonical_uuid(v):
    return isinstance(v,str) and str(uuid.UUID(v))==v

def validate(t):
    if not isinstance(t,dict) or not all(canonical_uuid(t[k]) for k in ('id','rev','device')): raise ValueError()
    if t['parent'] is not None and (not canonical_uuid(t['parent']) or t['parent']==t['rev']):raise ValueError()
    if not isinstance(t['name'],str) or not 1<=len(t['name'].strip())<=96:raise ValueError()
    if 'deleted' in t and type(t['deleted']) is not bool:raise ValueError()
    if not all(type(t[k])==int and 0<=t[k]<2**53 for k in ('created','updated')):raise ValueError()
    parts=t['parts']
    if not isinstance(parts,list) or not parts or sum(len(p) for p in parts)>50000:raise ValueError()
    for p in parts:
        if not isinstance(p,list) or len(p)<2:raise ValueError()
        for xy in p:
            if len(xy)!=2 or any(type(v) not in (int,float) or not math.isfinite(v) for v in xy) or abs(xy[0])>90 or abs(xy[1])>180:raise ValueError()

def application(env,start):
    def reply(status,body,mime='application/json'):
        if mime=='application/json':body=json.dumps(body,separators=(',',':'))
        data=body.encode();start(status,[('Content-Type',mime),('Content-Length',str(len(data))),('Cache-Control','no-store'),('X-Content-Type-Options','nosniff')]);return [data]
    key=(DATA/'pair-key').read_text().strip()
    if env['PATH_INFO']=='/api/field-map/key' and env['REQUEST_METHOD']=='GET':
        if env.get('HTTP_X_FIELD_PAIRED_ADMIN')!='yes':return reply('403 Forbidden',{})
        return reply('200 OK','Fiji Field Map sync key\n\n'+key+'\n\nIn the app, open Routes → Sync, paste this key, and tap Connect.','text/plain; charset=utf-8')
    if env['PATH_INFO']!='/api/field-map/sync' or env['REQUEST_METHOD']!='POST':return reply('404 Not Found',{})
    if not hmac.compare_digest(env.get('HTTP_AUTHORIZATION','').encode(),('Bearer '+key).encode()):return reply('401 Unauthorized',{})
    try:
        n=int(env.get('CONTENT_LENGTH') or 0)
        if n>MAX:return reply('413 Payload Too Large',{})
        data=json.loads(env['wsgi.input'].read(n));cursor=data['cursor'];push=data['push']
        if type(cursor)!=int or cursor<0 or not isinstance(push,list) or len(push)>4:raise ValueError()
        for t in push:validate(t)
    except (KeyError,ValueError,TypeError,OverflowError):return reply('400 Bad Request',{})
    db=sqlite3.connect(DATA/'trails.sqlite',timeout=15)
    try:
        with db:
            db.execute('CREATE TABLE IF NOT EXISTS revisions(seq INTEGER PRIMARY KEY,rev TEXT UNIQUE,trail TEXT,parent TEXT,payload TEXT NOT NULL)')
            db.execute('BEGIN IMMEDIATE')
            for t in push:
                payload=json.dumps(t,sort_keys=True,separators=(',',':'))
                old=db.execute('SELECT payload FROM revisions WHERE rev=?',(t['rev'],)).fetchone()
                if old:
                    if old[0]!=payload:raise ValueError()
                    continue
                if t['parent'] and not db.execute('SELECT 1 FROM revisions WHERE rev=? AND trail=?',(t['parent'],t['id'])).fetchone():raise ValueError()
                db.execute('INSERT INTO revisions(rev,trail,parent,payload) VALUES(?,?,?,?)',(t['rev'],t['id'],t['parent'],payload))
            rows=db.execute('SELECT seq,payload FROM revisions WHERE seq>? ORDER BY seq LIMIT 5',(cursor,)).fetchall()
        page=rows[:4]
        return reply('200 OK',dict(ack=[t['rev'] for t in push],changes=[json.loads(r[1]) for r in page],cursor=page[-1][0] if page else cursor,more=len(rows)>4))
    except ValueError:return reply('409 Conflict',{'error':'revision conflict'})
    finally:db.close()
