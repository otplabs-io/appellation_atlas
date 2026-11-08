#!/usr/bin/env python3
"""Shapes for the app's map: one drawn view for every place with wines, from the world down to the village.
Usage: python src/geoindex.py            (reads build/catalog.json, writes build/site/geo/)
Shapes are simplified to suit each view and kept in longitude and latitude. The browser projects them onto an
orthographic globe and flies between views: no map library, no tiles, no network. world.json is every country, coarse.

A place's shape comes from the first source that has it (overrides in regions/geo-sources.json come first):
  countries        Eurostat GISCO countries 2020
  US places        UC Davis AVA boundaries, US Census counties (a state is the union of its counties)
  EU appellations  the EU wine PDO boundaries (Candiago et al. 2022), drawn by whole commune
  EU villages      Eurostat GISCO LAU communes (Champagne's cru villages)
  other countries  the zone stores src/eumaps.py builds (data/cache/eu-maps/)
  anything else    the union of its children's shapes
A place with no shape still appears, as a chip under its parent. Category nodes (IGT, the Greek PGIs, Vinho Regional)
are passed through, so their members hang from the country."""
import collections,csv,json,os,re,sqlite3,sys,unicodedata,warnings
warnings.filterwarnings('ignore')
HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE)
from shapely.geometry import shape,box,mapping
from shapely.ops import unary_union,transform
from shapely import wkb
from pyproj import Transformer
ROOT=os.path.dirname(HERE); CA=os.path.join(ROOT,'data','cache')
OUT=os.path.join(ROOT,'build','site','geo')
T=json.load(open(os.path.join(ROOT,'regions','tree.json'),encoding='utf-8'))['nodes']
OV=json.load(open(os.path.join(ROOT,'regions','geo-sources.json'),encoding='utf-8'))
def norm(s): return re.sub(r'[^a-z0-9]','',unicodedata.normalize('NFKD',s).encode('ascii','ignore').decode().lower())
def jl(p): return json.load(open(p,encoding='utf-8'))
EU_CC={'France':'FR','Italy':'IT','Spain':'ES','Germany':'DE','Portugal':'PT','Austria':'AT','Hungary':'HU','Greece':'GR'}
LAU_CC={'France':'FR','Greece':'EL'}
class Sources:
    """Each source loads once, the first time a place asks for it."""
    def __init__(s): s._c={}
    def get(s,k,f):
        if k not in s._c: s._c[k]=f()
        return s._c[k]
    def countries(s): return s.get('cn',lambda:{f['properties']['NAME_ENGL']:shape(f['geometry']).buffer(0).simplify(.005) for f in jl(os.path.join(CA,'gisco','CNTR_RG_01M_2020_4326.geojson'))['features']})
    def nuts(s): return s.get('nuts',lambda:{f['properties']['NUTS_ID']:shape(f['geometry']).buffer(0) for f in jl(os.path.join(CA,'gisco','NUTS_RG_01M_2021_4326_LEVL_2.geojson'))['features']})
    def avas(s):
        def load():
            d={}
            for f in jl(os.path.join(CA,'avas.geojson'))['features']:
                if f.get('geometry') and not f['properties'].get('removed'): d[norm(f['properties']['name'])]=shape(f['geometry']).buffer(0)
            return d
        return s.get('ava',load)
    def counties(s): return s.get('cty',lambda:{f['id']:dict(name=f['properties']['NAME'],state=f['properties']['STATE'],g=shape(f['geometry']).buffer(0)) for f in jl(os.path.join(CA,'us-counties.json'))['features']})
    def pdo(s):
        def load():
            import gpkg
            to=Transformer.from_crs(3035,4326,always_xy=True).transform
            names={}
            for r in csv.DictReader(open(os.path.join(CA,'eu-pdo','PDO_EU_id.csv'),encoding='utf-8-sig')): names[r['PDOid']]=(r['Country'],r['PDOnam'])
            GN=jl(os.path.join(ROOT,'regions','profiles','greece.json'))['map']['eu']['names']
            d={}
            for pid,blob in sqlite3.connect(os.path.join(CA,'eu-pdo','EU_PDO.gpkg')).execute('select PDOid,Shape from EU_PDO'):
                cc,nm=names[pid]; g=None
                for part in nm.split(' / ')+[GN.get(nm.split(' / ')[0],'')]:
                    if part and (cc,norm(part)) not in d:
                        g=g or transform(to,gpkg.gpkg_geom(blob).buffer(0).simplify(60))
                        d[(cc,norm(part))]=g
            return d
        return s.get('pdo',load)
    def lau(s):
        def load():
            d={}
            for f in jl(os.path.join(CA,'gisco','LAU_RG_01M_2021_4326.geojson'))['features']:
                p=f['properties']
                if p['CNTR_CODE'] in LAU_CC.values() and f.get('geometry'): d.setdefault((p['CNTR_CODE'],norm(p['LAU_NAME'])),shape(f['geometry']).buffer(0))
            return d
        return s.get('lau',load)
    def stores(s):
        def load():
            d={}
            for a in jl(os.path.join(CA,'eu-maps','_national.json'))['appellations']:
                p=os.path.join(CA,'eu-maps',a['region'],a['slug']+'.json')
                if os.path.exists(p): d.setdefault(norm(a['name']),shape(jl(p)['geometry']).buffer(0))
            return d
        return s.get('st',load)
    def store_border(s,store): return unary_union([shape(f['geometry']) for f in jl(os.path.join(CA,'eu-maps',store,'_region.json'))['features']]).buffer(0)
    def store_commune(s,store,name):
        for f in jl(os.path.join(CA,'eu-maps',store,'_communes.json'))['features']:
            if norm(f['properties']['name'])==norm(name): return shape(f['geometry']).buffer(0)
S=Sources()
def country_of(n): return T[T[n]['path'].split('/')[0]]['name']
def own_shape(n):
    """The place's own shape, and the source it came from, or (None, None)."""
    o=OV['places'].get(n,{}); nm=norm(T[n]['name']); C=country_of(n)
    if 'nuts' in o: return unary_union([S.nuts()[k] for k in o['nuts']]).buffer(0),'Eurostat GISCO NUTS 2021'
    if 'us_state' in o: return unary_union([c['g'] for c in S.counties().values() if c['state']==o['us_state']]).buffer(0),'US Census counties'
    if 'us_county' in o: return S.counties()[o['us_county']]['g'],'US Census counties'
    if 'pdo' in o: return unary_union([S.pdo()[(EU_CC[C],norm(x))] for x in o['pdo']]).buffer(0),'EU wine PDO boundaries'
    if 'store_border' in o: return S.store_border(o['store_border']),'geoBoundaries'
    if 'store_commune' in o: return S.store_commune(*o['store_commune']),'geoBoundaries'
    if 'stores' in o: return unary_union([S.stores()[norm(x)] for x in o['stores']]).buffer(0),'geoBoundaries'
    if o.get('none'): return None,None
    if T[n]['depth']==0: return S.countries().get(T[n]['name']),'Eurostat GISCO countries'
    if C=='United States':
        g=S.avas().get(nm)
        if g is not None: return g,'UC Davis AVA boundaries'
    if C in EU_CC:
        g=S.pdo().get((EU_CC[C],nm))
        if g is not None: return g,'EU wine PDO boundaries'
    if C in LAU_CC:
        g=S.lau().get((LAU_CC[C],nm))
        if g is not None: return g,'Eurostat GISCO LAU'
    g=S.stores().get(nm)
    if g is not None: return g,'zone store'
    return None,None
def display_parent(n):
    """The place the app shows this one inside: its tree parent, skipping category nodes."""
    p=OV['display_parent'].get(n,T[n]['parent'])
    while p and p in OV['passthrough']: p=T[p]['parent']
    return p
def build(items):
    used=collections.Counter()
    for it in items:
        for p in (it.get('region') or {}).get('path',[]):
            if p not in OV['passthrough']: used[p]+=1
    kids=collections.defaultdict(list)
    for n in used:
        p=display_parent(n)
        if p: kids[p].append(n)
    geo={}; src={}
    def resolve(n):   # own shape, else the union of the children that have one
        if n in geo: return geo[n]
        g,sname=own_shape(n)
        if g is None or g.is_empty:
            ch=[resolve(k) for k in kids.get(n,[])]; ch=[c for c in ch if c is not None]
            g=unary_union(ch).buffer(0) if ch else None; sname='union of its children' if ch else None
        geo[n]=g; src[n]=sname; return g
    for n in used: resolve(n)
    # the path each wine is shown along, top to bottom
    place={}
    for it in items:
        node=(it.get('region') or {}).get('node')
        if not node: continue
        while node in OV['passthrough']: node=T[node]['parent']
        chain=[]
        while node: chain.append(node); node=display_parent(node)
        place[it['iwine']]=list(reversed(chain))
    return used,kids,geo,src,place
# ---- the views, in longitude and latitude: the browser draws them on an orthographic globe and flies between them
from shapely.geometry import Polygon
from shapely.geometry.polygon import orient
import math
def ortho(lon,lat,inv=False):
    """Orthographic projection on the unit sphere centered on lon, lat (the same one the browser draws), or its inverse."""
    l0,p0=math.radians(lon),math.radians(lat); s0,c0=math.sin(p0),math.cos(p0)
    def fwd(x,y,z=None):
        import numpy as np
        l,p=np.radians(x)-l0,np.radians(y)
        return np.cos(p)*np.sin(l),c0*np.sin(p)-s0*np.cos(p)*np.cos(l)
    def back(x,y,z=None):
        import numpy as np
        x,y=np.asarray(x,float),np.asarray(y,float); r=np.hypot(x,y); c=np.arcsin(np.clip(r,0,1)); rr=np.where(r==0,1,r)
        la=np.arcsin(np.cos(c)*s0+y*np.sin(c)*c0/rr); lo=l0+np.arctan2(x*np.sin(c),r*np.cos(c)*c0-y*np.sin(c)*s0)
        return np.degrees(lo),np.degrees(la)
    return back if inv else fwd
def polys(g): return [p for p in getattr(g,'geoms',[g]) if p.geom_type=='Polygon' and not p.is_empty]
def enc(g,tol,minarea=None):
    """A shape as polygons of rings of flat [lon,lat,...], outer rings counterclockwise, rounded to suit the tolerance."""
    if g is None or g.is_empty: return []
    g=g.simplify(tol); dec=max(1,min(5,math.ceil(-math.log10(tol))+1)); minarea=tol*tol*3 if minarea is None else minarea; out=[]
    for p in polys(g):
        if p.area<minarea: continue
        p=orient(p,1.0); rs=[]
        for r in [p.exterior,*p.interiors]:
            if r is not p.exterior and Polygon(r).area<minarea: continue
            c=list(r.coords)[:-1]
            if len(c)>=3: rs.append([round(v,dec) for xy in c for v in xy])
        if rs: out.append(rs)
    return out
def frame(g,c=None):
    """Center a frame on a shape: the lon/lat at the middle of its orthographic bounds, and the half width and height there."""
    c=c or g.envelope.centroid.coords[0]
    for _ in range(2):
        b=transform(ortho(*c),g).bounds; c=ortho(*c,inv=True)((b[0]+b[2])/2,(b[1]+b[3])/2)
    b=transform(ortho(*c),g).bounds
    return [round(c[0],4),round(c[1],4)],[max(-b[0],b[2]),max(-b[1],b[3])]
def atlas_shapes():
    """Every place's shape from the Appellation Atlas (build/atlas, src/atlas.py geo) and the places under each, or nothing if
    the atlas is not built. The app draws them as thin outlines, so a region shows all of itself, not just the parts with wine."""
    sp,ip=os.path.join(ROOT,'build','atlas','shapes.json'),os.path.join(ROOT,'build','atlas','geo','index.json')
    if not (os.path.exists(sp) and os.path.exists(ip)): return {},{}
    from shapely import wkb
    full={n:wkb.loads(h,hex=True) for n,h in jl(sp).items()}; fk=collections.defaultdict(list)
    for n,x in jl(ip)['places'].items(): fk[x['parent']].append(n)
    return full,fk
def views(used,kids,geo,items,thin=False,tight=1):
    cn=S.countries(); V={}
    # the world layer: every country, coarse, with long edges split so they curve on the globe
    world=[]
    for name,g in cn.items():
        g=g.intersection(box(-180,-86,180,84))
        if g.is_empty: continue
        import shapely
        p=enc(shapely.segmentize(g.simplify(.12),1.5),.12,minarea=.08)
        if p: rp=g.representative_point(); world.append(dict(n=name,p=p,l=[round(rp.x,2),round(rp.y,2)]))
    roots=[n for n in used if display_parent(n) is None]
    # the globe starts turned toward the country with the most wines and its near neighbours, weighted by count
    cnt=collections.Counter((it.get('region') or {}).get('path',[None])[0] for it in items)
    pts={n:geo[n].representative_point() for n in cnt if geo.get(n) is not None}
    unit=lambda q:(math.cos(math.radians(q.y))*math.cos(math.radians(q.x)),math.cos(math.radians(q.y))*math.sin(math.radians(q.x)),math.sin(math.radians(q.y)))
    top=unit(pts[max(pts,key=lambda n:cnt[n])]); vx=vy=vz=0
    for n,q in pts.items():
        u=unit(q)
        if sum(a*b for a,b in zip(u,top))>math.cos(math.radians(35)): vx+=cnt[n]*u[0]; vy+=cnt[n]*u[1]; vz+=cnt[n]*u[2]
    gc=[round(math.degrees(math.atan2(vy,vx)),2),round(min(40,max(-10,math.degrees(math.atan2(vz,math.hypot(vx,vy)))-8)),2)]
    def home(c):   # a country on the globe: its main land, the islands near it and any island with wine, not its overseas lands
        g=geo[c]; ps=polys(g); L=max(ps,key=lambda p:p.area); kg=[geo[k] for k in kids.get(c,[]) if geo.get(k) is not None]
        return unary_union([p for p in ps if p.distance(L)<6 or any(p.intersects(k) for k in kg)])
    def item(c,tol,fa,g=None):
        g=g if g is not None else geo.get(c)
        if g is None: return dict(id=c,name=T[c]['name'],mode='chip')
        lp=g.representative_point()
        if fa<1e8:   # close small gaps, so a region made of many appellations reads, and taps, as one place
            if thin: g=g.simplify(tol/2)   # the atlas draws thousands of fine outlines; the app's own maps leave this off
            r=tol*8; g=g.buffer(r,quad_segs=4).buffer(-r,quad_segs=4).union(g)
        return dict(id=c,name=T[c]['name'],mode='broad' if g.area>.6*fa else 'area',p=enc(g,tol),l=[round(lp.x,5),round(lp.y,5)])
    V['world']=dict(id='world',name='The world',parent=None,center=gc,half=[1,1],span=2,ctx=None,box=None,outline=[],
                    items=[item(c,.04,1e9,home(c) if geo.get(c) is not None else None) for c in sorted(roots,key=lambda c:-(geo[c].area if geo.get(c) is not None else 0))])
    span={'world':2}
    order=sorted([n for n in used if kids.get(n) and geo.get(n) is not None],key=lambda n:T[n]['depth'])
    full,fkids=atlas_shapes() if not thin else ({},{})
    for n in order:
        ch=[geo[c] for c in kids[n] if geo.get(c) is not None]
        if T[n]['depth']==0:   # a country: its main land and every place with wine, so a region is seen in its country
            base=unary_union([max(polys(geo[n]),key=lambda p:p.area),*ch])
        else: base=unary_union(ch) if ch else geo[n]
        whole=full.get(n) if T[n]['depth']>0 else None
        if whole is not None: base=unary_union([base,whole])   # frame the whole region, not just its parts with wine
        c,half=frame(base)
        par=display_parent(n) or 'world'; f=(.3 if T[n]['depth']==1 else .2)*tight   # the atlas frames small places tighter
        m=math.radians(4) if T[n]['depth']==0 else f*span.get(par,2)/2; half=[max(half[0],m),max(half[1],m)]   # never so tight that the land around goes missing
        sp=2*max(half); span[n]=sp
        deg=math.degrees(sp); tol=deg/600
        ctx=box_=None
        if deg<22:   # close in: draw the land around at this view's detail; farther out the world layer is enough
            r=deg*1.3; la0,la1=max(-89,c[1]-r),min(89,c[1]+r); rl=min(179,r/max(.2,math.cos(math.radians(min(abs(la0),abs(la1),80)) if la0*la1>0 else 1)))
            box_=[round(c[0]-rl,3),round(la0,3),round(c[0]+rl,3),round(la1,3)]; near=box(*box_); ctx=[]
            for cname,g in cn.items():
                if g.envelope.intersects(near):
                    gc_=g.intersection(near)
                    if not gc_.is_empty: ctx.append(dict(n=cname,p=enc(gc_,tol*1.5)))
            ctx=[x for x in ctx if x['p']]
        fa=box(*transform(ortho(*c,inv=True),box(-half[0],-half[1],half[0],half[1])).bounds).area
        # the whole place and every place inside it, wine or not, as thin outlines (from the atlas's shapes, when built)
        others=[dict(n=T[k]['name'],p=enc(full[k],tol),l=[round(full[k].representative_point().x,5),round(full[k].representative_point().y,5)]) for k in fkids.get(n,[]) if k not in kids[n] and k in full]
        V[n]=dict(id=n,name=T[n]['name'],parent=par,center=c,half=[round(h,6) for h in half],span=round(sp,6),ctx=ctx,box=box_,outline=enc(whole if whole is not None else geo[n],tol),
                  others=[o for o in others if o['p']],
                  items=[item(k,tol,fa) for k in sorted(kids[n],key=lambda k:-(geo[k].area if geo.get(k) is not None else 0))])
    return V,world
def main():
    cat=jl(os.path.join(ROOT,'build','catalog.json')); items=cat['items']
    used,kids,geo,src,place=build(items)
    V,world=views(used,kids,geo,items)
    os.makedirs(os.path.join(OUT,'views'),exist_ok=True)
    for f in os.listdir(os.path.join(OUT,'views')): os.remove(os.path.join(OUT,'views',f))
    json.dump(dict(countries=world),open(os.path.join(OUT,'world.json'),'w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
    for vid,v in V.items(): json.dump(v,open(os.path.join(OUT,'views',vid.replace('/','__')+'.json'),'w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
    index=dict(places={n:dict(name=T[n]['name'],parent=display_parent(n) or 'world',view=n in V,source=src.get(n),depth=T[n]['depth']) for n in used},
               wine_place=place)
    json.dump(index,open(os.path.join(OUT,'index.json'),'w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
    none=[n for n in used if geo.get(n) is None]
    print(f'{len(V)} views, {len(used)} places, {len(none)} without a shape: {sorted(none)}')
    print('sources:',collections.Counter(src.values()))
if __name__=='__main__': main()
