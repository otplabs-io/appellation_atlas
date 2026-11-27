"""Each place's outline, simplified and in kilometers, for Compare (two places drawn to one scale).

The outline is the place's own boundary from its map view, or, for a place with no view of its own, the shape its
parent's view draws for it. It is laid flat around its own middle (east-west kilometers shrink with the cosine of the
latitude), simplified to about 1/150 of its size, and written as an SVG path with y pointing down:

    "outline": {"w": 61.2, "h": 115.4, "d": "M12.3 0L...Z"}

w and h are the width and height in kilometers. The site and the app scale every path by the same pixels per
kilometer, so sizes compare. Bits smaller than 1/60 of the place's size are dropped.
"""
import hashlib, json, math, os

VERSION = '2:'   # change it when the way outlines are made changes, so the cache is rebuilt
from shapely.geometry import Polygon, MultiPolygon
from shapely.ops import unary_union


def rings_of(pid, views, places):
    v = os.path.join(views, pid.replace('/', '__') + '.json')
    if os.path.exists(v):
        o = json.load(open(v, encoding='utf-8')).get('outline')
        if o: return o
    parent = (places.get(pid) or [None, None])[1]
    if not parent: return None
    pv = os.path.join(views, parent.replace('/', '__') + '.json')
    if not os.path.exists(pv): return None
    for it in json.load(open(pv, encoding='utf-8')).get('items', []):
        if it.get('id') == pid: return it.get('p')
    return None


def outline(rings, country=False):
    polys = []
    for ring in rings or []:
        if not ring: continue
        flat = ring if isinstance(ring[0], (int, float)) else ring[0]   # a ring, or a polygon given as a list of rings
        pts = list(zip(flat[0::2], flat[1::2]))
        if len(pts) >= 3:
            p = Polygon(pts).buffer(0)
            if not p.is_empty: polys.append(p)
    if not polys: return None
    g = unary_union(polys)
    trimmed = False
    if country and isinstance(g, MultiPolygon):
        # a country's far-off islands and territories (Guadeloupe for France, the Canaries for Spain) would stretch it
        # across an ocean: keep the main land and every part within a quarter of its size of a part already kept, so
        # island chains near home stay (Sicily, then Lampedusa), and say so
        main = max(g.geoms, key=lambda p: p.area)
        span = max(main.bounds[2] - main.bounds[0], main.bounds[3] - main.bounds[1])
        near, rest = [main], [p for p in g.geoms if p is not main]
        while True:
            add = [p for p in rest if min(p.distance(k) for k in near) <= span / 4]
            if not add: break
            near += add; rest = [p for p in rest if not any(p is a for a in add)]
        trimmed = len(near) < len(g.geoms)
        g = unary_union(near)
    lat = g.centroid.y
    kx, ky = 111.32 * math.cos(math.radians(lat)), 110.57   # km per degree
    minx, miny, maxx, maxy = g.bounds
    w, h = (maxx - minx) * kx, (maxy - miny) * ky
    size = max(w, h)
    if size <= 0: return None
    from shapely.affinity import affine_transform
    g = affine_transform(g, [kx, 0, 0, -ky, -minx * kx, maxy * ky])   # km, y down, from the top-left corner
    g = g.simplify(size / 150, preserve_topology=True)
    parts = list(g.geoms) if isinstance(g, MultiPolygon) else [g] if isinstance(g, Polygon) else []
    nd = 0 if size >= 100 else 1 if size >= 5 else 2
    f = lambda v: f'{v:.{nd}f}'
    d = []
    for p in sorted(parts, key=lambda p: -p.area):
        if p.area < (size / 60) ** 2: continue
        xs = list(p.exterior.coords)[:-1]
        d.append('M' + 'L'.join(f(x) + ' ' + f(y) for x, y in xs) + 'Z')
    if not d: return None
    return dict(w=round(w, 2), h=round(h, 2), d=''.join(d), **({'far': 'left out'} if trimmed else {}))


def add_all(facts_dir, views, places, cache_path):
    """Writes an outline into every place's facts. Outlines whose source rings have not changed come from the cache."""
    cache = json.load(open(cache_path)) if os.path.exists(cache_path) else {}
    n = 0
    for fn in os.listdir(facts_dir):
        if not fn.endswith('.json') or ' ' in fn: continue
        pid = fn[:-5].replace('__', '/')
        rings = rings_of(pid, views, places)
        if not rings: continue
        key = VERSION + hashlib.sha1(json.dumps(rings).encode()).hexdigest()[:16]
        key += 'c' if (places.get(pid) or [None, None])[1] == 'world' else ''
        if cache.get(pid, {}).get('key') != key:
            cache[pid] = dict(key=key, o=outline(rings, country=key.endswith('c')))
        o = cache[pid]['o']
        if not o: continue
        p = os.path.join(facts_dir, fn)
        d = json.load(open(p, encoding='utf-8')); d['outline'] = o
        with open(p, 'w', encoding='utf-8') as fh: json.dump(d, fh, ensure_ascii=False, separators=(',', ':'))
        n += 1
    with open(cache_path, 'w') as fh: json.dump(cache, fh, separators=(',', ':'))
    return n
