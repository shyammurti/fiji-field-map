"""Bundle Sentinel-2 imagery around Fiji land at zooms 5-12 using cached WMS metatiles."""
from PIL import Image
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import io,sqlite3,math,urllib.request,urllib.parse,time,sys
base=Path(__file__).resolve().parents[1]/'apps/offroad/assets'
cache=Path(sys.argv[1]);cache.mkdir(parents=True,exist_ok=True)
sea=(16,42,51)
src=sqlite3.connect(base/'fiji.mbtiles')
jobs=[]
for x,y,data in src.execute('select tile_column,tile_row,tile_data from tiles where zoom_level=10'):
    if len(Image.open(io.BytesIO(data)).getcolors(65536) or [1,2])>1: jobs.append((x,1023-y))
def fetch(xy):
    x,y=xy;p=cache/f'{x}-{y}.jpg'
    if p.exists(): return
    edge=20037508.342789244;step=2*edge/1024
    box=(x*step-edge,edge-(y+1)*step,(x+1)*step-edge,edge-y*step)
    params=dict(SERVICE='WMS',REQUEST='GetMap',VERSION='1.3.0',LAYERS='esa-worldcover-s2rgbnir-10m-2021-v2_tcc',TIME='2021-01-01',STYLES='',CRS='EPSG:3857',BBOX=','.join(map(str,box)),WIDTH=1024,HEIGHT=1024,FORMAT='image/png',TRANSPARENT='TRUE')
    for i in range(5):
        try:
            with urllib.request.urlopen('https://titiler.terrascope.be/wms?'+urllib.parse.urlencode(params),timeout=55) as r:
                im=Image.open(io.BytesIO(r.read())).convert('RGBA')
            img=Image.new('RGB',im.size,sea);img.paste(im,mask=im.getchannel('A'));img.save(p,'JPEG',quality=87)
            return
        except Exception:
            if i==4:raise
            time.sleep(2**i)
with ThreadPoolExecutor(3) as pool:list(pool.map(fetch,jobs))
dst=sqlite3.connect(base/'fiji-satellite.mbtiles')
dst.executescript('DROP TABLE IF EXISTS metadata;DROP TABLE IF EXISTS tiles;CREATE TABLE metadata(name TEXT PRIMARY KEY,value TEXT);CREATE TABLE tiles(zoom_level INTEGER,tile_column INTEGER,tile_row INTEGER,tile_data BLOB,PRIMARY KEY(zoom_level,tile_column,tile_row));')
dst.executemany('INSERT INTO metadata VALUES(?,?)',dict(name='Fiji Sentinel-2 (2021)',format='jpg',type='baselayer',minzoom='5',maxzoom='12',attribution='ESA WorldCover / Copernicus Sentinel-2 (2021)').items())
def put(z,x,y,im):
    buf=io.BytesIO();im.save(buf,'JPEG',quality=86)
    dst.execute('INSERT INTO tiles VALUES(?,?,?,?)',(z,x,2**z-1-y,buf.getvalue()))
level={}
for x,y in jobs:
    with Image.open(cache/f'{x}-{y}.jpg') as im:
        for z in (12,11,10):
            n=2**(z-10);r=im.resize((256*n,256*n),Image.Resampling.LANCZOS)
            for i in range(n):
                for j in range(n):put(z,x*n+i,y*n+j,r.crop((i*256,j*256,i*256+256,j*256+256)))
        level[x,y]=r
for z in range(9,4,-1):
    parent={}
    for (x,y),im in level.items():
        key=(x//2,y//2)
        if key not in parent:parent[key]=Image.new('RGB',(256,256),sea)
        parent[key].paste(im.resize((128,128),Image.Resampling.LANCZOS),((x%2)*128,(y%2)*128))
    for (x,y),im in parent.items():put(z,x,y,im)
    level=parent
dst.commit();print(len(jobs),'land tiles,',dst.execute('select count(*) from tiles').fetchone())
