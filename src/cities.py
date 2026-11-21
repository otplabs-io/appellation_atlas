#!/usr/bin/env python3
"""Towns and cities on the maps, for bearings: a few on each view, from GeoNames' towns of 5,000 people or more (CC BY 4.0).
The towns a page names come first (Beaune, Épernay, Hermanus), then the biggest places, kept well apart.
Usage: python src/cities.py list     the towns each view would show
Input: data/cache/geonames/cities5000.txt and countryInfo.txt (https://download.geonames.org/export/dump/)."""
import json,math,os,re,struct,sys,unicodedata
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.path.dirname(HERE)
TOWNS=os.path.join(ROOT,'data','cache','geonames','cities5000.txt'); COUNTRIES=os.path.join(ROOT,'data','cache','geonames','countryInfo.txt')
SRC=dict(name='GeoNames, towns of 5,000 people or more (cities5000), CC BY 4.0, for the towns on the map',url='https://download.geonames.org/export/dump/')
MOST=4          # towns on a view, besides those its pages name
NAMED_MOST=4    # towns its pages name
APART=.12       # at least this share of the view's width between two towns

def towns():
    """GeoNames' towns of 5,000 people or more: name, country, people, capital, place."""
    global _TOWNS
    if _TOWNS is None:
        cn={}
        for line in open(COUNTRIES,encoding='utf-8'):
            if line.startswith('#'): continue
            c=line.rstrip('\n').split('\t')
            if len(c)>4: cn[c[0]]=c[4]
        _TOWNS=[]
        for line in open(TOWNS,encoding='utf-8'):
            c=line.rstrip('\n').split('\t')
            _TOWNS.append(dict(n=c[1],a=c[2],c=cn.get(c[8],c[8]),pop=int(c[14] or 0),cap=c[7]=='PPLC',lon=float(c[5]),lat=float(c[4])))
    return _TOWNS
_TOWNS=None

def fold(s): return unicodedata.normalize('NFKD',s).encode('ascii','ignore').decode()   # case kept: Tours the town, not wine tours

def area(outline):
    from shapely.geometry import Polygon
    from shapely.ops import unary_union
    ps=[]
    for poly in outline or []:
        rings=[list(zip(r[0::2],r[1::2])) for r in poly if len(r)>=6]
        if rings: ps.append(Polygon(rings[0],rings[1:]).buffer(0))
    return unary_union(ps) if ps else None

def attach(V,texts):
    """Give each view with a box a short list of towns: {n, c:[lon, lat]}. texts: {place id: what its page says}.
    Returns the views given towns."""
    if not os.path.exists(TOWNS): print('cities: no GeoNames table, skipped'); return set()
    from shapely.geometry import Point
    from shapely.prepared import prep
    T=towns(); out=set(); F={k:fold(t) for k,t in texts.items()}
    for vid,v in V.items():
        b=v.get('box')
        if not b: continue   # the world view: countries only
        own=area(v.get('outline'))
        if own is None or own.is_empty: continue
        ob=own.bounds; span=min(max(ob[2]-ob[0],ob[3]-ob[1]),max(b[2]-b[0],b[3]-b[1])); gap=APART*span   # the box, where the outline takes in far islands (Réunion, the Chathams)
        near=prep(own.buffer(.15*span))   # the place itself and a little around it: the Napa map names Napa and Vallejo, not Billings
        home=(V.get(vid.split('/')[0]) or {}).get('name')   # the view's own country: a map of France names French towns, not London
        inside=[t for t in T if b[0]<=t['lon']<=b[2] and b[1]<=t['lat']<=b[3] and (not home or t['c']==home) and near.contains(Point(t['lon'],t['lat']))]
        if not inside: continue
        ids={vid}|{i['id'] for i in v.get('items',[]) if i.get('id')}
        words=' '.join(F.get(i,'') for i in ids)
        named=[] if '/' not in vid else [t for t in inside if len(t['a'])>3 and fold(t['a']) in words and re.search(r'(?<![\w-])'+re.escape(fold(t['a']))+r'(?![\w-])',words)]   # a whole country goes by size; a name standing alone (not Tours-sur-Marne)
        pick=[]
        def far(t): return all(math.hypot((t['lon']-p['lon'])*math.cos(math.radians(t['lat'])),t['lat']-p['lat'])>=gap for p in pick)
        for t in sorted(named,key=lambda t:-t['pop']):
            if len(pick)<NAMED_MOST and far(t): pick.append(t)
        k=len(pick)
        for t in sorted(inside,key=lambda t:(-t['cap'],-t['pop'])):
            if len(pick)>=k+MOST: break
            if t['pop']>=50000 and far(t): pick.append(t)
        if pick:
            v['cities']=[dict(n=t['n'],c=[round(t['lon'],4),round(t['lat'],4)]) for t in pick]; out.add(vid)
    return out

if __name__=='__main__':
    import glob,water
    V={}
    for f in glob.glob(os.path.join(ROOT,'build','atlas','geo','views','*.json')):
        v=json.load(open(f,encoding='utf-8')); V[v['id']]=v
    attach(V,water.texts())
    for vid in sorted(V)[:int(sys.argv[2]) if len(sys.argv)>2 else 400]:
        if V[vid].get('cities'): print(vid,'|',', '.join(c['n'] for c in V[vid]['cities']))
