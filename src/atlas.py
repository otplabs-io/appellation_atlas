#!/usr/bin/env python3
"""The Appellation Atlas: a globe of every wine place in regions/tree.json, shaded by how well known it is, with what
is known about each place. A public site, built into public/.
Usage: python src/atlas.py fetch      download the boundary files the atlas adds (Australia, New Zealand, NUTS 1 and 3)
       python src/atlas.py geo        the shapes and globe views for every place (build/atlas/; about 2 minutes)
       python src/atlas.py climate    climate and soil for every place with a shape (regions/atlas-climate.json)
       python src/atlas.py facts      what the atlas says about each place (build/atlas/facts/)
       python src/atlas.py site DIR   copy the page and its data into DIR/appellation-atlas/ (src/site.py calls this)
Shapes come from the sources and rules in src/geoindex.py, for every place in the tree
instead of the places with wine. Where those miss a place, extra_shape() adds, for the atlas only:
  Wine Australia's GI boundaries (CC BY 4.0), New Zealand's IPONZ GI register files, the EU PDO by its register id, the
  AVA by its CFR section, a PGI named for a NUTS region (Gard, Var, Drama) drawn as that region, and a village inside a
  PDO (La Morra in Barolo) drawn as the commune of that name when at least half of it lies inside the PDO. The page says
  which of the approximate ones it is. Shading is regions/notoriety.json (src/notoriety.py). Facts come from:
  the EU wine PDO dataset (Candiago et al. 2022): allowed grapes, yields, planting density, irrigation, wine types
  the UC Davis AVA boundaries: approval date, counties, the CFR section, the AVAs it sits in and holds
  research/places/: researched claims, with their strength
  regions/atlas-climate.json: WorldClim 2.1, Koppen-Geiger (Beck et al. 2023) and SoilGrids 2.0, over the place's shape
  regions/atlas-plantings.json and atlas-terrain.json (src/atlasland.py): what is planted, and elevation, slope and aspect
  regions/climate-grapes.json: which grapes suit which growing season (Jones 2010) and what each Winkler region suits;
  src/atlasland.py readings() turns these into short plain sentences on what the numbers mean for the vines"""
import collections,glob,json,math,os,re,shutil,sys,threading,time
HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE)
ROOT=os.path.dirname(HERE); OUT=os.path.join(ROOT,'build','atlas')
def jl(p): return json.load(open(p,encoding='utf-8'))
def seed():
    """A fresh clone has no build/atlas. Start one from what the repository carries: the shapes and the published geo files."""
    import gzip
    os.makedirs(OUT,exist_ok=True)
    sp,gz,pg=os.path.join(OUT,'shapes.json'),os.path.join(ROOT,'regions','atlas-shapes.json.gz'),os.path.join(ROOT,'public','geo')
    if not os.path.exists(sp) and os.path.exists(gz):
        with gzip.open(gz,'rb') as a,open(sp,'wb') as b: shutil.copyfileobj(a,b)
    if not os.path.exists(os.path.join(OUT,'geo','index.json')) and os.path.isdir(pg): shutil.copytree(pg,os.path.join(OUT,'geo'),dirs_exist_ok=True)
def snap(name):
    """Keep a function's result in regions/snapshots/, and use that copy when the raw download it reads is not here."""
    def wrap(fn):
        def run(*a):
            p=os.path.join(ROOT,'regions','snapshots',name+'.json')
            try: v=fn(*a)
            except FileNotFoundError:
                x=jl(p); return set(x) if isinstance(x,list) else x
            os.makedirs(os.path.dirname(p),exist_ok=True)
            json.dump(sorted(v) if isinstance(v,set) else v,open(p,'w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
            return v
        return run
    return wrap
T=jl(os.path.join(ROOT,'regions','tree.json'))['nodes']
def guard(gb=6):
    """Stop this process if it ever holds more than gb of memory, so a big union can't freeze the computer."""
    import psutil
    me=psutil.Process()
    def watch():
        while True:
            if me.memory_info().rss>gb*2**30: print(f'stopped: over {gb} GB of memory',flush=True); os._exit(3)
            time.sleep(2)
    threading.Thread(target=watch,daemon=True).start()
# ---- shapes and views
# ---- shapes for countries the base sources do not cover
NUTS_CC={'austria':'AT','belgium':'BE','bulgaria':'BG','croatia':'HR','cyprus':'CY','czechia':'CZ','denmark':'DK','france':'FR','germany':'DE',
         'greece':'EL','hungary':'HU','italy':'IT','luxembourg':'LU','malta':'MT','netherlands':'NL','portugal':'PT','romania':'RO',
         'slovakia':'SK','slovenia':'SI','spain':'ES'}
NUTS_NOT={'spain/cadiz','spain/cordoba'}   # their PGIs cover only some of the province's municipalities
COUNTRY_ALSO={'Turkey':'Türkiye'}   # GISCO's English name
STATE_FIPS={'West Virginia':'54','Massachusetts':'25'}   # US states whose AVAs the AVA data does not draw
class Extra:
    def __init__(s): s._c={}
    def get(s,k,f):
        if k not in s._c: s._c[k]=f()
        return s._c[k]
    def australia(s):
        """Wine Australia's Geographical Indications (zones, regions, subregions), CC BY 4.0: {name: (shape, properties)}."""
        def load():
            from shapely.geometry import shape
            import geoindex as G; d={}
            for i in range(3):
                for f in jl(os.path.join(CA,'australia-gi',f'layer{i}.geojson'))['features']:
                    if f.get('geometry'): d[G.norm(f['properties']['GI_NAME'])]=(shape(f['geometry']).buffer(0).simplify(.001).buffer(0),f['properties'])
            return d
        return s.get('au',load)
    def nz(s,slug):
        """IPONZ's boundary for one registered New Zealand wine GI (ESRI JSON in NZGD2000, which is WGS84 to a metre)."""
        p=os.path.join(CA,'nz-gi',slug+'.zip')
        if not os.path.exists(p): return None
        import zipfile,functools
        from shapely.geometry import Polygon
        Z=zipfile.ZipFile(p); js=[k for k in Z.namelist() if k.endswith('.json')]
        if not js: return None
        rings=[r for f in json.loads(Z.read(js[0]).decode('utf-8-sig'))['features'] for r in f['geometry']['rings']]
        polys=[Polygon(r).buffer(0) for r in rings if len(r)>=4]   # outer rings and holes, by even-odd
        return functools.reduce(lambda a,b:a.symmetric_difference(b),polys).simplify(.0005).buffer(0) if polys else None
    def pdo_ids(s):
        def load():
            import sqlite3,gpkg
            from pyproj import Transformer
            from shapely.ops import transform
            to=Transformer.from_crs(3035,4326,always_xy=True).transform; want=set(eu_rows_ids().values())
            return {pid:transform(to,gpkg.gpkg_geom(b).buffer(0).simplify(60)) for pid,b in
                    sqlite3.connect(os.path.join(CA,'eu-pdo','EU_PDO.gpkg')).execute('select PDOid,Shape from EU_PDO') if pid in want}
        return s.get('pdo',load)
    def avas(s):
        def load():
            from shapely.geometry import shape
            return {f['properties']['cfr_index']:shape(f['geometry']).buffer(0) for f in jl(os.path.join(CA,'avas.geojson'))['features']
                    if f.get('geometry') and f['properties'].get('removed') in (None,'None')}
        return s.get('ava',load)
    def nuts(s):
        def load():
            from shapely.geometry import shape
            import geoindex as G; d={}
            for L in (1,2,3):
                for f in jl(os.path.join(CA,'gisco',f'NUTS_RG_01M_2021_4326_LEVL_{L}.geojson'))['features']:
                    p=f['properties']
                    for nm in {p['NUTS_NAME'],p['NAME_LATN']}:
                        if G.norm(nm): d.setdefault((p['CNTR_CODE'],G.norm(nm)),(shape(f['geometry']).buffer(0).simplify(.001).buffer(0),p['NUTS_ID']))
            return d
        return s.get('nuts',load)
    def lau(s):
        """Communes (Eurostat LAU 2021) whose name is a tree place's name in the same country: {(cc, name): [shapes]}."""
        def load():
            from shapely.geometry import shape
            import geoindex as G
            want={(NUTS_CC[n.split('/')[0]],G.norm(m)) for n,t in T.items() if n.split('/')[0] in NUTS_CC for m in [t['name']]+t.get('also',[]) if G.norm(m)}
            d={}
            for f in jl(os.path.join(CA,'gisco','LAU_RG_01M_2021_4326.geojson'))['features']:
                p=f['properties']; k=(p['CNTR_CODE'],G.norm(p['LAU_NAME']))
                if k in want and f.get('geometry'): d.setdefault(k,[]).append(shape(f['geometry']).buffer(0))
            return d
        return s.get('lau',load)
    def chile(s):
        """Chile's wine zones from Decreto 464 (regions/atlas-chile.json), drawn from geoBoundaries: {node: shape}."""
        def load():
            from shapely.geometry import shape
            import geoindex as G
            fix=lambda v:(v.encode('latin-1').decode('utf-8') if any(ch in v for ch in 'ÃÂ') else v)   # BCN names come double-encoded
            lay={}
            for L,pre in (('ADM1',''),('ADM2','Provincia de '),('ADM3','')):
                for f in jl(os.path.join(CA,'chile',f'CHL_{L}.geojson'))['features']:
                    nm=fix(f['properties']['shapeName']); nm=nm[len(pre):] if pre and nm.startswith(pre) else nm
                    lay.setdefault(L,{}).setdefault(G.norm(nm),[]).append(shape(f['geometry']).buffer(0))
            D=jl(os.path.join(ROOT,'regions','atlas-chile.json'))['places']; out={}; miss=[]
            for n,x in D.items():
                gs=[]
                for k,L in (('regions','ADM1'),('provinces','ADM2'),('comunas','ADM3')):
                    for nm in x.get(k,[]):
                        g=lay[L].get(G.norm(nm))
                        if not g: miss.append(f'{n}: {nm}')
                        elif len(g)>1: miss.append(f'{n}: {nm} is not unique')
                        else: gs.append(g[0])
                if gs: out[n]=G.unary_union(gs).buffer(0)
            if miss: print('chile: not found,',miss,flush=True)
            return out
        return s.get('chile',load)
    def argentina(s):
        """geoBoundaries for Argentina: provinces {name: shape} and departments {name: [shapes]}."""
        def load():
            from shapely.geometry import shape
            import geoindex as G
            fixp={'laroja':'larioja'}   # the province layer's spelling of La Rioja
            pv={}; dp={}
            for f in jl(os.path.join(CA,'argentina','ARG_ADM1.geojson'))['features']:
                k=G.norm(f['properties']['shapeName']); pv[fixp.get(k,k)]=shape(f['geometry']).buffer(0)
            for f in jl(os.path.join(CA,'argentina','ARG_ADM2.geojson'))['features']:
                dp.setdefault(G.norm(f['properties']['shapeName']),[]).append(shape(f['geometry']).buffer(0))
            return pv,dp
        return s.get('ar',load)
X=Extra()
@__import__('functools').cache
def eu_rows_ids():
    import glob
    files={}
    for f in glob.glob(os.path.join(ROOT,'regions','sources','eu-*.json')):
        for e in jl(f)['entries']: files[e['id']]=e.get('file')
    return {n:files[x['eu_id']] for n,x in T.items() if x.get('eu_id') and files.get(x['eu_id'])}
# Districts the tree names after a small appellation of the same name: the Côte de Beaune district holds Meursault and Pommard, while
# the Côte de Beaune AOC is a few slopes above Beaune. The page is the district: drawn from its villages, without the AOC's rules.
DISTRICTS={'france/cote-de-beaune'}
SHAPE_SRC={'eu-pdo':'EU wine PDO boundaries','lau-rules':'Eurostat LAU, the municipalities its rules name','ava':'UC Davis AVA boundaries','wine-australia':'Wine Australia GI boundaries','iponz':'IPONZ GI register',
           'argentina':'geoBoundaries, the department it is named for','chile':'Chile Decreto 464, drawn from its comunas and provinces','nuts':'Eurostat NUTS, the area it is named for','lau':'Eurostat LAU, the commune it is named for'}
def geoindex_norm(v):
    import geoindex as G; return G.norm(v)
# outlines the EU record gets wrong (round 30): Valdeorras's row carries Alicante's 104 communes, Cviček's carries Bela krajina's three
SHAPE_FIX={'spain/valdeorras':('lau',['ES_32009','ES_32015','ES_32017','ES_32038','ES_32060','ES_32072','ES_32073','ES_32088']),   # O Barco, O Bolo, Carballeda, Larouco, Petín, A Rúa, Rubiá, Vilamartín: the DO's eight municipalities
           'slovenia/cvicek':('pdo','PDO-SI-A0871'),   # Cviček is the Dolenjska (Lower Carniola) district's wine: drawn as that district
           'france/coligny':('none',None)}   # merged into Val-des-Marais in 2018; the only Coligny left in the 2021 communes is in the Ain (like Vertus or Bisseuil, no outline)
def fixed_shape(n):
    import geoindex as G
    how,v=SHAPE_FIX[n]
    if how=='none': return None,None
    if how=='pdo': return X.pdo_ids()[v],'EU wine PDO boundaries'
    from shapely.geometry import shape
    gs=[shape(f['geometry']).buffer(0) for f in jl(os.path.join(CA,'gisco','LAU_RG_01M_2021_4326.geojson'))['features'] if f['properties'].get('GISCO_ID') in v or f['properties']['CNTR_CODE']+'_'+str(f['properties']['LAU_ID']) in v]
    assert len(gs)==len(v),(n,len(gs))
    return G.unary_union(gs).buffer(0),'Eurostat LAU, the municipalities its rules name'
def extra_shape(n):
    """A shape for a place the app's sources miss, and where it came from, or (None, None)."""
    import geoindex as G
    t=T[n]; c=t['path'].split('/')[0]; names=[G.norm(m) for m in [t['name']]+t.get('also',[])]
    if t['depth']==0 and t['name'] in COUNTRY_ALSO: return G.S.countries().get(COUNTRY_ALSO[t['name']]),'Eurostat GISCO countries'
    if t['name'] in STATE_FIPS and c=='united-states':
        return G.unary_union([x['g'] for x in G.S.counties().values() if x['state']==STATE_FIPS[t['name']]]).buffer(0),'US Census counties'
    pid=eu_rows_ids().get(n)
    if pid and pid in X.pdo_ids(): return X.pdo_ids()[pid],'EU wine PDO boundaries'
    if t.get('cfr') and t['cfr'] in X.avas(): return X.avas()[t['cfr']],'UC Davis AVA boundaries'
    if c=='australia':
        for m in names:
            if m in X.australia(): return X.australia()[m][0],'Wine Australia GI boundaries'
    if c=='chile' and n in X.chile(): return X.chile()[n],'Chile Decreto 464, drawn from its comunas and provinces'
    if c=='argentina' and t['depth']>=1:   # a province, or an IG named for a department inside its province
        pv,dp=X.argentina(); chain=t['path'].split('/'); prov='argentina/'+chain[1] if len(chain)>1 else None
        pn=G.norm(T[prov]['name']) if prov in T else None
        if t['depth']==1 and pn in pv and t.get('kind')=='group': return pv[pn],'geoBoundaries, the province it is named for'
        if pn in pv and t['depth']>=2:
            for m in names:
                best=max(dp.get(m,[]),key=lambda g:g.intersection(pv[pn]).area/g.area if g.area else 0,default=None)
                if best is not None and best.area and best.intersection(pv[pn]).area/best.area>=.5: return best,'geoBoundaries, the department it is named for'
    if c=='new-zealand':
        g=X.nz(n.split('/')[-1].replace('central-hawke-s-bay','central-hawkes-bay'))
        if g is not None: return g,'IPONZ GI register'
    if c in NUTS_CC and 'PGI' in (t.get('official') or [t.get('kind')]):   # a PGI named for a province, department or region
        for m in names+[G.norm(re.sub(r'\s+(IGP|IGT|PGI|VdlT|Landwein)$','',t['name']))]:
            if not m or n in NUTS_NOT: continue   # Greek names normalise to nothing
            hit=X.nuts().get((NUTS_CC[c],m))
            if hit: return hit[0],'Eurostat NUTS, the area it is named for'
    if c in NUTS_CC and t.get('parent') and 'PDO' in (T[t['parent']].get('official') or [T[t['parent']].get('kind')]) and not t.get('official'):   # a village inside an appellation (La Morra in Barolo): the commune of that name,
        try: pg,_=G.own_shape(t['parent'])   # if at least half of it lies inside the appellation
        except KeyError: pg=None
        if pg is not None and not pg.is_empty:
            for m in names:
                best=max(X.lau().get((NUTS_CC[c],m),[]),key=lambda g:g.intersection(pg).area/g.area if g.area else 0,default=None)
                if best is not None and best.area and best.intersection(pg).area/best.area>=.5: return best,'Eurostat LAU, the commune it is named for'
    return None,None
AU_GI='https://services6.arcgis.com/s8j6JbJJCqmhNgh7/arcgis/rest/services/Wine_Geographical_Indications_Australia/FeatureServer'
NZ_GI=['northland','auckland','matakana','kumeu','waiheke-island','gisborne','hawkes-bay','central-hawkes-bay','wairarapa','gladstone','martinborough',
       'nelson','marlborough','canterbury','north-canterbury','waipara-valley','waitaki-valley-north-otago','central-otago','bannockburn']
def fetch():
    """The boundary files extra_shape() reads, into data/cache/. Each is skipped when already there."""
    import re,urllib.request
    ua={'User-Agent':'PourSheetsAtlas/0.3 (personal wine-learning project)'}
    def save(url,path):
        if os.path.exists(path): return
        os.makedirs(os.path.dirname(path),exist_ok=True)
        with urllib.request.urlopen(urllib.request.Request(url,headers=ua),timeout=300) as r: open(path,'wb').write(r.read())
        print('saved',os.path.relpath(path,ROOT),flush=True); time.sleep(1)
    for i in range(3):   # zones, regions, subregions, simplified to about 50 m
        save(f'{AU_GI}/{i}/query?where=1%3D1&outFields=*&outSR=4326&geometryPrecision=5&maxAllowableOffset=0.0005&f=geojson',os.path.join(CA,'australia-gi',f'layer{i}.geojson'))
    for s in NZ_GI:   # each register page links its boundary zip
        p=os.path.join(CA,'nz-gi',s+'.zip')
        if os.path.exists(p): continue
        with urllib.request.urlopen(urllib.request.Request(f'https://www.iponz.govt.nz/get-ip/geographical-indications/register/{s}',headers=ua),timeout=60) as r:
            m=re.search(r'/assets/GIRegister/[^"]+\.zip',r.read().decode('utf-8','replace'))
        if m: save('https://www.iponz.govt.nz'+m.group(0),p)
    for L in (1,3):
        save(f'https://gisco-services.ec.europa.eu/distribution/v2/nuts/geojson/NUTS_RG_01M_2021_4326_LEVL_{L}.geojson',os.path.join(CA,'gisco',f'NUTS_RG_01M_2021_4326_LEVL_{L}.geojson'))
def geo():
    guard(); import geoindex as G
    from shapely import wkb
    places=[n for n in T if n not in G.OV['passthrough']]
    kids=collections.defaultdict(list)
    for n in places:
        p=G.display_parent(n)
        if p: kids[p].append(n)
    shp={}; src={}; t0=time.time()
    def resolve(n):
        if n in shp: return shp[n]
        try: g,s=(None,None) if n in DISTRICTS else (fixed_shape(n) if n in SHAPE_FIX else G.own_shape(n))
        except KeyError: g,s=None,None
        if (g is None or g.is_empty) and n not in DISTRICTS: g,s=extra_shape(n)
        if g is None or g.is_empty:
            ch=[c for c in (resolve(k) for k in kids.get(n,[])) if c is not None]
            g=G.unary_union(ch).buffer(0) if ch else None; s='union of its children' if ch else None
        shp[n]=g; src[n]=s; return g
    for i,n in enumerate(sorted(places,key=lambda n:-T[n]['depth'])):
        resolve(n)
        if i%250==0: print(f'shapes {i}/{len(places)} {time.time()-t0:.0f}s',flush=True)
    import shapely
    for n,g in shp.items():   # keep the views' smoothing quick: outlines past ~5,000 points are thinned to about 100 m, finer than
        if g is None: continue   # the closest view draws, and a shape of hundreds of islets (Tasmania has 5,000) drops those under ~1 km²
        if shapely.get_num_geometries(g)>100:
            ps=[p for p in getattr(g,'geoms',[g]) if p.area>=1e-4] or [max(g.geoms,key=lambda p:p.area)]; g=G.unary_union(ps)
        if shapely.get_num_coordinates(g)>5000: g=g.simplify(.001).buffer(0)
        shp[n]=g
    os.makedirs(OUT,exist_ok=True)
    json.dump({n:wkb.dumps(g,hex=True) for n,g in shp.items() if g is not None},open(os.path.join(OUT,'shapes.json'),'w'))
    import gzip
    with open(os.path.join(OUT,'shapes.json'),'rb') as x,gzip.GzipFile(os.path.join(ROOT,'regions','atlas-shapes.json.gz'),'wb',mtime=0) as z: shutil.copyfileobj(x,z)   # the copy the repository carries
    pseudo=[dict(region=dict(path=[T[n]['path'].split('/')[0]])) for n in places]   # turns the globe toward where most places are
    V,world=G.views(collections.Counter(places),kids,shp,pseudo,thin=True,tight=.25)
    import water   # the rivers and lakes the pages name, into each view that shows them (data/cache/water, from src/water.py fetch)
    used=water.attach(V,{n:G.display_parent(n) for n in places})
    json.dump({vid:[w['n'] for w in v['water']] for vid,v in V.items() if v.get('water')},open(os.path.join(OUT,'water-views.json'),'w',encoding='utf-8'),ensure_ascii=False,indent=0)
    print(f'water: {len(used)} rivers and lakes on {sum(1 for v in V.values() if v.get("water"))} views')
    import cities   # a few towns on each view, for bearings (data/cache/geonames, src/cities.py)
    cv=cities.attach(V,water.texts())
    json.dump(sorted(cv),open(os.path.join(OUT,'city-views.json'),'w',encoding='utf-8'))
    print(f'towns: {sum(len(V[v]["cities"]) for v in cv)} on {len(cv)} views')
    vd=os.path.join(OUT,'geo','views'); os.makedirs(vd,exist_ok=True)
    for f in os.listdir(vd): os.remove(os.path.join(vd,f))
    json.dump(dict(countries=world),open(os.path.join(OUT,'geo','world.json'),'w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
    for vid,v in V.items(): json.dump(v,open(os.path.join(vd,vid.replace('/','__')+'.json'),'w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
    index={n:dict(name=T[n]['name'],parent=G.display_parent(n) or 'world',view=n in V,source=src.get(n),depth=T[n]['depth']) for n in places}
    json.dump(dict(places=index),open(os.path.join(OUT,'geo','index.json'),'w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
    none=[n for n in places if shp.get(n) is None]
    print(f'{len(V)} views, {len(places)} places, {len(none)} without a shape, {time.time()-t0:.0f}s')
    print('sources:',collections.Counter(src.values()))
# ---- what the atlas says about each place
CA=os.path.join(ROOT,'data','cache')
SKIN={'N':'red','Rg':'red','B':'white','G':'pink','Gr':'pink','Rs':'pink'}   # Gr: grey-skinned (Czech Pálava, Rulandské šedé)
SRC={'eu-pdo':dict(name='Candiago et al. 2022, A geospatial inventory of regulatory information for wine protected designations of origin in Europe, Scientific Data (product specifications as of 2021)',url='https://doi.org/10.1038/s41597-022-01513-0'),
     'ava':dict(name='UC Davis Library, American Viticultural Area boundaries, with the CFR text',url='https://github.com/UCDavisLibrary/ava'),
     'wikipedia':dict(name='Wikidata sitelinks and Wikimedia page views',url='https://www.wikidata.org'),
     'weing':dict(name='Austrian Weingesetz 2009, § 23: at most 10,000 kg of grapes (7,500 litres of wine) a hectare, from the 2020 harvest',url='https://www.ris.bka.gv.at/'),
     'worldclim':dict(name='Fick and Hijmans 2017, WorldClim 2.1 monthly averages for 1970 to 2000, 2.5 minute grid (about 4.5 km)',url='https://www.worldclim.org/data/worldclim21.html'),
     'koppen':dict(name='Beck et al. 2023, High-resolution (1 km) Koppen-Geiger maps, Scientific Data (1991 to 2020)',url='https://doi.org/10.1038/s41597-023-02549-6'),
     'soilgrids':dict(name='ISRIC SoilGrids 2.0, 1 km aggregates, 30 to 60 cm depth (CC BY 4.0)',url='https://www.isric.org/explore/soilgrids'),
     'jones':dict(name='Jones 2006, Climate and Terroir: Impacts of Climate Variability and Change on Wine, Geoscience Canada reprint series 9 (growing season temperature classes)',url=None),
     'winkler':dict(name='Winkler, Cook, Kliewer and Lider 1974, General Viticulture, University of California Press (heat summation regions)',url=None),
     'wine-australia':dict(name='Wine Australia, Geographical Indications of Australia (zones, regions and subregions), CC BY 4.0',url='https://wineaustralia-opendata-wineaustralia.hub.arcgis.com/'),
     'chianti-disciplinare':dict(name='Chianti DOCG production rules (disciplinare), as amended by Reg. (EU) 2024/2741, art. 5.6: Riserva needs at least 2 years from 1 January after the harvest',url='https://aisitalia.it/Disciplinari/Toscana/DOCG/Chianti.pdf'),
     'iponz':dict(name='Intellectual Property Office of New Zealand, the geographical indications register and its boundary data',url='https://www.iponz.govt.nz/get-ip/geographical-indications/register/'),
     'nuts':dict(name='Eurostat GISCO, NUTS 2021 boundaries',url='https://ec.europa.eu/eurostat/web/gisco/geodata/statistical-units/territorial-units-statistics'),
     'chile':dict(name='Decreto 464, Zonificación vitícola (Servicio Agrícola y Ganadero), drawn on geoBoundaries comunas and regions (BCN, CC BY 3.0 IGO) and provinces (OpenStreetMap, ODbL)',url='https://sag.cl/sites/default/files/decreto_ndeg_464.pdf'),
     'argentina':dict(name='geoBoundaries, Argentina departments (Instituto Geográfico Nacional, CC BY 3.0 IGO) and provinces (CC BY 2.5)',url='https://www.geoboundaries.org'),
     'lau':dict(name='Eurostat GISCO, Local Administrative Units 2021 (communes)',url='https://ec.europa.eu/eurostat/web/gisco/geodata/statistical-units/local-administrative-units'),
     'lau-rules':dict(name='Eurostat GISCO, Local Administrative Units 2021 (the municipalities the rules name)',url='https://ec.europa.eu/eurostat/web/gisco/geodata/statistical-units/local-administrative-units'),
     'nrcs':dict(name='USDA NRCS Soil Survey Manual, Agriculture Handbook 18 (texture classes and pH classes)',url=None),
     'inao':dict(name="INAO, the appellation's cahier des charges, chapter V (grapes and their shares), from the Bulletin officiel du ministère de l'Agriculture (Licence Ouverte)",url='https://www.inao.gouv.fr/rechercher-un-produit'),
     'anderson':dict(name='Anderson, Nelgen and Puga, Database of Regional, National and Global Winegrape Bearing Areas by Variety, 2000 to 2023, University of Adelaide (CC BY 4.0)',url='https://doi.org/10.25909/32870405.v1'),
     'statistik-austria':dict(name='Statistik Austria, Weingartengrunderhebung 2020, grape varieties by state (Rebsorten nach Bundesländern 2020), in hectares',url='https://www.statistik.at/fileadmin/pages/164/RebsortenNachBL2020.ods'),
     'vivc':dict(name='Vitis International Variety Catalogue (VIVC), Julius Kühn-Institut: varieties listed only as table or raisin grapes',url='https://www.vivc.de'),
     'usda-juice':dict(name='USDA NASS grape production and disposition survey: juice-type varieties (Concord, Niagara) counted apart from wine-type ones',url='https://www.nasda.org/wp-content/uploads/2024/01/Grape-PDI-Training-Materials.pdf'),
     'terrain':dict(name='AWS Terrain Tiles (Terrarium), from SRTM, GMTED2010, ETOPO1 and national elevation models',url='https://registry.opendata.aws/terrain-tiles/'),
     'jones2010':dict(name='Jones 2010, Climate, grapes, and wine: structure and suitability in a variable and changing climate, VIII International Terroir Congress (which grapes suit which growing season temperatures)',url='https://ives-openscience.eu/wp-content/uploads/2023/03/Climate_Grape_Wine_Jones.pdf'),
     'winkler-wiki':dict(name='Wikipedia, Winkler index (what each region suits)',url='https://en.wikipedia.org/w/index.php?title=Winkler_index&oldid=1379995815'),
     'lapse':dict(name='Wikipedia, Lapse rate (6.5 °C cooler per 1,000 m, the standard atmosphere)',url='https://en.wikipedia.org/wiki/Lapse_rate'),
     'sawis':dict(name='SAWIS, Production areas defined in terms of the Wine of Origin Scheme, June 2024 (regions, districts and wards)',url='https://www.sawis.co.za/cert/download/Production_areas_-_June_2024.pdf'),}
@snap('australia-gi')
def au_gi(): return {m:v[1] for m,v in X.australia().items()}
@snap('wset')
def wset(gi):
    """The places in the WSET Level 4 Diploma, from regions/wset.json: a listed country's own node; every place in a country
    marked all; a listed place or region and everything under it; and a place with no listed ancestor whose shape's inside
    point falls within a listed region (or the listed NUTS 2 regions), so flat lists like Italy's IGTs sort by where they are."""
    from shapely import wkb
    from shapely.geometry import shape
    from shapely.ops import unary_union
    from shapely.prepared import prep
    W=jl(os.path.join(ROOT,'regions','wset.json'))['countries']; SH=jl(os.path.join(OUT,'shapes.json'))
    N2={f['properties']['NUTS_ID']:f['geometry'] for L in (2,3) for f in jl(os.path.join(CA,'gisco',f'NUTS_RG_01M_2021_4326_LEVL_{L}.geojson'))['features']} if any('nuts' in w for w in W.values()) else {}
    area={}
    for c,w in W.items():
        gs=[wkb.loads(SH[r],hex=True) for r in w.get('regions',[]) if r in SH]+[shape(N2[k]) for k in w.get('nuts',[])]
        area[c]=prep(unary_union([g.buffer(0) for g in gs])) if gs else None
    def up(n):
        while n and n!='world': yield n; n=gi[n]['parent'] if n in gi else None
    out=set()
    for n in sorted(gi,key=lambda n:len(list(up(n)))):   # parents first: a place with no shape goes with its parent
        c=n.split('/')[0]; w=W.get(c); par=gi[n]['parent']
        if w is None: continue
        named=set(w.get('regions',[]))|set(w.get('places',[]))
        if n==c or w.get('all') or any(a in named for a in up(n)): out.add(n)
        elif n in SH: (area[c] and area[c].contains(wkb.loads(SH[n],hex=True).representative_point())) and out.add(n)
        elif par!=c and par in out: out.add(n)
    return out
@snap('eu-rules')
def eu_rows():
    import csv,glob
    files={}
    for f in glob.glob(os.path.join(ROOT,'regions','sources','eu-*.json')):
        for e in jl(f)['entries']: files[e['id']]=e.get('file')
    rows={r['PDOid']:r for r in csv.DictReader(open(os.path.join(CA,'eu-pdo','PDO_EU_id.csv'),encoding='utf-8-sig'))}
    return {n:rows[files[x['eu_id']]] for n,x in T.items() if x.get('eu_id') and files.get(x['eu_id']) in rows}
def num(v):
    try: return float(v)
    except (TypeError,ValueError): return None
def grapes(s):
    out=[]
    for g in (s or '').split('/'):
        g=g.strip()
        if not g or g=='na' or '?' in g: continue   # the record's own doubt ("Moscatel Aromática (Maybe Synonym Of Moscatel De Alejandria?)" beside Moscatel de Alejandría in Alicante)
        name,_,sk=g.rpartition(' ')
        out.append([name,SKIN[sk]] if sk in SKIN and name else [g,None])
    return out
def rules(r):
    return dict(registered=r['Registration'] or None,types=[t for t in r['Category_of_wine_product'].split('/') if t and t!='na'],
                grapes=grapes(r['Varieties_OIV']),grapes_other=grapes(r['Varieties_Other']),
                yield_hl=num(r['Maximum_yield_hl']),yield_kg=num(r['Maximum_yield_kg']),density=num(r['Minimum_planting_density']),
                irrigation=None if r['Irrigation']=='na' else r['Irrigation'],communes=[c for c in r['Municip_nam'].split('/') if c and c!='na'],
                register=r['PDOinfo'] or None)
SKIN_EN={'red':'red','white':'white','pink':'pink'}
fmt0=lambda v:f'{v:,.0f}'
# French regions whose départements are not the region: Beaujolais's Rhône takes in Côte-Rôtie and leaves out its Saône-et-Loire crus;
# the Rhône Valley's Gard, Vaucluse and Drôme bring in Languedoc IGP Merlot and leave out the northern Rhône; Languedoc's lack the Gard
# places of the hand-built French hierarchy (regions/tree.json source 'chris') that are appellations or AOC mentions: Beaujolais-Villages is
# AOC Beaujolais with the mention Villages, the Hautes-Côtes are AOC Bourgogne's, Castillon and Blaye are AOC Côtes de Bordeaux's
TIER_TERMS={'italy':{'DOCG':'docg','DOC':'doc','IGT':'igt'},'france':{'AOC':'aoc','IGP':'igp'},
            'spain':{'DOCa':'doca','DO':'do-es','Vino de la Tierra':'vdlt','Vino de Pago':'vino-de-pago','Vino de Calidad':'vc-es'}}   # each country's ladder of label tiers, by the page's own category
ALSO_INSIDE={'australia/north-west-victoria':['australia/murray-darling'],'australia/big-rivers':['australia/swan-hill'],
             'united-states/sonoma-county':['united-states/los-carneros','united-states/petaluma-gap','united-states/pine-mountain-cloverdale-peak']}   # AVAs partly in the county, which the county's own count of 19 includes
CHRIS_KIND={'italy/langhe-nebbiolo':'DOC','spain/condado-do-tea':'Subzone','spain/o-rosal':'Subzone','spain/val-do-salnes':'Subzone','france/beaujolais-villages':'AOC','france/macon-villages':'AOC','france/chablis-premier-cru':'AOC','france/hautes-cotes-de-nuits':'AOC',
            'france/hautes-cotes-de-beaune':'AOC','france/castillon-cotes-de-bordeaux':'AOC','france/blaye-cotes-de-bordeaux':'AOC','france/alsace-aoc':'AOC',
            'italy/puglia-igt':'IGT','france/cote-des-bar':'district','france/montagne-de-reims':'district','france/cote-des-blancs':'district','france/vallee-de-la-marne':'district'}
# Blurbs on pages without reviewed key facts keep only what the page's own data supports: a sentence with numbers keeps them only if
# each is a planting share, the planting year, or the AVA, GI or recognition year on the page; a ranking ("largest", "first") only
# if the superlative check confirmed it (build/review/superlatives/). Wikipedia's figures and rankings were the main source of errors.
AREA_SHAPES={'EU wine PDO boundaries','Eurostat LAU, the municipalities its rules name','Eurostat NUTS, the area it is named for','Eurostat LAU, the commune it is named for',
             'geoBoundaries, the department it is named for','geoBoundaries, the province it is named for',
             'Chile Decreto 464, drawn from its comunas and provinces','union of its children','Eurostat GISCO LAU','Eurostat GISCO NUTS 2021',
             'US Census counties','geoBoundaries'}
RANK=re.compile(r"\b(largest|smallest|oldest|newest|first|highest|lowest|northernmost|southernmost|easternmost|westernmost|biggest|(?:second|third|fourth|fifth|sixth|seventh)[- ](?:largest|oldest|biggest|smallest|most)|most important|most famous|most widely|leading)\b",re.I)
def _checked():
    out=set()
    for i in range(1,5):
        bp=os.path.join(ROOT,'build','review','superlatives',f'batch{i}.json'); rp=os.path.join(ROOT,'build','review','superlatives',f'result{i}.json')
        if not (os.path.exists(bp) and os.path.exists(rp)): continue
        items,res=jl(bp),jl(rp)
        if len(items)==len(res): out|={it['sentence'] for it,r in zip(items,res) if r['verdict']=='keep'}
        out|={r['replacement'] for r in res if r.get('replacement')}
    return out
CHECKED=_checked()
PGI_WORDS={'IGT','IGP','Vino de la Tierra','Vinho Regional'}
def national_terms(t,kind):
    """A blurb says PDO or PGI where the page's label gives the national term (a DOC, an IGP): use the label's word."""
    for eu,isp in (('PDO',False),('PGI',True)):
        lab=[k for k in kind or [] if k not in ('PDO','PGI','group','AVA') and (k in PGI_WORDS)==isp]
        if len(lab)!=1: continue
        L=lab[0]; an='an' if L[0] in 'AEIOU' else 'a'
        t=re.sub(r'\b([Aa])n? '+eu+r'\b',lambda m:(an if m.group(1)=='a' else an.capitalize())+' '+L,t)
        t=re.sub(r'\b'+eu+r'\b',L,t)
    return t
def trim_blurb(t,f):
    ok=set()
    pl=f.get('planted') or {}
    for g,h,*_ in pl.get('grapes',[]):
        if pl.get('ha'): v=100*h/pl['ha']; ok|={int(v),int(v)+1,round(v)}
    for y in [pl.get('year'),(f.get('ava') or {}).get('created'),(f.get('rules') or {}).get('recognised'),(f.get('gi') or {}).get('year')]:
        if y: ok.add(int(str(y)[:4]))
    for k in ('places',):
        if (f.get('summary') or {}).get(k): ok.add(f['summary'][k])
    bad=lambda x:bool({int(v.replace(',','')) for v in re.findall(r'\d[\d,]*',x)}-ok) or bool(RANK.search(x))
    keep=[]; dropped=False
    ANAPHOR=re.compile(r'^(?:These|Those|This|They|Their|Both)\b|\bthose two\b|\bthe same (?:grapes|area|zone)\b|^It (?:was|became) (?:created|founded|established|recognized|recognised|approved|an? (?:DOCG?|AOC|DO|AVA|PDO))\.$',re.I)
    for sen in re.split(r'(?<=\.)\s+',t):
        if keep and dropped and ANAPHOR.search(sen): continue   # it leans on the sentence just cut ("It also makes white from those two grapes")
        if not keep and dropped and re.search(r'\bthe same\b|\bthose\b|^(?:That|This|These|Those)\b',sen): continue   # "That winery went bankrupt" with its winery cut
        dropped=False
        if sen in CHECKED or not bad(sen): keep.append(sen); continue
        dropped=True
        parts=re.split(r',\s+',sen.rstrip('.'))   # cut only the clause that carries the figure: "A Côte de Beaune village in Burgundy, making more than 85% red"
        if bad(parts[0]):   # "A sparkling wine appellation covering nearly 500 communes" keeps "A sparkling wine appellation"
            p0=re.sub(r'\s+(?:covering|of|with|across|spanning|around|about|nearly|over|some|at|in)\b[^,.]*?\d[^,.]*$','',parts[0])
            if p0==parts[0] or bad(p0) or len(p0.split())<3 or re.search(r'\b(?:created|founded|established|recognized|recognised|approved|planted)$|^It (?:was|became)\b',p0): continue
            if re.search(r'\b(?:is|are|was|were|sits?|lies|follows|awarded|set up|gained its \w+|bankrupt|outset|suggests|began|started)$',p0): continue   # "Sovana rosso is", "Most vines sit"
            head=re.search(r'\b(?:appellation|denomination|DOCG?|AOC|AVA|DOP?|PDO|PGI|IGP|IGT|area|region|zone|subregion|district)$',p0)
            join=len(parts)>1 and re.match(r'(?:with|for|making|led by|near|around|between)\b',parts[1])
            parts=[p0]+(parts[1:] if head and join else [])   # the clauses after it stay when they hang on a whole noun (Haut-Poitou's "with Sauvignon for white and Cabernet Franc for red")
        if re.match(r'(?:In|On|At|With|After|From|For|By|As|Since|Of)\b',parts[0]) and len(parts)>1: continue   # a lead-in with its subject cut away
        rest=[x for x in parts[1:] if not bad(x)]
        if len(rest)<len(parts)-1 and not re.match(r'(?:A|An|The)\b',parts[0]): continue   # "Across X and Y, plantings are..., then ..." loses its middle
        if (len(rest)<len(parts)-1 and len(parts[0].split())<4) or re.search(r'\b(?:along|for|of|in|on|at|from|with|between|across|by|to|and|or)$',parts[0]): continue   # "A narrow, running inland": the noun went with the figure
        keep.append(', '.join([parts[0]]+rest)+'.')
    if keep and re.match(r'Its? ',keep[0]) and not re.match(r'Its? ',t):   # the opening went; name the place instead of "It"
        keep[0]=re.sub(r'^It ',f['name']+' ',re.sub(r'^Its ',f['name']+"'s ",keep[0]))
    pl_=f.get('planted')
    if pl_ and pl_.get('grapes'):   # a planting sentence must agree with the table beside it (Western Victoria's blurb quoted the zone's leftover row)
        rows=[(g,h) for g,h,*_ in pl_['grapes'] if g!='Other']; top8={g for g,_ in rows[:8]}; lead={g for g,h in rows if h>=rows[0][1]-.01*pl_['ha']}
        names=sorted({g for g,_ in rows}|{'Shiraz','Syrah','Pinot Noir','Chardonnay','Cabernet Sauvignon','Merlot','Sauvignon Blanc','Riesling','Pinot Gris','Grenache','Tempranillo','Sangiovese','Nebbiolo','Malbec','Chenin Blanc','Semillon','Sémillon'},key=len,reverse=True)
        def agrees(x):
            if not re.search(r'\b(?:plantings|planted|leads?|led by|most planted|followed by|of the vines)\b',x): return True
            hits=sorted((x.find(g),g) for g in names if re.search(r'\b'+re.escape(g)+r'\b',x))
            seen=[]
            for i,g in hits:
                if not any(g in s_ and g!=s_ for _,s_ in hits): seen.append(g)   # "Pinot Noir" not "Noir"
            same=lambda a,b:a==b or {a,b}=={'Shiraz','Syrah'}
            return bool(seen) and any(same(seen[0],l) for l in lead) and all(any(same(g,t) for t in top8) for g in seen)
        keep=[x for x in keep if x in CHECKED or agrees(x)]
    if not f.get('planted'):   # the page shows no planting table to back a share ("Cabernet over half" in Walla Walla came from one state's side)
        keep=[x for x in keep if x in CHECKED or not re.search(r'\b(?:plantings|planted|most planted|percent|leads|over half|of the vines)\b|%',x)]
    DANG=r'\b(?:the|a|an) [a-z]+(?:ern|er|ward)?, (?=within|in|on|at|near|of)'   # "in the western, within" after "highest part of Eden Valley" was cut
    keep=[x for x in keep if not (re.search(DANG,x) and not re.search(DANG,t))]
    return ' '.join(keep)
def gc_communes():
    """Each Alsace grand cru's communes, from the commune table in its shared cahier (the EU record gives some the wrong ones: Schoenenbourg, Wiebelsberg)."""
    import glob,unicodedata
    out={}
    for tp in glob.glob(os.path.join(ROOT,'data','cache','inao','pdf','*.txt')):
        t=open(tp,encoding='utf-8').read()
        if 'NOM DE L’APPELLATION COMMUNES' not in t or 'Alsace grand cru Schoenenbourg' not in t: continue
        for m in re.finditer(r'^Alsace grand cru (\S.*?) +((?:[A-ZÉ][\w\-éèœ]+(?: Vignoble)?)(?: et (?:[A-ZÉ][\w\-éèœ]+(?: Vignoble)?))?)$',t,re.M):
            nm,cs=m.groups()
            if nm.endswith(' Bennwihr et'): nm,cs=nm[:-12],'Bennwihr et '+cs
            k='france/alsace-grand-cru-'+re.sub(r'[^a-z]+','-',unicodedata.normalize('NFKD',nm).encode('ascii','ignore').decode().lower()).strip('-')
            out.setdefault(k,cs.split(' et '))
    return out
GC=gc_communes()
# grapes the EU record lists that the disciplinare does not (Malvasia delle Lipari: Malvasia di Lipari up to 95%, Corinto Nero 5 to 8%, DM 30.11.2011)
# wine categories the EU record gives that the disciplinare does not have (Prosecco's Glera wines are not aromatic sparkling; the DOCG has no plain sparkling wine: art. 1)
TYPEDROP={'italy/prosecco-doc':{'Quality Aromatic Sparkling Wine'},'italy/asolo-prosecco':{'Quality Aromatic Sparkling Wine'},
          'italy/conegliano-valdobbiadene-prosecco-superiore':{'Quality Aromatic Sparkling Wine','Sparkling Wine'},
          'italy/cesanese-di-affile':{'Semi-Sparkling Wine'},'italy/colli-della-sabina':{'Semi-Sparkling Wine'},   # still wine only in the disciplinari in force
          'italy/circeo':{'Quality Aromatic Sparkling Wine'}}   # its one spumante is a Trebbiano-based white, not aromatic (DM 07.03.2014)
# cahiers whose sub-area tables the reader cannot untangle (Touraine 2025: per-colour roles, Gamay and five sub-area rows, so it kept
# only the white row and an Amboise red yield): show the EU record, labelled as such, until the table is read by hand
CAHIERSKIP={'france/touraine'}
# the cahier audit's corrections to what the reader made of each cahier, page by page (build/review/audit-cahier/), with their sources
CAHIERFIX=json.load(open(os.path.join(ROOT,'regions','cahier-audit.json'),encoding='utf-8')) if os.path.exists(os.path.join(ROOT,'regions','cahier-audit.json')) else {}
CAHIERSKIP|={k for k,v in CAHIERFIX.items() if v.get('eu')}
def cahier_fix(n,r,src):
    fx=CAHIERFIX.get(n)
    if not fx or fx.get('eu') or not r: return
    for k,v in (fx.get('set') or {}).items():
        if v is None: r.pop(k,None)
        else: r[k]=v
    if 'yield_base' in (fx.get('set') or {}):
        for k in ('yield_hl','yield_kg','yield_ceiling'): r.pop(k,None)
    if fx.get('limits_drop') or fx.get('limits_add'):
        r['limits']=list(dict.fromkeys([l for l in r.get('limits') or [] if l not in set(fx.get('limits_drop') or [])]+list(fx.get('limits_add') or [])))   # an added line the reader already had shows once
    if fx.get('blend_add'): r['blend']=list(fx['blend_add'])   # shares the cahier sets for the blend (assemblage, cuvée), not for the vineyard
    ren=fx.get('grape_rename') or {}; drop=set(fx.get('grape_drop') or [])
    def tidy(gs): return [[ren.get(g[0],g[0]),*g[1:]] if isinstance(g,list) else ren.get(g,g) for g in gs or [] if (g[0] if isinstance(g,list) else g) not in drop]
    for k in ('grapes','grapes_other','grapes_trial'): r[k]=tidy(r.get(k))
    if r.get('by_wine'):   # a drop that grape_add puts back moved a grape to another role (Côtes de Bourg's whites); the per-wine rows already have their roles
        back={g[0] for g in fx.get('grape_add') or []}; drop_=drop-back
        tidy_=lambda gs:[[ren.get(g[0],g[0]),*g[1:]] for g in gs or [] if g[0] not in drop_]
        r['by_wine']=[[w,tidy_(m),tidy_(o)] for w,m,o in r['by_wine']]
        r['by_wine']=[x for x in r['by_wine'] if x[1]] or None   # a wine left with no main grape is one the audit took off the page (Côtes de Bordeaux's whites belong to its sub-names)
    if fx.get('by_colour'):
        r['grapes']=r.get('grapes',[])+[g if isinstance(g,list) else [g,None] for g in r.get('grapes_other') or []]; r['grapes_other']=[]; r['by_wine']=None; r['roles_unread']=True
    r['grapes']=r.get('grapes',[])+[list(g) for g in fx.get('grape_add') or [] if list(g) not in r.get('grapes',[])]
    r['grapes_trial']=r.get('grapes_trial',[])+[list(g) for g in fx.get('trial_add') or []]
    r['grapes_other']=r.get('grapes_other',[])+[list(g) for g in fx.get('other_add') or [] if list(g) not in r.get('grapes_other',[])]
    if r.get('by_wine') and fx.get('other_add'):   # the per-wine lists too: into the one wine, or the wines of the grape's colour
        for w in r['by_wine']:
            fits=lambda g:len(r['by_wine'])==1 or bool(g[1]) and any(c in w[0] for c in {'pink':('rosé','gris','red'),'red':('red','rosé')}.get(g[1],(g[1],)))   # a grey grape belongs in the rosé and red wines
            w[2]=w[2]+[list(g) for g in fx['other_add'] if fits(g)]
    for i,c in enumerate(fx.get('cite') or []):
        SRC[f'cahierfix:{n}:{i}']=c; src.append(f'cahierfix:{n}:{i}')
# base yields set per colour in separate paragraphs the cahier reader cannot split (Terrasses du Larzac, arrêté of 3 November 2026:
# red 45 hl/ha from the sixth leaf, white 50)
BASEYIELD={'france/terrasses-du-larzac':'45 hl/ha for red, 50 for white'}
# wine categories the current specification adds to the EU record's (Manzanilla's pliego: "vino y vino de licor", modified 2023)
TYPEADD={'spain/manzanilla-de-sanlucar':['Wine'],
         'italy/lambrusco-di-sorbara':['Sparkling Wine','Quality Sparkling Wine'],
         'italy/colline-joniche-tarantine':['Sparkling Wine']}   # disciplinare art. 1: Bianco Spumante   # DM 5 Nov 2024 (GU 277, 26 Nov 2024) art. 1: rosso, rosato and bianco spumante beside the frizzante
# EU-record yields older than the disciplinare in force (Cesanese di Olevano Romano: 91 hl/ha in the record, 78 under DM 30.11.2011): say none
YIELDSTALE={'italy/cesanese-di-olevano-romano','italy/marsala','spain/terra-alta','spain/rueda'}   # Marsala: 10 t/ha for white grapes, 9 for black (disciplinare art. 4); one figure would mislead; Terra Alta 70 white, 56 red; Rueda five limits by grape and training (single document)
# UC Davis gives some AVAs their effective date, not the final rule's (Dundee Hills: T.D. TTB-18, 69 FR 69527, published 30 November 2004)
AVADATE={}   # the page now says "In effect from", which is the UC Davis date (the effective date); no overrides needed
# AVAs a later rule put inside a larger one, after the UC Davis snapshot (Contra Costa: T.D. TTB-191, 89 FR, 15 March 2024, expanded San Francisco Bay and Central Coast to take it in)
AVAWITHIN={'united-states/contra-costa':['San Francisco Bay','Central Coast']}
# AVAs a rule keeps out of the larger ones their outlines touch (Santa Cruz Mountains is "specifically excluded" from San Francisco Bay and Central Coast, 27 CFR 9.157 and 9.75)
AVANOTWITHIN={'united-states/santa-cruz-mountains':{'San Francisco Bay','Central Coast'}}
# AVAs that only partly lie in a larger one the source lists them within: shown as "Overlaps", not "Inside" (round 27, checked against the
# T.D. notices and the CFR boundaries: Bennett Valley T.D. TTB-6; Chalk Hill and Russian River Valley T.D. TTB-97 and 27 CFR 9.116; High Valley
# T.D. TTB-24 and TTB-188; Petaluma Gap T.D. TTB-149; Pine Mountain-Cloverdale Peak T.D. TTB-96; Rockpile T.D. ATF-473 and 9.70; Swan Creek
# T.D. TTB-69; Mendocino Ridge T.D. ATF-392 and 9.93; Los Carneros, Sonoma Valley and Wild Horse Valley from 9.23, 9.29, 9.32, 9.44, 9.116, 9.124)
# pairs UC Davis lists as "contains" that only touch or overlap (under half the smaller AVA inside on the boundary map): not counted as places inside
AVANOTCONTAINS={'Ozark Mountain':{'Augusta'},'Pine Mountain-Cloverdale Peak':{'Alexander Valley'},'Alexander Valley':{'Russian River Valley','Pine Mountain-Cloverdale Peak'},
                'Anderson Valley':{'Mendocino Ridge'},'Mendocino Ridge':{'Anderson Valley'},'Rockpile':{'Dry Creek Valley'},'Dry Creek Valley':{'Rockpile'},
                'Russian River Valley':{'Alexander Valley'},'Northern Sonoma':{'Sonoma Coast'},'Sonoma Coast':{'Northern Sonoma'}}
AVAOVERLAP={'united-states/bennett-valley':['Sonoma Valley','Sonoma Coast','Sonoma Mountain'],'united-states/chalk-hill':['Sonoma Coast'],
            'united-states/high-valley':['Clear Lake'],'united-states/los-carneros':['Napa Valley','Sonoma Valley','Sonoma Coast'],
            'united-states/mendocino-ridge':['Mendocino'],'united-states/petaluma-gap':['Sonoma Coast'],'united-states/pine-mountain-cloverdale-peak':['Northern Sonoma'],
            'united-states/rockpile':['Northern Sonoma'],'united-states/russian-river-valley':['Sonoma Coast'],'united-states/sonoma-valley':['Sonoma Coast'],
            'united-states/swan-creek':['Yadkin Valley'],'united-states/wild-horse-valley':['Napa Valley','Solano County Green Valley']}
RULEDROP={'italy/malvasia-delle-lipari':{'Catarratto Bianco','Viognier'},
          'italy/faro':{'Catarratto Bianco','Fiano'},
          'spain/los-cerrillos':{'Chardonnay','Merlot'},   # red only: Tempranillo, Cabernet Sauvignon, Syrah, Petit Verdot (pliego 2019, Petit Verdot added 2020)
          'spain/manzanilla-de-sanlucar':{'Moscatel De Alejandria','Muscat Blanc','Pedro Ximénez'}}   # Palomino only (pliego of May 2026)   # Faro is red only: Nerello Mascalese, Nerello Cappuccio, Nocera, up to 15% Calabrese, Gaglioppo or Sangiovese (DM 07.03.2014)
# the grape a wine is named for or built on, which the EU record leaves out, from the rules in force (with their source)
RULEADD={'austria/eisenberg':([['Welschriesling','white']],dict(name='Austrian Ministry of Agriculture, Eisenberg DAC um Welschriesling erweitert (DAC-Verordnung Eisenberg, in force 18 Sep 2024): Welschriesling for Ortswein and Riedenwein',url='https://www.bmluk.gv.at/themen/landwirtschaft/landwirtschaft-in-oesterreich/pflanzliche-produktion/wein/eisenberg-dac-um-welschriesling-erweitert.html')),
         'italy/aleatico-di-puglia':([['Aleatico','red']],dict(name='Disciplinare di produzione della DOC Aleatico di Puglia, art. 2 (Aleatico at least 85%), as amended DM 07.03.2014',url='https://disciplinare.it/userfiles/downloads/doc/DOC%20Aleatico%20di%20Puglia.pdf')),
         'spain/vallegarcia':([['Garnacha Tinta','red'],['Mazuelo','red'],['Monastrell','red']],dict(name='Amendment PDO-ES-02085-AM01 to the Vallegarcía specification, Official Journal of the EU, C 167, 21 April 2022',url='https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=OJ:C:2022:167:TOC')),
         'portugal/colares':([['Ramisco','red']],dict(name='IVV, Caderno de especificações DO Colares (PDO-PT-A1461): Ramisco for the red',url='https://www.ivv.gov.pt/wp-content/uploads/2026/02/DO_Colares.pdf'))}
DRIED=re.compile(r'passito|vin-santo|recioto|scanzo|sciacchetra|sforzato|amarone')
YIELDKINDS=re.compile(r'Fortified|Liqu|Raisined|Overripe|Partially Fermented')
def yields_many(n,r):
    """The EU record keeps one yield, the highest, where the single document sets one per kind of wine: Dafnes's 95.37 hl/ha is its
    liqueur wine's, beside 80 for Liatiko red and 47 for raisined wine. Austria's and Germany's caps are national law for every kind."""
    return n.split('/')[0] not in ('austria','germany') and any(YIELDKINDS.search(t) for t in r.get('types') or [])
def yields_agree(n,r):
    """The EU record's hl/ha and kg/ha should agree: a hectolitre of wine takes 130 to 250 kg of grapes, more for dried-grape wines.
    Where they do not, one of them is wrong (Verduno Pelaverga's 8.1 hl/ha beside 9,000 kg, Colli Romagna centrale's 6,635 hl/ha), so say neither."""
    h,k=r.get('yield_hl'),r.get('yield_kg')
    if not (h and k): return True
    q=h/(k/100)
    return .2<=q<=.9 and (q>=.6 or bool(DRIED.search(n)))   # a still wine yields 65 to 75 litres from 100 kg: Friuli Colli Orientali's 56 hl beside 11,000 kg is a subzone's figure
RULEFIX={('italy/bianco-capena','Malvasia di Candia Aromatica'):'Malvasia Bianca di Candia',
         ('italy/montecompatri-colonna','Biancame'):'Bombino Bianco',('italy/montecompatri-colonna','Verdicchio Bianco'):'Trebbiano Verde',   # disciplinare art. 2 (the EU record maps them to other prime names)
         ('france/saint-pourcain','Sacy'):'Sacy (Tressallier)'}   # the cahier: "localement appelé tressallier"
ADMIN_NOT_PGI={'greece/sterea-ellada','south-africa/paarl','south-africa/olifants-river'}   # and SAWIS's statistical Paarl, which takes in Wellington, Franschhoek and Tulbagh   # the database row is the administrative region, without Attica; the PGI covers both
PLANTDROP={'austria/eisenberg':'the 2022 rows sum to about 364 ha; the DAC Produktspezifikation gives 515 ha',
           'united-states/hudson-river-region':'its only county row is Ulster, which lies partly inside; Columbia, Dutchess and Orange are missing',
           'united-kingdom':'the 2023 country rows put Bacchus first and Pinot Noir at 3%, against WineGB and FSA figures (Chardonnay, Pinot Noir, Meunier lead)',
           'australia/central-western-australia':'its only district row is Peel, which lies in the Greater Perth zone'}   # planting tables that misstate the place
# California stays: its 2016 county rows sum to 464,000 acres, and USDA's 2016 California Grape Acreage Report (Table 10) gives 459,629 bearing acres of wine grapes, 482,641 in all
DEPT_MISMATCH={'france/cremant-de-bordeaux','france/beaujolais','france/rhone-valley','france/languedoc-roussillon','france/languedoc','france/southern-rhone','france/south-west-france'}   # and AOCs whose départements cover only part of them
US_STATE={"Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR", "California": "CA", "Colorado": "CO", "Connecticut": "CT", "Delaware": "DE", "Florida": "FL", "Georgia": "GA", "Hawaii": "HI", "Idaho": "ID", "Illinois": "IL", "Indiana": "IN", "Iowa": "IA", "Kansas": "KS", "Kentucky": "KY", "Louisiana": "LA", "Maine": "ME", "Maryland": "MD", "Massachusetts": "MA", "Michigan": "MI", "Minnesota": "MN", "Mississippi": "MS", "Missouri": "MO", "Montana": "MT", "Nebraska": "NE", "Nevada": "NV", "New Hampshire": "NH", "New Jersey": "NJ", "New Mexico": "NM", "New York": "NY", "North Carolina": "NC", "North Dakota": "ND", "Ohio": "OH", "Oklahoma": "OK", "Oregon": "OR", "Pennsylvania": "PA", "Rhode Island": "RI", "South Carolina": "SC", "South Dakota": "SD", "Tennessee": "TN", "Texas": "TX", "Utah": "UT", "Vermont": "VT", "Virginia": "VA", "Washington": "WA", "West Virginia": "WV", "Wisconsin": "WI", "Wyoming": "WY"}
def inao_rules(r,x):
    """The EU rules with the grapes sorted the way the French cahier des charges sorts them: main grapes, grapes allowed
    in smaller shares, grapes on trial to adapt to a changing climate, and the share limits."""
    import atlasland
    eu={atlasland.prime(g):[g,sk] for g,sk in r['grapes']+r['grapes_other']}
    small={'de','du','des','la','le','les','à','a','au','aux'}
    title=lambda g:' '.join(w.lower() if w.lower() in small and i else w[:1].upper()+w[1:] for i,w in enumerate(g.split()))
    seen=collections.Counter(geoindex_norm(g) for g,_,_ in x['grapes'])
    def en(g,sk):   # the EU list's English name for the grape when it has one, else the cahier's own
        if geoindex_norm(g)=='manseng' and sk=='red': g='manseng noir'   # Béarn's "manseng N" is Manseng Noir, not the white Mansengs
        if seen[geoindex_norm(g)]>1 and sk!='red': g+=' '+({'white':'blanc','pink':'rouges'} if 'muscat a petits grains' in geoindex_norm(g).replace('-',' ') else {'white':'blanc','pink':'gris'})[sk]   # Grenache N beside Grenache B; Muscat à petits grains Rg is rouge
        if atlasland.prime(g) in eu and eu[atlasland.prime(g)][1] in (sk,None): return [title(eu[atlasland.prime(g)][0]),sk]
        return [title(g),sk]
    name={}; by={'main':[],'complementary':[],'accessory':[],'adaptation':[]}
    for g,sk,role in x['grapes']:
        e=en(g,sk); name.setdefault(geoindex_norm(g),e[0]); by[role].append(e)
    alln={e[0] for v in by.values() for e in v}
    for k in by: by[k]=[e for e in by[k] if not (e[0].endswith(' Blanc') and e[0]+'he' in alln)]   # 'mondeuse B' is the Mondeuse Blanche listed beside it
    WINES={'red':'red','rosé':'rosé','white':'white'}
    def wine_roles(w):   # the roles one wine gives its grapes, where the cahier sets them per wine (Malepère's red and rosé)
        for lab,gs in x.get('by_wine') or []:
            if lab==w: return gs
        return None
    def who(l):
        wr=wine_roles(l.get('wine'))
        if not l['grapes'] and wr and l['role'] in ('main','complementary','accessory'): gs=[g for g,_,r in wr if r==l['role']]   # name them: "Merlot: at least 50%"
        else: gs=l['grapes'] or (x.get('members',{}).get(l['role'],[]) if l['role'] in ('complementary','accessory') and l['blend'] else [])   # in a blend, name the grapes the role holds
        if gs:
            ns=[name.get(geoindex_norm(g)) or title(g) for g in gs]
            s=ns[0] if len(ns)==1 else ', '.join(ns[:-1])+' and '+ns[-1]
            return s+(', each' if l['each'] and len(ns)>1 else ' together' if len(ns)>1 else '')
        if l['role']=='single': return 'Any one grape'
        noun={'main':'main grape','complementary':'complementary grape','accessory':'minor grape','adaptation':'trial grape'}[l['role']]
        return f'Each {noun}' if l['each'] else f'The {noun}s together'
    def amount(l):
        f=lambda v:f'{v:g}%'
        if l['min'] is not None and l['max'] is not None: return f"{l['min']:g} to {f(l['max'])}"
        return f"at most {f(l['max'])}" if l['max'] is not None else f"at least {f(l['min'])}"
    def line(l):
        w=who(l); pre=[f"for {l['wine']} wine" if l.get('wine') else '', 'in a blend' if l.get('blend') else '']
        pre=' and '.join(p for p in pre if p)
        if pre: w=pre[:1].upper()+pre[1:]+', '+(w[:1].lower()+w[1:] if w.split()[0] in ('The','Each','Any') else w)
        return f'{w}: {amount(l)}'
    named=lambda l:bool(l['grapes']) or bool(l['role'] in ('main','complementary','accessory') and wine_roles(l.get('wine')) and [g for g,_,r in wine_roles(l.get('wine')) if r==l['role']])
    cols_=[t for t in x.get('types') or [] if t in ('White wine','Red wine','Rosé wine','Gris (pale rosé)','Clairet')]
    tied=lambda l:bool(l.get('wine')) or (len(cols_)<=1 and not x.get('mixed_roles'))   # Clairette de Die's 65% Muscat is the méthode ancestrale's   # where the cahier makes several colours, a limit read without its colour may belong to one only (Corbières' Cinsault cap is red's; in rosé it is a main grape)
    listed=lambda l:all(geoindex_norm(g) in name for g in l['grapes'])   # a grape the role lists dropped is not capped on the page either (Corbières' Marselan, by convention only)
    lim=[line(l) for l in x['limits'] if named(l) and tied(l) and listed(l)]   # only limits that name their grapes: "the minor grapes together" reads wrongly when the page merges two tiers
    subj=collections.Counter(l.split(':')[0] for l in lim)
    lim=[l for l in lim if subj[l.split(':')[0]]==1 or l.startswith('For ')]   # one grape with two unlabelled limits belongs to two wines (Rasteau's red and its VDN): show neither
    per=[]
    for lab,gs in x.get('by_wine') or []:
        b={'main':[],'other':[]}
        for g,sk,rl in gs:
            if rl!='adaptation': b['main' if rl=='main' else 'other'].append(en(g,sk))
        lab={'red':'red wine','rosé':'rosé','white':'white wine','sparkling white':'sparkling white','sparkling rosé':'sparkling rosé','red and rosé':'red and rosé'}.get(lab,lab)
        made_={c_ for t_ in r.get('types') or [] for c_,w_ in (('red','Red'),('rosé','Rosé'),('white','White')) if w_ in t_}
        if made_ and not any(c_ in lab for c_ in made_): continue   # the page's wine types leave this colour out (a Médoc white row)
        per.append([lab,b['main'],b['other']])
    out=dict(r,grapes=by['main'],grapes_other=by['complementary']+by['accessory'],grapes_trial=by['adaptation'],by_wine=per or None,
                limits=list(dict.fromkeys(lim)),cahier=dict(year=str(x['date'])[:4] if x.get('date') else None,url=x['url']))
    if not (by['main'] or by['complementary'] or by['accessory']): return dict(r,cahier=out['cahier'],grapes_trial=by['adaptation'])   # the cahier's grapes were not read (Cabernet d'Anjou's table): keep the EU list
    sparkling_only=bool(r.get('types')) and all('Sparkling' in t for t in r['types'])
    if sparkling_only and not any('Sparkling' in t for t in x.get('types') or []): return out   # the cahier read is a still wine's (Crémant d'Alsace from Alsace's)
    if x.get('types'):
        eu=r.get('types') or []
        extra=(['Fortified wine'] if any('Liqueur' in t for t in eu) and not any(re.search('doux naturel|liqueur',t) for t in x['types']) else [])+\
              (['Sparkling wine'] if any('Sparkling' in t for t in eu) and not any('parkling' in t for t in x['types']) else [])
        out['types']=x['types']+extra; out['types_from']='cahier'   # the EU record keeps a category the cahier reading missed (Maury's vins doux naturels)
    if x.get('base_yield'): out['base_yield']=x['base_yield']
    if x.get('mixed_roles'): out['grapes'],out['grapes_other'],out['roles_unread']=by['main']+by['complementary']+by['accessory'],[],True   # roles differ by wine and the rows were not read apart
    if x.get('recognised'): out['recognised']=x['recognised']
    return out
_MON={m:i+1 for i,m in enumerate(['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'])}
def ava_start(p):
    """The date the AVA first took effect. UC Davis's 'created' is sometimes a later boundary amendment
    (High Valley: TTB-188, 2023, for an AVA set up by TTB-30 in 2005) or a typo (Coombsville 2002 for 2012).
    The first T.D. in the CFR history is the founding rule; final rules took effect 30 days after publication."""
    import datetime as dt
    c=p.get('created'); c=None if c in (None,'None') else c
    m=re.search(r'FR\s*\d+,?\s*([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),\s*(\d{4})',p.get('cfr_revision_history') or '')
    if not m or m[1].lower() not in _MON: return c
    eff=dt.date(int(m[3]),_MON[m[1].lower()],int(m[2]))+dt.timedelta(days=30)
    if c:
        try:
            if abs((dt.date.fromisoformat(c[:10])-eff).days)<=60: return c
        except ValueError: pass
    return eff.isoformat()
@snap('ava-rules')
def ava_rows():
    A={}
    for f in jl(os.path.join(CA,'avas.geojson'))['features']:
        p=f['properties']
        if p.get('removed') not in (None,'None'): continue
        A[p['cfr_index']]=p
    nn=lambda v:[x.strip() for x in re.split(r'[|,]',v or '') if x.strip() and x.strip()!='None']   # West Sonoma Coast's parents are comma-separated
    AVN={f['properties']['name'] for f in jl(os.path.join(CA,'avas.geojson'))['features']}
    gw=os.path.join(ROOT,'regions','ava-within-geometry.json'); GEOW=jl(gw) if os.path.exists(gw) else {}   # the data leaves "within" empty for 106 AVAs (Crystal Springs of Napa Valley)
    def avas(v):   # the data splits multi-word names ("Solano County|Green Valley"): join the pieces back into real AVA names, drop the rest
        ps=nn(v); out_=[]; i=0
        while i<len(ps):
            for j in range(len(ps),i,-1):
                if ' '.join(ps[i:j]) in AVN: out_.append(' '.join(ps[i:j])); i=j; break
            else: i+=1
        return out_
    out={}
    for n,x in T.items():
        p=A.get(x['cfr']) if x.get('cfr') else None
        if p: out[n]=dict(created=ava_start(p),states=sorted(set(nn(p['state']))),counties=sorted(set(nn(p['county']))),
                          within=list(dict.fromkeys(x for x in [T[o]['name'] for o in GEOW.get(n,[]) if o in T]+avas(p['within'])+AVAWITHIN.get(n,[]) if x not in AVANOTWITHIN.get(n,()) and x not in AVAOVERLAP.get(n,[]))),overlaps=AVAOVERLAP.get(n,[]),contains=avas(p['contains']),ucd=p['name'],cfr=p['cfr_index'],cfr_url=f"https://www.ecfr.gov/current/title-27/chapter-I/subchapter-A/part-9/subpart-C/section-{p['cfr_index']}")
    return out
def research():
    import glob
    out={}
    for f in glob.glob(os.path.join(ROOT,'research','places','*','*.json')):
        d=jl(f)
        if d.get('id') in T:
            out[d['id']]=dict(read=d.get('read'),sheet=d.get('sheet'),claims=[dict(topic=c.get('topic'),claim=c['claim'],strength=c.get('strength')) for c in d.get('claims',[]) if not (c.get('strength') in ('Weak','Estimate') and re.search(r'\d',c['claim']))],
                              sources=[dict(name=s.get('name'),url=s.get('url')) for s in d.get('sources',{}).values()],gaps=d.get('gaps',[]))
    return out
def facts():
    seed(); AU=au_gi()
    import geoindex as G
    np_=os.path.join(ROOT,'regions','notoriety.json'); N=jl(np_)['places'] if os.path.exists(np_) else {}
    cp=os.path.join(ROOT,'regions','atlas-climate.json'); CL=jl(cp)['places'] if os.path.exists(cp) else {}
    E,A,R=eu_rows(),ava_rows(),research()
    import blurbs; BL=blurbs.written()
    import categories; CATS=jl(os.path.join(ROOT,'regions','categories.json'))
    import keyfacts; KF=keyfacts.written()
    import style as style_; STY=style_.written(); STYR=style_.refs()   # what the wines taste like, for the WSET places (src/style.py)
    LT=jl(os.path.join(ROOT,'regions','label-terms.json')) if os.path.exists(os.path.join(ROOT,'regions','label-terms.json')) else dict(terms={},places={})
    TA={}   # the articles the label terms are defined from (src/terms.py)
    for fn in glob.glob(os.path.join(CA,'wikipedia','terms','*.json')):
        a_=jl(fn); TA[a_['title']]=a_['url']
    import atlasland
    opt=lambda f:jl(os.path.join(ROOT,'regions',f))['places'] if os.path.exists(os.path.join(ROOT,'regions',f)) else {}
    INAO=opt('inao-grapes.json')
    import water; SRC['osm-water']=water.SRC
    import cities; SRC['geonames']=cities.SRC; CV=set(jl(os.path.join(OUT,'city-views.json'))) if os.path.exists(os.path.join(OUT,'city-views.json')) else set()
    wv=os.path.join(OUT,'water-views.json'); WV=jl(wv) if os.path.exists(wv) else {}
    GI_=jl(os.path.join(OUT,'geo','index.json'))['places'] if os.path.exists(os.path.join(OUT,'geo','index.json')) else {}
    def view_of(n):   # the view the page's map shows: its own, or the nearest place above it with one (viewFor in web/atlas.js)
        while n and n!='world' and not (GI_.get(n) or {}).get('view'): n=(GI_.get(n) or {}).get('parent')
        return n
    def renamed(r,c):   # grapes in the Diploma's names for the country, once each (src/atlasland.py display): Sauvignon Blanc, Malbec, Spätburgunder
        seen=set()
        old=[g[0] for k in ('grapes','grapes_other','grapes_trial') for g in r.get(k) or [] if isinstance(g,list)]+[g[0] for w in r.get('by_wine') or [] for i in (1,2) for g in w[i]]
        swap={o:atlasland.rule_name(o,c) for o in old if atlasland.rule_name(o,c)!=o}
        if (r.get('limits') or r.get('blend')) and swap:   # the limits name grapes as the chips do: Malbec, not Cot
            keep_={v for v in swap.values()}|{g_[0] for k_ in ('grapes','grapes_other') for g_ in r.get(k_) or [] if isinstance(g_,list)}|{'Cabernet Sauvignon','Sauvignon Gris','Sauvignon Blanc','Cabernet Franc'}
            full={**{k_:k_ for k_ in keep_},**swap}   # names already in their final form match first, whole, so "Sauvignon" inside "Cabernet Sauvignon" or "Sauvignon Gris" is left alone (Bergerac)
            pat=re.compile(r'\b('+'|'.join(sorted(map(re.escape,full),key=len,reverse=True))+r')\b')
            for k_ in ('limits','blend'):
                if r.get(k_): r[k_]=[pat.sub(lambda m:full[m.group(1)],l) for l in r[k_]]
        for key in ('grapes','grapes_other'):
            out=[]
            for g in r.get(key) or []:
                nm=atlasland.rule_name(g[0] if isinstance(g,list) else g,c)
                if nm=='Malvasia' and isinstance(g,list) and g[1:2]==['red']: nm='Malvasia Nera'   # the EU record's bare red "Malvasia" is Malvasia Nera (Matino's own blurb and rules say so)
                if nm in seen: continue
                seen.add(nm); out.append([nm,*g[1:]] if isinstance(g,list) else nm)
            if r.get(key): r[key]=out
        for w in r.get('by_wine') or []:   # the same names in the per-wine roles
            for i in (1,2): w[i]=list({atlasland.rule_name(g[0],c):[atlasland.rule_name(g[0],c),*g[1:]] for g in w[i]}.values())
        if r.get('types'): r['types']=['Fortified wine' if t=='Liqueur Wine' else t for t in r['types']]   # the EU's "liqueur wine" is what the Diploma calls fortified
        sk={x[1] for x in r.get('grapes') or [] if isinstance(x,list)}
        if not r.get('cahier') or not r.get('grapes'):   # the EU's "other varieties" are those not on the OIV list, not minor ones (Almansa's Garnacha Tintorera); a cahier read with no main grapes has no roles either
            r['grapes'],r['grapes_other']=(r.get('grapes') or [])+(r.get('grapes_other') or []),[]
            if r.get('cahier'): r['roles_unread']=True
        if c=='italy' and len(r.get('grapes') or [])>=10: r['province_list']=True   # Italy's EU records list every grape the province approves, not the DOC's blend
        elif len(r.get('grapes') or [])>20: r['long_list']=True   # Germany's and Austria's records carry the national list of approved varieties
        elif r.get('types')==['Wine'] and 'white' in sk and sk<={'white','pink'}: r['types']=['White wine']   # white grapes make only white wine; red grapes can make red, rosé or white, so they say nothing
        if r.get('types')==['Wine']: r.pop('types')   # the record gives no colour or style: say nothing rather than "Wine"
        by=r.pop('base_yield',None)
        if by:   # the cahier's rendement, for the colours this place makes; the EU figure is the rendement butoir, the ceiling some years allow
            cols={'White wine':'white','Red wine':'red','Rosé wine':'rosé','Gris (pale rosé)':'gris','Clairet':'clairet'}
            made={cols[t] for t in r.get('types') or [] if t in cols}
            colour=lambda lab:{w for w in lab.replace('dry ','').replace('sweet ','').split(' and ')}
            keep=[b for b in by if not b[0] or not made or not colour(b[0])<=set(cols.values()) or colour(b[0])&made]   # still and sparkling rows stay
            n=lambda b:f"{fmt0(b[1])} {b[2]}"
            if len(keep)==1 or len({b[1] for b in keep})==1: r['yield_base']=n(keep[0])
            elif keep: r['yield_base']=n(keep[0])+' for '+keep[0][0]+', '+', '.join(f"{fmt0(b[1])} for {b[0]}" for b in keep[1:])
            r.pop('yield_hl',None); r.pop('yield_kg',None)
        elif c=='france' and (r.get('yield_hl') or r.get('yield_kg')) and not r.get('cahier'): r['yield_ceiling']=True   # only the EU's rendement butoir is known; where a cahier was read but its yields were not (Savennières), say no more than the EU record does
        r.pop('registered',None)   # an EU record date (1973 for most old names), not when the place was recognised
        return r
    rules_of=lambda k:renamed(inao_rules(rules(E[k]),INAO[k]) if k in INAO and k not in CAHIERSKIP else rules(E[k]),k.split('/')[0])
    PLN,TER,RK=opt('atlas-plantings.json'),opt('atlas-terrain.json'),opt('atlas-rocks.json'); CG=jl(os.path.join(ROOT,'regions','climate-grapes.json'))
    OWNROW={T[k]['name'] for k,v in PLN.items() if v.get('scope')=='own' and k in T}   # places with a database row of their own
    CG['rocks']=jl(os.path.join(ROOT,'regions','rock-types.json')); RNAME={x['id']:x['name'] for x in CG['rocks']['families']}
    for k,v in CG['rocks']['sources'].items(): SRC.setdefault('rock-'+k,v)
    PLOTS=opt('atlas-plots.json'); TER.update(PLOTS)   # a grand cru measured over its own vineyard, in place of the whole commune the EU draws
    SRC.setdefault('plots',jl(os.path.join(ROOT,'regions','grand-crus.json'))['source'])
    gi=jl(os.path.join(OUT,'geo','index.json'))['places']; WS=wset(gi)
    kids=collections.defaultdict(list)
    for n,x in gi.items(): kids[x['parent']].append(n)
    UCD_T={v['ucd']:T[k]['name'] for k,v in A.items() if k in T and v.get('ucd')}   # UC Davis's name for an AVA, as the atlas names it (Oak Knoll District of Napa Valley)
    OVERLAP_OF={T[k]['name']:set(v) for k,v in AVAOVERLAP.items() if k in T}   # an AVA's name: the larger AVAs it only partly lies in
    def below(n):   # every place under n in the atlas
        out=[]; st=list(kids.get(n,[]))
        while st: k=st.pop(); out.append(k); st+=kids.get(k,[])
        return out
    from shapely import wkb
    AREA={}
    for k,h in jl(os.path.join(OUT,'shapes.json')).items():   # km2, near enough: square degrees scaled at the shape's latitude
        g=wkb.loads(h,hex=True); AREA[k]=round(g.area*111.32**2*math.cos(math.radians(g.representative_point().y)))
    OWN={'UC Davis AVA boundaries','Wine Australia GI boundaries','IPONZ GI register'}   # drawn to the place's own boundary, not by whole commune or district
    def vineyard(k,src):   # small enough, and drawn closely enough, for the way its slopes face to mean something: a single vineyard or grand cru,
        return k in PLOTS or (src in OWN and AREA.get(k,99)<=2)   # a few hectares up to Corton's 160 (1.6 km2). The EU draws grand crus by whole commune, so those are measured apart, in PLOTS.
    def part(k):   # one row of the table that compares the places inside a big or varied place
        c=(CL.get(k) or {}).get('climate') or {}; te=TER.get(k) or {}; pl=PLN.get(k) or {}
        if not c and not te: return None
        cls=next((nm for lo,hi,nm in CG['classes'] if lo<=c['gst']<hi),None) if c.get('gst') is not None else None
        top=None   # which way slopes face means nothing over a whole district, so the table leaves it out
        g=pl['grapes'][0][0] if pl.get('scope') in ('own','within') and pl.get('grapes') and pl['grapes'][0][0]!='Other' else None
        big=AREA.get(k,0)>15000 or bool(te and te['elev'][2]-te['elev'][0]>=800)
        if big:   # a varied place: the spread across the places inside it, not its own blurred average
            gs=sorted(CL[q]['climate']['gst'] for q in below(k) if (CL.get(q) or {}).get('climate') and CL[q]['climate'].get('gst') is not None and not (AREA.get(q,0)>15000))
            return [k,[gs[0],gs[-1]] if len(gs)>=2 else None,None,te['elev'] if te else None,te.get('steep'),None,g,int(k in BENCH),1]
        return [k,c.get('gst'),cls,(te['elev'] if big else te['elev'][1]) if te else None,te.get('steep'),top if te and te.get('flat',1)<.8 and not big else None,g,int(k in BENCH),int(big)]
    NAMED={k for w in jl(os.path.join(ROOT,'regions','wset.json'))['countries'].values() for k in w.get('regions',[])+w.get('places',[])}
    VINELESS={'australia/eastern-plains-inland-and-north-of-western-australia'}   # a GI zone of desert with no vineyards recorded
    def bench(n):   # a Benchmark page is one inside a Diploma region that has something of its own to teach: rules, an AVA, key facts or a climate
        if n not in WS: return False
        if '/' not in n or n in NAMED or T[n].get('source')=='chris': return True   # a country, a place the Diploma list names, or one of the hand-built Diploma structure
        own=n in E or n in A or n in KF or (CL.get(n) or {}).get('climate',{}) and CL[n]['climate'].get('gst') is not None or (n in BL and gi[n].get('source'))   # a blurb counts when the place is on the map (South Eastern Australia), not for a name alone (Creek Shores)
        return bool(own) and n not in VINELESS
    BENCH={n for n in gi if bench(n)}
    WL=jl(os.path.join(ROOT,'regions','wset-levels.json'))   # the places the Level 2 and Level 3 specifications name
    def lv(n):   # 1 named in Level 2, 2 named in Level 3, 4 above a Level 2 place, 8 above a Level 3 place (so the way to it is gold too)
        return LV.get(n,0)
    LV={}
    for bit,key in ((1,'2'),(2,'3')):
        for k in WL[key]['places']:
            if k not in gi: continue
            LV[k]=LV.get(k,0)|bit; q=gi[k]['parent']
            while q and q!='world': LV[q]=LV.get(q,0)|(bit*4); q=gi[q]['parent'] if q in gi else None
    kids_={}
    for k,v in gi.items(): kids_.setdefault(v['parent'],[]).append(k)
    PARTIAL={k for k,v in gi.items() if v.get('source')=='union of its children' and kids_.get(k) and 2*sum(1 for c in kids_[k] if gi[c].get('source'))<len(kids_[k])}
    PARTIAL|={'italy/freisa-d-asti','greece/sterea-ellada'}   # Sterea Ellada's outline and rows are the administrative region, which leaves out Attica   # the EU record lists the two communes its rules leave out, so the outline is the wrong land
    fd=os.path.join(OUT,'facts'); os.makedirs(fd,exist_ok=True)
    for f in os.listdir(fd): os.remove(os.path.join(fd,f))
    places={}
    for n,x in gi.items():
        t=T[n]; chain=[]; p=x['parent']
        while p and p!='world': chain.insert(0,[p,T[p]['name']]); p=gi[p]['parent']
        own_st={US_STATE.get(s.strip(),s.strip()) for s in (A.get(n) or {}).get('states') or []}   # 'WA', or 'Washington' spelled out (Beverly, Upper Cumberland)
        if own_st: chain=[c for c in chain if not (c[0].count('/')==1 and c[0].startswith('united-states/') and c[1] in US_STATE and US_STATE[c[1]] not in own_st)]   # an Ohio AVA inside Lake Erie, which is filed under New York
        kind=[k for k in t.get('official',[]) if k] or ([t['kind']] if t.get('kind') else [])
        kind=categories.label(n,kind,CATS)   # AOC, DOCG, DOCa, DOC, not the EU's PDO: the words the Diploma uses (src/categories.py)
        if n in DISTRICTS or n=='france/cote-de-nuits': kind=['district']
        if not kind and n in CHRIS_KIND: kind=[CHRIS_KIND[n]]
        if n=='france/alsace-grand-cru': kind=['AOC']   # 51 grand cru AOCs under one name
        f=dict(id=n,name=t['name'],also=[a for a in t.get('also',[]) if a.casefold()!=t['name'].casefold()],kind=kind,country=T[t['path'].split('/')[0]]['name'],chain=chain,depth=t['depth'],
               shape=x['source'],known=N.get(n))
        src=(['wikipedia'] if n in N else [])+(['sawis'] if n.startswith('south-africa/') else [])
        if n in E and n not in DISTRICTS: f['rules']=rules_of(n); src+=['eu-pdo']+(['inao'] if n in INAO else [])
        for g in (f.get('rules') or {}).get('grapes') or []:   # record names the disciplinare contradicts (Bianco Capena's Malvasia is the Lazio Malvasia di Candia, not the aromatic one)
            if isinstance(g,list) and (n,g[0]) in RULEFIX: g[0]=RULEFIX[(n,g[0])]
        if n in GC and f.get('rules'): f['rules']['communes']=GC[n]
        if n.startswith('austria/') and f.get('rules'):
            r_=f['rules']
            if r_.get('yield_kg')==9000: r_['yield_kg']=10000.0; r_.pop('yield_hl',None); src.append('weing')   # the 2022 record keeps the old limit for six DACs (Wachau, Carnuntum)
            if 'DAC' in (f.get('kind') or []) and r_.get('types'): r_['types']=[x_ for x_ in r_['types'] if 'parkl' not in x_] or None   # a DAC is for wine; Austrian Sekt g.U. is named for its Bundesland
        if n.startswith('france/alsace-grand-cru-') and (f.get('rules') or {}).get('by_wine'):   # red grand cru is Pinot Noir alone (cahier 2025, V.1°a)
            f['rules']['by_wine']=[[w,[g for g in m if g[1]=='red'],[g for g in o if g[1]=='red']] if w.startswith('red') else [w,m,o] for w,m,o in f['rules']['by_wine']]
        if n in TYPEADD and f.get('rules'): f['rules']['types']=TYPEADD[n]+[x_ for x_ in f['rules'].get('types') or [] if x_ not in TYPEADD[n]]
        if n in TYPEDROP and (f.get('rules') or {}).get('types'): f['rules']['types']=[x_ for x_ in f['rules']['types'] if x_ not in TYPEDROP[n]] or None
        if n.startswith('austria/') and 'DAC' in (f.get('kind') or []) and (f.get('rules') or {}).get('long_list'):   # the record's national list, not the DAC's own few grapes (Weststeiermark allows nine)
            f['rules'].pop('long_list',None); f['rules']['grapes']=[]; f['rules']['grapes_other']=[]   # empty, not missing: the page reads both lists
        if n in RULEADD and f.get('rules'):
            f['rules']['grapes']=RULEADD[n][0]+[g for g in f['rules'].get('grapes') or [] if not (isinstance(g,list) and g[0] in {x[0] for x in RULEADD[n][0]})]
            SRC['ruleadd:'+n]=RULEADD[n][1]; src.append('ruleadd:'+n)
        if n in RULEDROP and f.get('rules'): f['rules']['grapes']=[g for g in f['rules'].get('grapes') or [] if not (isinstance(g,list) and g[0] in RULEDROP[n])]
        if n in BASEYIELD and f.get('rules'): f['rules']['yield_base']=BASEYIELD[n]
        cahier_fix(n,f.get('rules'),src)
        if f.get('rules') and (n in YIELDSTALE or n.split('/')[0] in ('italy','spain','greece','portugal') or not yields_agree(n,f['rules']) or yields_many(n,f['rules'])):   # Italian disciplinari and Spanish pliegos set yields per type, colour or grape; the EU record keeps one (the highest), so say none
            for k_ in ('yield_hl','yield_kg','yield_ceiling'): f['rules'].pop(k_,None)
        if n in A: f['ava']=dict(A[n],**AVADATE.get(n,{})); src.append('ava')
        if n in CL:
            f['climate']=CL[n].get('climate'); src+=[s for s in ('worldclim','koppen','winkler','jones2010') if f['climate']]   # no topsoil: a 1 km model contradicts the documented soils too often (Willow Creek's calcareous shale reads pH 6.7)
        # Only figures that are the place's own: its region, the districts inside it, or its country. A wider district's mix sits under
        # the place's name as if it were its own, and students read it so: Merlot-led Pauillac, Gamay in Côte-Rôtie, red Meursault.
        part_rows=[c for c in (A.get(n) or {}).get('contains',[]) if c in OWNROW and c not in (PLN.get(n) or {}).get('names',[])]
        sc_=PLN.get(n,{}).get('scope')   # a French main region's départements are the region (Alsace's Haut-Rhin and Bas-Rhin); elsewhere a wider
        own_scope=(sc_ in ('own','within','country') and n not in DEPT_MISMATCH) or (sc_=='around' and t['depth']==1 and n.startswith('france/') and n not in DEPT_MISMATCH)   # area's mix is another place's (Priorat's Cataluña)
        multistate=len({x.strip() for x in (A.get(n) or {}).get('states') or []})>1   # a state's report covers only its side (Columbia Gorge), or what is left outside sub-AVAs (Columbia Valley)
        no_other=n.startswith('united-states/') and not any(g=='Other' for g,*_ in (PLN.get(n) or {}).get('grapes',[]))   # rows with no "other" line count only the listed grapes (Lake Chelan: 104 of about 265 acres)
        statewide=n.startswith('united-states/') and sc_=='within' and any(x in US_STATE for x in PLN.get(n,{}).get('names') or []) and t['name'] not in US_STATE   # a state's table on an AVA (Loramie Creek shows all Ohio)
        if n in PLN and (PLN[n].get('ha') or 0)>=20 and own_scope and not part_rows and n not in ADMIN_NOT_PGI and not multistate and not statewide and not no_other and n not in PLANTDROP:   # under 20 ha, whole-hectare rows make shares meaningless (Tandil's 9 ha)   # an AVA whose row leaves out its sub-AVAs' rows (Columbia Valley) is incomplete
            f['planted']=dict(PLN[n]); src.append(PLN[n].get('source') or 'anderson')
            if f['planted'].get('scope')=='around' and t['depth']==1 and n.startswith('france/'): f['planted']['scope']='within'   # the départements named, not a wider area (the Loire's four)
            if f['planted'].get('scope')=='within' and f['planted'].get('names')==[T.get(t.get('parent'),{}).get('name')]: f['planted']['scope']='own'   # a zone holding only this region (the Hunter in Hunter Valley)
            if PLN[n].get('scope')=='own' and set(f.get('kind') or [])&{'DOC','DOCG','DO','DOCa','IGT','IGP','Vino de la Tierra','Vinho Regional','PDO','PGI','AOC','DAC'}: f['planted']['any_name']=True   # the region's vineyards, not only what is sold under this name (Piemonte DOC)
            lf=PLN[n].get('left') or {}
            src+=(['vivc'] if 'table' in lf else [])+(['usda-juice'] if 'juice' in lf else [])
            if f.get('rules') and f['rules'].get('grapes'): f['planted']['legal']=atlasland.legal(f['planted'],f['rules'])
        if n in TER and TER[n]['elev'][2]-TER[n]['elev'][0]<1: pass   # one flat reading is the tiles' floor, not the land (Merritt Island, partly below sea level)
        elif n in TER:
            f['terrain']=TER[n] if vineyard(n,x['source']) else {k:v for k,v in TER[n].items() if k!='aspect'}; src+=['terrain','lapse']+(['plots'] if n in PLOTS else [])
        if n in AREA: f['area_km2']=AREA[n]
        if n in RK and not n.startswith('austria'): f['rocks']=dict(RK[n],families=[[i,min(v,.49) if k else v] for k,(i,v) in enumerate(RK[n]['families'])],names={i:RNAME[i] for i,_ in RK[n]['families'] if i in RNAME});   # only the first family can be "mostly" src+=['rock-macrostrat','rock-wiki-soils','rock-sommselect']
        te=TER.get(n)
        f['large']=t['depth']==0 or AREA.get(n,0)>15000 or bool(te and te['elev'][2]-te['elev'][0]>=800)   # too big or too varied for one reading
        if f['large']:
            rows=[r for r in (part(k) for k in kids.get(n,[])) if r]
            if len(rows)>=2: f['parts']=rows
        if n in PARTIAL:   # its outline joins only a few of the places inside it (Breede River Valley is Robertson's alone): figures over it would be theirs
            for k in ('climate','soil','terrain','rocks','parts'): f.pop(k,None)
            for k in ('worldclim','koppen','winkler','jones2010','soilgrids','nrcs','terrain','lapse','rock-macrostrat','rock-wiki-soils','rock-sommselect'):
                if k in src: src.remove(k)
        if n.startswith('france/alsace-grand-cru-'):   # climate and rock read over the cru's whole communes, Vosges forest and all (Sporen's one cell reads 55°F); the terrain is the plot's own
            for k in ('climate','soil','rocks'): f.pop(k,None)
            for k in ('worldclim','koppen','winkler','jones2010','rock-macrostrat','rock-wiki-soils','rock-sommselect'):
                if k in src: src.remove(k)
        rd=atlasland.readings(dict(f,_wider=(PLN.get(n) or {}).get('grapes')),CG)   # the wider table only orders the rules' grapes, it names none
        if rd: f['reading']=rd
        c_=f.get('climate') or {}
        if c_.get('tavg') and c_.get('prec') and c_.get('koppen') and not c_['koppen'].startswith('B'):   # the map's class against the page's own monthly figures (Köppen's dry test)
            T_=sum(c_['tavg'])/12; P_=sum(c_['prec']); summer=[9,10,11,0,1,2] if c_.get('lat',0)<0 else [3,4,5,6,7,8]
            sh=sum(c_['prec'][i] for i in summer)/P_ if P_ else 0
            th=20*T_+(280 if sh>=.7 else 0 if sh<.3 else 140)
            if P_<.5*th:   # Molinos: 137 mm a year is desert, though the 1 km map, taking in mountain cells, says Cwb
                f['climate']=dict(c_,koppen='BW'+('h' if T_>=18 else 'k'),koppen_name='Arid, desert'+(', hot' if T_>=18 else ', cold')+' (from WorldClim\'s monthly averages)')
        GC_=n.startswith('france/alsace-grand-cru-')   # climate and soil read over the cru's whole communes, Vosges forest and all, not its plot (Schoenenbourg)
        if f.get('soil') and (GC_ or AREA.get(n,99)<5 or (f.get('climate') or {}).get('cells',9)<=2): f.pop('soil',None)   # a 1 km topsoil model on a plot of a few hectares
        if f.get('climate'):   # no rain anywhere, by Chris's choice: grids read valleys ringed by hills and deserts far too wet, and too few
            # weather stations stand among vines (build/review/rain/). The monthly rain stays in atlas-climate.json for the dry test above only
            f['climate']={k:v for k,v in f['climate'].items() if k not in ('rain','gs_rain','prec','dry')}
        if f.get('climate') and f['climate'].get('gdd') is not None:
            # the class only: Winkler's sentences for each class were written for California, and read wrongly elsewhere ("mostly hybrids"
            # in Champagne, "quality tops out at acceptable" in the Barossa); what suits the place is said from its own grapes instead
            f['winkler']=next(([w[0],''] for w in CG['winkler']['regions'] if w[1]<=f['climate']['gdd']<w[2]),['below Ia' if f['climate']['gdd']<850 else 'above V',''])
        if n in R: f['research']=R[n]
        tk=[k for p_ in [c_[0] for c_ in chain]+[n] for k in LT['places'].get(p_,[])]+LT.get('only',{}).get(n,[]); tk=[k for k in tk if n not in LT.get('except',{}).get(k,[])]
        tiers=TIER_TERMS.get(n.split('/')[0])
        if tiers:   # a DOC page explains DOC, not every tier of Italy's ladder; a place with no tier of its own (a region, a group) keeps them all
            kinds_=list(f.get('kind') or [])+[x for c_ in reversed(chain) for x in categories.label(c_[0],[k_ for k_ in T[c_[0]].get('official',[]) if k_] or ([T[c_[0]]['kind']] if T[c_[0]].get('kind') else []),CATS) or []]
            own=next((tiers[x] for x in kinds_ if x in tiers),None)
            if own: tk=[k for k in tk if k==own or k not in set(tiers.values())|{'vdf'}]
        if 'ava' in tk and not f.get('ava'): tk=[k for k in tk if k!='ava']   # the AVA rule on an AVA page, not on a state or an informal region (California's Central Valley)   # what the words on its labels mean: its own terms, those of the regions above it, and terms for the place alone (Bordeaux Supérieur is not a Loupiac term)
        if tk:
            f['terms']=[[LT['terms'][k]['name'],LT['terms'][k]['def']] for k in dict.fromkeys(tk)]
            for k in dict.fromkeys(tk):
                a_=LT['terms'][k]['source']
                if a_.startswith('SRC:'):
                    if a_[4:] not in SRC and a_[4:] in LT.get('sources',{}): SRC[a_[4:]]=LT['sources'][a_[4:]]   # a law or official text the audit wrote the term from
                    src.append(a_[4:]); continue   # a term defined from one of the atlas's own sources (Wine Australia's GI levels)
                SRC.setdefault('term:'+a_,dict(name=f'Wikipedia, {a_} (what the label terms mean)',url=TA.get(a_))); src.append('term:'+a_)
        if KF.get(n,{}).get('facts'):   # the few things a Diploma student must know, from the place's full article (src/keyfacts.py)
            f['keyfacts']=[atlasland.text_names(x,n.split('/')[0]) for x in KF[n]['facts']]
            for i,c in enumerate(KF[n].get('cite') or []): SRC[f'kfcite:{n}:{i}']=c; src.append(f'kfcite:{n}:{i}')   # an official text the key-fact audit checked a fact against
            SOILW=re.compile(r'\b(soil|soils|slate|schist|limestone|chalk|granite|gravel|clay|marl|sand|volcanic|llicorella|albariza|terra rossa|loess|alluvial|pumice|basalt)\b',re.I)
            if any(SOILW.search(x) for x in f['keyfacts']):   # the key facts say what the vineyard soils are; map geology and a 1 km soil model would contradict them
                f.pop('rocks',None); f.pop('soil',None)
            if f.get('rules') and any(re.search(r'hl/ha|hectolit',x) for x in f['keyfacts']):
                for k in ('yield_hl','yield_kg','yield_base','yield_ceiling'): f['rules'].pop(k,None)   # the key facts give the base yields
            ap=os.path.join(ROOT,'data','cache','wikipedia','full',n.replace('/','__')+'.json')
            if os.path.exists(ap):
                a=jl(ap); SRC['kf:'+n]=dict(name=f'Wikipedia, {a["title"]}{"" if a["lang"]=="en" else " ("+a["lang"]+")"}, the full article (key facts)',url=a['url']); src.append('kf:'+n)
        sw=next(((c_,STY[c_]) for c_ in [n]+([c_[0] for c_ in chain[-1:] if '/' in c_[0]] if not f.get('rules') else []) if STY.get(c_,{}).get('notes')),None)   # an appellation with rules of its own makes its own wine: the region's notes would describe other wines (dry Entre-Deux-Mers on sweet Loupiac)   # its own notes, else its parent region's: one step only, since a whole state or country speaks badly for a cool corner of it (Sta. Rita Hills is not California at large)
        if sw and sw[0]!=n:   # a parent's note that names another place under it (Bío-Bío on Itata, Margaret River on the South East Coastal zone) does not describe this one
            mine={n}|{c_[0] for c_ in chain}
            others=[T[k]['name'] for k in below(sw[0]) if k not in mine and len(T[k]['name'])>=4]
            keep=[x for x in sw[1]['notes'] if not any(re.search(r'\b'+re.escape(o.replace(' Valley',''))+r'\b',x) for o in others)]
            sw=(sw[0],dict(sw[1],notes=keep)) if keep else None
        if sw:
            f['style']=dict(notes=[atlasland.text_names(x,n.split('/')[0]) for x in sw[1]['notes']])
            if sw[0]!=n: f['style']['of']=T[sw[0]]['name']
            for t_ in sw[1].get('art',[]):
                a_=style_.source(t_)
                if a_: SRC['style:'+t_]=dict(name=f'Wikipedia, {a_["title"]} (what the wines taste like)',url=a_['url']); src.append('style:'+t_)
            for r_ in sw[1].get('ref',[]):   # official specifications, national wine bodies and a GI register, where Wikipedia says nothing
                if r_ in STYR and not any(SRC.get(k_,{}).get('url')==STYR[r_]['url'] for k_ in src): SRC['style-ref:'+r_]=STYR[r_]; src.append('style-ref:'+r_)   # once only: the Rías Baixas pliego is already cited for its rules
        if n in BL:   # what the place is known for, written from its own facts and its Wikipedia intro (src/blurbs.py)
            f['blurb']=dict(text=re.sub(r'\.\.(?=\s|$)','.',atlasland.text_names(BL[n]['text'],n.split('/')[0]))); w=BL[n].get('wiki')
            f['blurb']['text']=national_terms(f['blurb']['text'],f.get('kind'))
            if w: SRC['wiki:'+n]=dict(name=f'Wikipedia, {w["title"]}{"" if w["lang"]=="en" else " ("+{"it":"Italian","fr":"French"}.get(w["lang"],w["lang"])+")"}, the opening of the article',url=w['url']); src.append('wiki:'+n)
            c_=BL[n].get('cite')   # a blurb written from an official text the page has no other use for (Chablis Premier Cru from the Chablis cahier)
            if c_: SRC['cite:'+n]=c_; src.append('cite:'+n)
        if n in BENCH: f['study']=True   # the gold sets follow the regions a wine-school syllabus covers (regions/wset.json, regions/wset-levels.json); by Chris's choice the pages do not name the school
        if lv(n)&3: f['levels']=[l for l,bit in ((2,1),(3,2)) if lv(n)&bit]
        if x['source']=='Wine Australia GI boundaries':
            pr=next((AU[m] for m in [geoindex_norm(v) for v in [t['name']]+t.get('also',[])] if m in AU),None)
            if pr: f['gi']={k:pr.get(v) for k,v in dict(type='GI_TYPE',number='GI_NUMBER',year='YEAR_REGISTER',area_km2='GI_AREA_KM2',vines_ha='VINE_AREA_HA',url='GI_URL',state='STATE').items()}
        src+=[k for k,v in SHAPE_SRC.items() if v==x['source']]
        sub=below(n)+ALSO_INSIDE.get(n,[])   # a region in two zones counts in both (Murray Darling and Swan Hill straddle the Victoria and New South Wales border)
        ac=list(dict.fromkeys([UCD_T.get(x,x) for x in (A.get(n) or {}).get('contains') or [] if x and t['name'] not in OVERLAP_OF.get(x,()) and x not in AVANOTCONTAINS.get(t['name'],())]
                              +([T[k]['name'] for k,v in A.items() if k!=n and k in T and t['name'] in (v.get('within') or [])] if n in A else [])))   # UC Davis lists El Dorado twice in Sierra Foothills (the AVA and the county); an AVA only partly inside is not counted; AVAs whose own "Inside" names this one count too (Fort Ross-Seaview in Sonoma Coast)
        if sub or ac:   # a region: what its places share
            st_=US_STATE.get(t['name']) if n.startswith('united-states/') and n.count('/')==1 else None
            if st_: sub=[k for k in sub if not (A.get(k) or {}).get('states') or st_ in {s.strip() for s in A[k]['states']}]   # Indiana does not hold West Virginia's Kanawha River Valley
            ap=[k for k in sub if k in E]; gc=collections.Counter(); sk={}
            for k in ap:
                for g,s in rules_of(k)['grapes']: gc[g]+=1; sk[g]=s
            gs=[CL[k]['climate']['gst'] for k in sub if k in CL and (CL[k].get('climate') or {}).get('gst') is not None]
            overlap=n in A and len(ac)>len(sub)   # an AVA whose sub-AVAs sit elsewhere in the tree (North Coast's are under Napa, Sonoma and Mendocino)
            f['summary']=dict(places=len(ac) if overlap else len(sub),kinds=collections.Counter(([k for k in T[s].get('official',[])] or ['region'])[0] for s in sub).most_common(),
                              grapes=[[g,sk[g],c] for g,c in gc.most_common(24) if c>=2],with_rules=len(ap),   # a grape in one record only says nothing about what is most often allowed
                              gst=[round(min(gs),1),round(max(gs),1)] if len(gs)>=2 and not overlap else None,   # a range needs two places: not "67 to 67" from Robertson alone
                              best=[k for k in sorted(sub,key=lambda k:-(N.get(k) or {}).get('score',-1))[:8] if k in N])
        if f.get('gi'): f['gi'].pop('vines_ha',None)   # Wine Australia's GI vine area carries no year, and the planting table gives a dated one where there is one
        if (AREA.get(n,0)>200000 or (t['depth']==1 and n.split('/')[0] in ('united-states','canada'))) and f.get('climate'):   # a state's warm ground is mostly where no vines grow (Washington's west side)   # a whole state's grid average describes the outback, not its vineyards (South Australia)
            f.pop('climate',None); f.pop('winkler',None)
            if f.get('reading'): f['reading'].pop('climate',None)
        if f.get('blurb') and n not in KF and not BL.get(n,{}).get('audited'): f['blurb']['text']=trim_blurb(f['blurb']['text'],f)   # a blurb the audit rewrote was checked against sources; the trimmer leaves it alone
        if f.get('terrain') and (x['source'] in AREA_SHAPES or (x['source']=='zone store' and n.startswith('argentina/'))) and n not in PLOTS:   # Argentina's stored zones are its departments: Luján de Cuyo's band ran up into the Andes   # a whole commune or district: its heights are not the vineyards' (Avize's plateau, Gattinara's plain)
            f.pop('terrain',None); f.pop('aspect',None)
            if f.get('reading'): f['reading'].pop('land',None)
            src=[s_ for s_ in src if s_ not in ('terrain','lapse')]
        if f.get('blurb') is not None and not f['blurb']['text']: f.pop('blurb')
        if WV.get(view_of(n)): src.append('osm-water')   # the map above the page draws rivers and lakes
        if view_of(n) in CV: src.append('geonames')   # and names a few towns
        f['sources']=[SRC[s] for s in dict.fromkeys(src)]
        json.dump(f,open(os.path.join(fd,n.replace('/','__')+'.json'),'w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
        places[n]=[t['name'],x['parent'],round((N.get(n) or {}).get('score',-1)),(kind or [''])[0],T[t['path'].split('/')[0]]['name'],f['also'],int(n in BENCH),lv(n),int(n in WS and n not in VINELESS)]   # the last: inside a classic region, by where it is alone, the map's light gold
    json.dump(dict(places=places),open(os.path.join(OUT,'places.json'),'w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
    print(f'{len(places)} places: {len(BENCH)} Benchmark ({len(WS)-len(BENCH)} inside Diploma regions with nothing of their own), {len(E)} with EU rules, {len(A)} AVAs, {len(CL)} with climate, {len(R)} researched, {len(N)} with a Wikipedia score')
# ---- climate and soil, worked out over each place's shape
CL=os.path.join(CA,'climate')
def raster(path):
    """A GeoTIFF as (array, x0, y0, dx, dy), read whole: the grids here are under 1.2 GB each and read one at a time."""
    import tifffile
    with tifffile.TiffFile(path) as t:
        p=t.pages[0]; g=p.geotiff_tags; sx,sy=g['ModelPixelScale'][:2]; tp=g['ModelTiepoint']; a=p.asarray()
    return a,tp[3],tp[4],sx,sy
def cells(g,x0,y0,dx,dy,shape):
    """Row and column of every grid cell whose middle is inside g, or the one cell under its representative point."""
    import numpy as np,shapely
    nr,nc=shape; minx,miny,maxx,maxy=g.bounds
    c0,c1=max(0,int((minx-x0)/dx)),min(nc,int((maxx-x0)/dx)+1); r0,r1=max(0,int((y0-maxy)/dy)),min(nr,int((y0-miny)/dy)+1)
    if c1>c0 and r1>r0:
        X,Y=np.meshgrid(x0+(np.arange(c0,c1)+.5)*dx,y0-(np.arange(r0,r1)+.5)*dy); shapely.prepare(g)
        rr,cc=np.nonzero(shapely.contains_xy(g,X,Y))
        if len(rr): return rr+r0,cc+c0
    q=g.representative_point(); return np.array([min(nr-1,max(0,int((y0-q.y)/dy)))]),np.array([min(nc-1,max(0,int((q.x-x0)/dx)))])
GST=[(13,'too cool for most grapes'),(15,'cool'),(17,'intermediate'),(19,'warm'),(21,'hot'),(24,'very hot'),(99,'too hot for most grapes')]
WINKLER=[(1389,'I'),(1667,'II'),(1944,'III'),(2222,'IV'),(1e9,'V')]
PH=[(4.5,'extremely acid'),(5.05,'very strongly acid'),(5.55,'strongly acid'),(6.05,'moderately acid'),(6.55,'slightly acid'),(7.35,'neutral'),(7.85,'slightly alkaline'),(8.45,'moderately alkaline'),(9.05,'strongly alkaline'),(99,'very strongly alkaline')]
def band(v,table): return next(n for t,n in table if v<t)
def texture(clay,sand,silt):   # the USDA soil texture triangle
    if silt+1.5*clay<15: return 'sand'
    if silt+2*clay<30: return 'loamy sand'
    if clay<7 and silt<50 or 7<=clay<20 and sand>52: return 'sandy loam'
    if 7<=clay<27 and 28<=silt<50 and sand<=52: return 'loam'
    if silt>=80 and clay<12: return 'silt'
    if silt>=50 and (12<=clay<27 or clay<12): return 'silt loam'
    if 20<=clay<35 and silt<28 and sand>45: return 'sandy clay loam'
    if 27<=clay<40 and 20<sand<=45: return 'clay loam'
    if 27<=clay<40 and sand<=20: return 'silty clay loam'
    if clay>=35 and sand>45: return 'sandy clay'
    if clay>=40 and silt>=40: return 'silty clay'
    return 'clay'
def climate():
    """Climate and soil for every place with a shape below the country level. Writes regions/atlas-climate.json."""
    guard(); import numpy as np
    from shapely import wkb
    from shapely.ops import transform  # noqa: the pyproj function form
    from pyproj import Transformer
    shp={n:wkb.loads(h,hex=True) for n,h in jl(os.path.join(OUT,'shapes.json')).items() if T[n]['depth']>0}
    lat={n:g.representative_point().y for n,g in shp.items()}
    out={n:dict(climate={},soil={}) for n in shp}; t0=time.time()
    # WorldClim: twelve months of temperature and of rain on one grid
    a,x0,y0,dx,dy=raster(os.path.join(CL,'worldclim','tavg','wc2.1_2.5m_tavg_01.tif'))
    idx={n:cells(g.simplify(.01),x0,y0,dx,dy,a.shape) for n,g in shp.items()}; print(f'worldclim cells {time.time()-t0:.0f}s',flush=True)
    grid=dict(x0=x0,y0=y0,dx=dx,dy=dy,shape=a.shape)
    cellv={n:{} for n in idx}
    for var in ('tavg','prec'):
        for m in range(12):
            a=raster(os.path.join(CL,'worldclim',var,f'wc2.1_2.5m_{var}_{m+1:02d}.tif'))[0]
            for n,(rr,cc) in idx.items(): cellv[n].setdefault(var,[]).append(a[rr,cc].astype('float64'))
        print(f'worldclim {var} {time.time()-t0:.0f}s',flush=True)
    # The vineyard mask: only the cells warm enough for wine grapes, a growing season of 13 °C or more (Jones's floor), count.
    # An outline drawn round a valley takes in the mountains above it; averaged whole, Marlborough or the Uco Valley come out
    # colder and wetter than any vineyard in them. Where no cell is that warm, the warmest quarter stands in.
    warm={}
    for n,(rr,cc) in idx.items():
        ta=np.array(cellv[n]['tavg']); pr=np.array(cellv[n]['prec']); ok=(ta>-1e30).all(0)&(pr>-1e30).all(0)
        gs=[9,10,11,0,1,2,3] if lat[n]<0 else [3,4,5,6,7,8,9]
        g=ta[gs].mean(0); keep=ok&(g>=13)
        if not keep.any() and ok.any(): keep=ok&(g>=np.quantile(g[ok],.75))
        if keep.any() and keep.sum()<.7*ok.sum() and g[keep].max()<17: keep=keep&(g>=g[keep].max()-1.5)   # cool and mostly hill: the vines take the warmest
        # ground, which a 4.5 km grid can only find as the cells nearest the warmest (the Wairau). Not in warm high country such as the Uco
        # Valley, where the warmest cells are the plains below the vineyards
        warm[n]=keep
        out[n]['climate']['tavg']=[round(float(ta[i][keep].mean()),1) if keep.any() else None for i in range(12)]
        out[n]['climate']['prec']=[round(float(pr[i][keep].mean()),1) if keep.any() else None for i in range(12)]
        out[n]['climate']['warm_share']=round(float(keep.sum()/max(1,ok.sum())),2)
    del cellv
    os.makedirs(OUT,exist_ok=True)
    json.dump(dict(grid=dict(x0=x0,y0=y0,dx=dx,dy=dy,shape=list(grid['shape'])),
                   cells={n:[[int(r),int(c)] for r,c,k in zip(idx[n][0],idx[n][1],warm[n]) if k] for n in idx}),
              open(os.path.join(OUT,'warmcells.json'),'w'),separators=(',',':'))
    WK={n:set(zip(idx[n][0][warm[n]].tolist(),idx[n][1][warm[n]].tolist())) for n in idx}
    def warm_at(n,lon,lat_,G=dict(grid)):   # which of these points fall in the place's warm cells (on the WorldClim grid, not the caller's)
        r=((G['y0']-lat_)/G['dy']).astype(int); c=((lon-G['x0'])/G['dx']).astype(int); S=WK[n]
        return np.array([(a_,b_) in S for a_,b_ in zip(r.tolist(),c.tolist())],dtype=bool)
    days=[31,28.25,31,30,31,30,31,31,30,31,30,31]
    for n,o in out.items():
        c=o['climate']; ta,pr=c.get('tavg'),c.get('prec')
        if not ta or None in ta or None in pr: o['climate']=None; continue
        gs=[9,10,11,0,1,2,3] if lat[n]<0 else [3,4,5,6,7,8,9]
        gst=sum(ta[i] for i in gs)/7; gdd=sum(max(0,ta[i]-10)*days[i] for i in gs)
        c.update(gst=round(gst,1),gst_class=band(gst,GST),gdd=round(gdd),winkler=band(gdd,WINKLER) if gdd>=850 else None,
                 rain=round(sum(pr)),gs_rain=round(sum(pr[i] for i in gs)),lat=round(lat[n],2),cells=int(len(idx[n][0])))
    del a,idx
    # Koppen-Geiger: the most common class
    leg={}
    for line in open(os.path.join(CL,'koppen','tif','legend.txt'),encoding='utf-8'):
        b=line.strip().split(':')
        if len(b)>1 and b[0].strip().isdigit(): w=b[1].split('[')[0].split(); leg[int(b[0])]=(w[0],' '.join(w[1:]))
    a,x0,y0,dx,dy=raster(os.path.join(CL,'koppen','tif','1991_2020','koppen_geiger_0p00833333.tif'))
    for n,g in shp.items():
        if not out[n]['climate']: continue
        rr,cc=cells(g.simplify(.004),x0,y0,dx,dy,a.shape); v=a[rr,cc]
        m=warm_at(n,x0+(cc+.5)*dx,y0-(rr+.5)*dy)
        if m.any(): v=v[m]
        v=v[v>0]
        if len(v): out[n]['climate']['koppen'],out[n]['climate']['koppen_name']=leg.get(int(np.bincount(v).argmax()),(None,None))
    del a; print(f'koppen {time.time()-t0:.0f}s',flush=True)
    # SoilGrids: the typical (median) value, on the Homolosine grid
    to=Transformer.from_crs(4326,'+proj=igh +lon_0=0 +datum=WGS84 +units=m +no_defs',always_xy=True).transform
    sg=os.path.join(CL,'soilgrids'); idx=None; vals={}
    for prop in ('clay','sand','phh2o','cfvo'):
        a,x0,y0,dx,dy=raster(os.path.join(sg,f'{prop}_30-60cm_mean_1000.tif'))
        if idx is None: idx={n:cells(transform(to,g).simplify(400),x0,y0,dx,dy,a.shape) for n,g in shp.items()}
        if prop=='clay':
            inv=Transformer.from_crs('+proj=igh +lon_0=0 +datum=WGS84 +units=m +no_defs',4326,always_xy=True).transform
            wmask={}
            for n,(rr,cc) in idx.items():
                lo,la=inv(x0+(cc+.5)*dx,y0-(rr+.5)*dy); m=warm_at(n,np.asarray(lo),np.asarray(la)); wmask[n]=m if m.any() else np.ones(len(rr),bool)
        for n,(rr,cc) in idx.items():
            v=a[rr,cc][wmask[n]]; v=v[(v>=0)&(v<32000)]
            if prop!='cfvo': v=v[v>0]
            vals.setdefault(n,{})[prop]=float(np.median(v))/10 if len(v) else None
        del a; print(f'soil {prop} {time.time()-t0:.0f}s',flush=True)
    for n,v in vals.items():
        if None in (v['clay'],v['sand'],v['phh2o']): out[n]['soil']=None; continue
        clay,sand=round(v['clay']),round(v['sand']); silt=max(0,100-clay-sand)
        out[n]['soil']=dict(clay=clay,sand=sand,silt=silt,texture=texture(clay,sand,silt),ph=round(v['phh2o'],1),ph_class=band(v['phh2o'],PH),
                            stones=round(v['cfvo']) if v['cfvo'] is not None else None,cells=int(len(idx[n][0])))
    json.dump({'$about':'Climate and soil over each place\'s shape. Built by src/atlas.py climate; sources and method in its docstring.',
               'places':{n:o for n,o in sorted(out.items()) if o['climate'] or o['soil']}},open(os.path.join(ROOT,'regions','atlas-climate.json'),'w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
    print(f'{sum(1 for o in out.values() if o["climate"])} with climate, {sum(1 for o in out.values() if o["soil"])} with soil, {time.time()-t0:.0f}s')
# ---- the page
def site(dest=None):
    """Write the finished site to public/, which is what Vercel serves. Built beside it and swapped in, so public/ is never half written."""
    dest=dest or os.path.join(ROOT,'public'); new=os.path.join(ROOT,'build','public-new'); old=os.path.join(ROOT,'build','public-old')
    if not os.path.exists(os.path.join(OUT,'places.json')): raise SystemExit('No data yet. Run: make data')
    junk=shutil.ignore_patterns('* [0-9].*','* [0-9][0-9].*','.DS_Store')   # iCloud's conflict copies ("x 2.json") and Finder's files
    for p in (new,old): shutil.rmtree(p,ignore_errors=True)
    shutil.copytree(os.path.join(ROOT,'web'),new,ignore=junk)
    for sub in ('geo','facts'): shutil.copytree(os.path.join(OUT,sub),os.path.join(new,sub),ignore=junk)
    shutil.copy2(os.path.join(OUT,'places.json'),os.path.join(new,'places.json'))
    if os.path.exists(dest): os.rename(dest,old)
    os.rename(new,dest); shutil.rmtree(old,ignore_errors=True)
    print(f'atlas: written to {os.path.relpath(dest,ROOT)}/')
if __name__=='__main__':
    cmd=sys.argv[1] if len(sys.argv)>1 else ''
    if cmd=='fetch': fetch()
    elif cmd=='geo': geo()
    elif cmd=='climate': climate()
    elif cmd=='facts': facts()
    elif cmd=='site': site(sys.argv[2] if len(sys.argv)>2 else None)
    else: raise SystemExit(__doc__)
