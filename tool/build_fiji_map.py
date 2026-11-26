"""Build the bundled Fiji overview from a Geofabrik Fiji PBF and OSM land SHP.

Usage: python3 tool/build_fiji_map.py fiji.osm.pbf land.shp output.mbtiles
Offline build dependencies: Pillow, pyosmium, pyshp, DejaVu Sans.
Coordinates stay unwrapped around Fiji until writing standard TMS tile keys.
"""
import io
import math
import sqlite3
import sys
from pathlib import Path

import osmium
import shapefile
from PIL import Image, ImageDraw, ImageFont

WEST, SOUTH, EAST, NORTH = 176.0, -21.2, 182.3, -12.0
HALF_WORLD = 20037508.342789244
SEA = '#cadfe0'
LAND = '#e3e7c7'
ROAD_STYLES = {
    'path': (10, '#94794a', 1), 'footway': (10, '#94794a', 1),
    'track': (9, '#946e44', 1), 'residential': (10, '#aaa782', 1),
    'unclassified': (9, '#a3a17f', 1), 'tertiary': (8, '#a69c76', 1),
    'secondary': (7, '#b79458', 1), 'primary': (6, '#ac7841', 2),
    'trunk': (6, '#ac7841', 2), 'motorway': (6, '#ac7841', 2),
}


def project(lon, lat):
    if lon < 0:
        lon += 360
    return ((lon + 180) / 360, (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2)


class FijiFeatures(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.lines = []
        self.places = []

    def way(self, way):
        kind = way.tags.get('highway')
        if kind in ROAD_STYLES:
            style = ROAD_STYLES[kind]
        elif way.tags.get('waterway') == 'river':
            style = (8, '#82b0b2', 1)
        else:
            return
        if all(n.location.valid() for n in way.nodes) and len(way.nodes) >= 2:
            self.lines.append((style, [project(n.lon, n.lat) for n in way.nodes]))

    def node(self, node):
        ranks = {'city': 6, 'town': 7, 'village': 9, 'hamlet': 10}
        rank = ranks.get(node.tags.get('place'))
        name = node.tags.get('name')
        if rank and name:
            self.places.append((rank, name, project(node.location.lon, node.location.lat)))


def land_rings(path):
    rings = []
    with shapefile.Reader(path) as shp:
        for shape in shp.iterShapes():
            x0, y0, x1, y1 = shape.bbox
            if y1 < -2500000 or y0 > -1200000 or (x0 < 19400000 and x1 > -19600000):
                continue
            normalized = []
            for x, y in shape.points:
                if x < 0:
                    x += 2 * HALF_WORLD
                normalized.append(((x + HALF_WORLD) / (2 * HALF_WORLD), (HALF_WORLD - y) / (2 * HALF_WORLD)))
            ends = list(shape.parts) + [len(normalized)]
            for start, end in zip(ends, ends[1:]):
                if end - start >= 3:
                    ring = normalized[start:end]
                    # Shapefile outer rings run clockwise in geographic space.
                    area = sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(ring,ring[1:]))
                    rings.append((ring, LAND if area > 0 else SEA))
    return rings


def write_map(pbf, land, dest):
    features = FijiFeatures()
    features.apply_file(pbf, locations=True)
    features.lines.sort(key=lambda item: -item[0][0])
    rings = land_rings(land)
    labels = sorted(features.places, key=lambda place: (place[0], place[1]))
    font = ImageFont.truetype('DejaVuSans.ttf', 13)
    if Path(dest).exists():
        raise SystemExit('Choose a new output path')
    with sqlite3.connect(dest) as db:
        db.executescript('CREATE TABLE metadata(name TEXT PRIMARY KEY,value TEXT);'
                         'CREATE TABLE tiles(zoom_level INTEGER,tile_column INTEGER,tile_row INTEGER,tile_data BLOB,'
                         'PRIMARY KEY(zoom_level,tile_column,tile_row));')
        db.executemany('INSERT INTO metadata VALUES (?,?)', {
            'name':'Fiji starter map','format':'png','version':'1','type':'baselayer',
            'center':'178.6,-17.2,7','minzoom':'5','maxzoom':'10',
            'description':'Fiji roads, rivers, settlements and coastline on both sides of 180 degrees.',
            'attribution':'© OpenStreetMap contributors, ODbL 1.0'
        }.items())
        for z in range(5, 11):
            n = 2**z
            xmin, ymin = [math.floor(v*n) for v in project(WEST,NORTH)]
            xmax, ymax = [math.floor(v*n) for v in project(EAST,SOUTH)]
            size = (256*(xmax+1-xmin), 256*(ymax+1-ymin))
            canvas = Image.new('RGB', size, SEA)
            draw = ImageDraw.Draw(canvas)
            def pixels(pt):
                return (round((pt[0]*n-xmin)*256), round((pt[1]*n-ymin)*256))
            for ring, color in rings:
                draw.polygon([pixels(pt) for pt in ring], fill=color)
            for (minzoom,color,width), points in features.lines:
                if z >= minzoom:
                    draw.line([pixels(pt) for pt in points], fill=color, width=width)
            occupied = []
            # Hand-placed label anchors for the overview at island scale.
            if z <= 8:
                island_font = ImageFont.truetype('DejaVuSerif.ttf', 12)
                islands = [('Viti Levu',177.96,-17.81),('Vanua Levu',179.22,-16.56),
                           ('Taveuni',180.04,-16.85),('Kadavu',178.16,-19.05),('Rotuma',177.07,-12.50)]
                for name,lon,lat in islands:
                    xy = pixels(project(lon,lat))
                    box = draw.textbbox(xy,name,font=island_font,anchor='mm',stroke_width=2)
                    if any(a<box[2] and b<box[3] and c>box[0] and d>box[1] for a,b,c,d in occupied):
                        continue
                    draw.text(xy,name,font=island_font,anchor='mm',fill='#526747',stroke_width=1,stroke_fill=LAND)
                    occupied.append(box)
            for minzoom, name, pos in labels:
                if z < minzoom:
                    continue
                x,y = pixels(pos)
                box = draw.textbbox((x+5,y),name,font=font,anchor='lm',stroke_width=2)
                if any(a<box[2]+4 and b<box[3]+3 and c>box[0]-4 and d>box[1]-3 for a,b,c,d in occupied):
                    continue
                occupied.append(box)
                draw.ellipse((x-2,y-2,x+2,y+2),fill='#364b40')
                draw.text((x+5,y),name,font=font,anchor='lm',fill='#263e36',stroke_width=2,stroke_fill='#f2f1dc')
            for x in range(xmin,xmax+1):
                for y in range(ymin,ymax+1):
                    left,top = (x-xmin)*256,(y-ymin)*256
                    out = io.BytesIO()
                    canvas.crop((left,top,left+256,top+256)).save(out,format='PNG',optimize=True)
                    db.execute('INSERT INTO tiles VALUES (?,?,?,?)',(z,x%n,n-1-y,out.getvalue()))
            print('Rendered zoom',z,flush=True)
    print(len(features.lines),'ways and',len(labels),'named places')


if __name__ == '__main__':
    write_map(*sys.argv[1:])
