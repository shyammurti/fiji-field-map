"""Create a compact offline OSM geometry/road-name index for display and matching."""
import sqlite3,sys,json,zlib,osmium,math
from pathlib import Path
db=sqlite3.connect(sys.argv[2])
db.executescript('CREATE TABLE roads(id INTEGER PRIMARY KEY,name TEXT NOT NULL,kind TEXT NOT NULL,coords BLOB NOT NULL,node_ids BLOB,direction INTEGER);CREATE TABLE edges(src INTEGER,dst INTEGER,lat REAL,lon REAL,cost REAL,PRIMARY KEY(src,dst)) WITHOUT ROWID;CREATE VIRTUAL TABLE bounds USING rtree(id,minlon,maxlon,minlat,maxlat);')
class Roads(osmium.SimpleHandler):
    def way(self,way):
        kind=way.tags.get('highway')
        if not kind or kind in ('construction','proposed','platform','bus_stop','crossing','street_lamp','elevator'): return
        driving=kind in ('motorway','trunk','primary','secondary','tertiary','unclassified','residential','living_street','service','track','road','motorway_link','trunk_link','primary_link','secondary_link','tertiary_link')
        access=next((way.tags[k] for k in ('motorcar','motor_vehicle','vehicle','access') if k in way.tags),'yes')
        driving=driving and access not in ('no','private','agricultural','forestry')
        one=way.tags.get('oneway','yes' if way.tags.get('junction')=='roundabout' or kind=='motorway' else 'no')
        direction=1 if one in ('yes','1','true') else -1 if one=='-1' else 0
        ids=[];pts=[]
        for n in way.nodes:
            if not n.location.valid(): return
            # Use a continuous Fiji longitude axis internally.
            ids.append(n.ref)
            pts.append((round(n.lat*1e6),round((n.lon%360)*1e6)))
        if len(pts)<2:return
        if driving:
            for i in range(1,len(pts)):
                a,b=pts[i-1:i+1];src,dst=ids[i-1:i+1]
                dl=(b[1]-a[1])/1e6
                cost=111195*math.hypot((b[0]-a[0])/1e6,dl*math.cos(math.radians((a[0]+b[0])/2e6)))
                if direction>=0:db.execute('insert or ignore into edges values(?,?,?,?,?)',(src,dst,b[0]/1e6,b[1]/1e6,cost))
                if direction<=0:db.execute('insert or ignore into edges values(?,?,?,?,?)',(dst,src,a[0]/1e6,a[1]/1e6,cost))
        for start in range(0,len(pts)-1,32):
            chunk=pts[start:start+33]; lats,lons=zip(*chunk)
            key=db.execute('insert into roads(name,kind,coords,node_ids,direction) values(?,?,?,?,?)',(way.tags.get('name',''),kind,zlib.compress(json.dumps(chunk,separators=(',',':')).encode()),zlib.compress(json.dumps(ids[start:start+33]).encode()) if driving else None,direction)).lastrowid
            db.execute('insert into bounds values(?,?,?,?,?)',(key,min(lons)/1e6,max(lons)/1e6,min(lats)/1e6,max(lats)/1e6))
Roads().apply_file(sys.argv[1],locations=True)
db.commit();print(db.execute('select count(*) from roads').fetchone())
