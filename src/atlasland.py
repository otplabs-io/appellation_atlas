#!/usr/bin/env python3
"""The Appellation Atlas: what is planted in each place, and the lie of its land. Atlas only.
Usage: python src/atlasland.py plant     grapes planted around every place (regions/atlas-plantings.json)
       python src/atlasland.py terrain   elevation, slope and the way the slopes face (regions/atlas-terrain.json)
       python src/atlasland.py plots     the same terrain measures over each grand cru's own vineyard (regions/atlas-plots.json)
       python src/atlasland.py rocks     the rock families beneath every place, from Macrostrat (regions/atlas-rocks.json)
Plantings come from Anderson, Nelgen and Puga, the Database of Regional, National and Global Winegrape Bearing Areas by
Variety (University of Adelaide, CC BY 4.0): bearing hectares by variety for about 700 regions. Each region gets a
boundary (an atlas place of that name, a Eurostat NUTS region, a US county, a Chilean region or an Argentine department);
a place then takes the regions that lie mostly inside it, or else the smallest region around it, and says which.
Terrain comes from the AWS Terrain Tiles (Terrarium; SRTM, GMTED and others), read at a zoom that keeps each place to a
few dozen tiles: the 10th, 50th and 90th percentile of elevation, the average slope and the share of sloping ground
facing each way. Both run over the place's own boundary (build/atlas/shapes.json, from src/atlas.py geo)."""
import collections,json,math,os,re,sys,time,urllib.request
HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE)
ROOT=os.path.dirname(HERE); OUT=os.path.join(ROOT,'build','atlas'); CA=os.path.join(ROOT,'data','cache')
def jl(p): return json.load(open(p,encoding='utf-8'))
T=jl(os.path.join(ROOT,'regions','tree.json'))['nodes']
def norm(s): import geoindex; return geoindex.norm(s)
def shapes():
    from shapely import wkb
    import atlas; atlas.seed()
    return {n:wkb.loads(h,hex=True) for n,h in jl(os.path.join(OUT,'shapes.json')).items()}
def parents():
    return {n:x['parent'] for n,x in jl(os.path.join(OUT,'geo','index.json'))['places'].items()}

# ---------- plantings
ANDERSON='https://doi.org/10.25909/32870405.v1'
YEAR={'Germany':2016,'Hungary':2016,'United States':2016}   # these break down by wine region or county in 2016, by state or district in 2023
NAME={'Garnacha Tinta':'Grenache','Côt':'Malbec','Mazuelo':'Carignan','Tribidrag':'Zinfandel','Monastrell':'Mourvèdre','Douce Noire':'Bonarda',
      'Prosecco':'Glera','Tempranillo (W)':'Tempranillo Blanco','Muscat Blanc à Petits Grains':'Muscat Blanc','Alicante Henri Bouschet':'Alicante Bouschet','Graševina':'Welschriesling',
      'Durif':'Petite Sirah'}
# Not wine grapes, so left out of what is planted. Table and raisin grapes from VIVC (regions/table-grapes.json). In the United States the
# county surveys count every vine, juice grapes too: USDA's grape survey asks about juice-type grapes apart from wine-type ones, and
# Concord and Niagara are the juice grapes it means first.
TABLE=set(jl(os.path.join(ROOT,'regions','table-grapes.json'))['table'])
TABLE_IN={'france':{'Muscat of Hamburg'},'argentina':{'Superior Seedless','Cardinal','Alphonse Lavallée'}}   # VIVC: table grapes (Argentina's INV rows count them)   # in France it is the Muscat du Ventoux table-grape AOP's grape, not a wine grape
JUICE={'united-states':{'Concord','Niagara'}}
# rows the database names wrongly: Sardinia's 7,064 ha are Cannonau, which Sardinians also call Alicante, not Alicante Bouschet
ROWFIX={('Italy','Sardegna','Alicante Henri Bouschet'):'Garnacha Tinta',
        ('Argentina','*','Muscat Blanc à Petits Grains (G)'):'Moscatel Rosado',
        ('Chile','*','Alicante Henri Bouschet'):'Tintoreras (red-fleshed grapes)'}   # SAG's census counts 142 ha of Alicante Bouschet and 6,766 ha of its Tintoreras group; the database's 6,908 ha is both   # Argentina's pink Muscat is its own variety, Moscatel Rosado (INTA)
WINE_IN={'japan':{'Campbell Early'}}   # crushed for wine in Japan, though VIVC lists it as a table grape
def not_wine(g,c):
    if g in WINE_IN.get(c,()): return None
    return 'table' if g in TABLE or g in TABLE_IN.get(c,()) else 'juice' if g in JUICE.get(c,()) else None
# The names the Diploma uses, over the database's prime names: one table for planted lists, rules and climate lines alike.
NAME.update({'Sultaniye':'Sultana','Vidal':'Vidal Blanc','Sauvignon Blanc (G)':'Sauvignon Gris','Pinot Meunier':'Meunier','Meunier':'Meunier',
             'Tocai Friulano':'Friulano','Sauvignonasse':'Friulano','Muscat Blanc à Petits Grains':'Muscat Blanc','Mazuela':'Mazuelo',
             'Müller Thurgau':'Müller-Thurgau','Mueller Thurgau':'Müller-Thurgau','Weißer Riesling':'Riesling','Weisser Riesling':'Riesling'})
NAME.update({'Gamay Noir':'Gamay','Cinsaut':'Cinsault','Garnacha Roja (Gris)':'Grenache Gris','Muscat Blanc à Petits Grains (G)':'Muscat Blanc',
             'Muscat Blanc à Petits Grains (R)':'Muscat Blanc','Muscat Blanc à Petits Grains (Rg)':'Muscat Blanc'})
LOCAL={'australia':{'Syrah':'Shiraz','Sémillon':'Semillon'},'south-africa':{'Syrah':'Shiraz','Sémillon':'Semillon','Chenin Blanc':'Chenin Blanc'},
       'new-zealand':{'Alvarinho':'Albariño'},'united-states':{'Alvarinho':'Albariño'},'france':{'Silvaner':'Sylvaner'},
       'spain':{'Alvarinho':'Albariño','Trajadura':'Treixadura','Vinhao':'Sousón','Borraçal':'Caíño Tinto','Mazuelo':'Mazuelo'},
       'portugal':{'Tempranillo':'Tinta Roriz','Mencía':'Jaen','Damaschino':'Alicante Branco'},
       'italy':{'Pinot Gris':'Pinot Grigio','Pinot Noir':'Pinot Nero','Pinot Blanc':'Pinot Bianco','Muscat Blanc':'Moscato Bianco','Sauvignonasse':'Friulano'},
       'germany':{'Pinot Noir':'Spätburgunder','Pinot Gris':'Grauburgunder','Pinot Blanc':'Weissburgunder','Schiava Grossa':'Trollinger','Blauer Spätburgunder':'Spätburgunder',
                 'Blaufränkisch':'Lemberger','Blauer Limberger':'Lemberger','Pinot Meunier':'Schwarzriesling','Meunier':'Schwarzriesling','Müllerrebe':'Schwarzriesling','Chasselas':'Gutedel'},   # the names German labels and statistics use
       'austria':{'Pinot Blanc':'Weissburgunder','Muscat Blanc':'Gelber Muskateller','Pinot Noir':'Blauburgunder'},
       'hungary':{'Grasă de Cotnari':'Kövérszőlő','Muscat Blanc':'Sárga Muskotály'},
       'chile':{'Listán Prieto':'País'},'argentina':{'Listán Prieto':'Criolla Chica'},'slovenia':{'Savagnin Blanc':'Traminer'},'czechia':{'Savagnin Blanc':'Traminer'}}
LOCAL['austria']['Savagnin Blanc']='Traminer'
import re as _re
TEXT=[(r'\bPinot noir\b','Pinot Noir'),(r'\bSauvignon blanc\b','Sauvignon Blanc'),(r'\bChenin blanc\b','Chenin Blanc'),(r'\bCabernet sauvignon\b','Cabernet Sauvignon'),
      (r'\bCabernet franc\b','Cabernet Franc'),(r'\bPinot [Mm]eunier\b','Meunier'),(r'\bPinot gris\b','Pinot Gris'),(r'\bPinot blanc\b','Pinot Blanc'),
      (r'\bPinot grigio\b','Pinot Grigio'),(r'\bPinot nero\b','Pinot Nero'),(r'\bGamay Noir\b','Gamay'),(r'\bCinsaut\b','Cinsault'),(r'\bCarmenere\b','Carmenère'),
      (r'\bvitis vinifera\b','Vitis vinifera'),(r'Garnacha Roja \(Gris\)','Grenache Gris'),(r' \((?:G|R|Rg)\)',''),(r'\bCarménère\b','Carmenère'),(r'\bEchézeaux\b','Échezeaux'),(r'\bMEGA\b','MGA'),(r'\bMelon de Bourgogne\b','Melon'),(r'\bBrun Argente\b','Brun Argenté'),(r'\bFetească Neagrăn\b','Fetească Neagră'),(r'\bBăbeasacă\b','Băbească'),(r'\bRkatiteli\b','Rkatsiteli'),(r'\bRiesling Italian\b','Welschriesling'),(r'\bSauvignon Blanc Gris\b','Sauvignon Gris')]
TEXT_IN={'australia':[(r'\bSyrah\b','Shiraz'),(r'\bSémillon\b','Semillon')],'south-africa':[(r'\bSyrah\b','Shiraz'),(r'\bSémillon\b','Semillon')],
         'new-zealand':[(r'\bAlvarinho\b','Albariño')],'spain':[(r'\bAlvarinho\b','Albariño')],'france':[(r'\bSilvaner\b','Sylvaner'),(r'\bSemillon\b','Sémillon')],'germany':[(r'\bPinot Noir\b','Spätburgunder')],'spain':[(r'\bAlvarinho\b','Albariño'),(r'\bDOP\b','DO')],'portugal':[(r'\bTempranillo\b','Tinta Roriz'),(r'\bMencía\b','Jaen')],'hungary':[(r'\b[Oo]laszrizling\b','Welschriesling')],'slovenia':[(r'\bLaški [Rr]izling\b','Welschriesling')],'italy':[(r'\bMuscat Blanc\b','Moscato Bianco')]}
def text_names(t,c):
    """Grape names in running text, made to match the tables: Shiraz in Australia, Pinot Noir not Pinot noir, no (G) or (R)."""
    for a,b in TEXT+TEXT_IN.get(c,[]): t=_re.sub(a,b,t)
    return _re.sub(r'\b([\w\u00C0-\u017F][\w\u00C0-\u017F ]*?) \(\1\)',r'\1',t)   # "Spätburgunder (Pinot Noir)" renamed to "Spätburgunder (Spätburgunder)" 
LAW_APART={'Malvasia Bianca'}
def rule_name(g,c):
    """A grape as a rules list names it, in the Diploma's word: the law's own name (Tinta Negra, Aragonez) unless it is a mere spelling of
    the prime (Sauvignon, Cot, Semillon), and without the law's colour codes ("Listrão R")."""
    import unicodedata
    fold=lambda x:unicodedata.normalize('NFKD',x).encode('ascii','ignore').decode().lower().replace(' ','')
    g=_re.sub(r' (?:R|B|N|G|Rs|Rg)$','',g.strip())
    if c=='italy' and g=='Bonarda': return 'Bonarda Piemontese'   # Italy's register calls Bonarda Piemontese plain "Bonarda N"; not Croatina, not Argentina's Bonarda (Douce Noire)
    if g in LAW_APART: return text_names(g,c)   # Italy's national register lists Malvasia Bianca and Malvasia Bianca di Candia as two grapes; the synonym list joins them
    p=prime(g)
    if _re.search(r' \((?:R|Rg|G|Rs)\)$',p) and fold(g)!=fold(p): return text_names(g,c)   # a colour form the law lists apart (Muscat à Petits Grains Roses beside its white)
    d=display(g,c) if (fold(g) in fold(p) or fold(p) in fold(g) or g in NAME or p in NAME) else LOCAL.get(c,{}).get(p) or LOCAL.get(c,{}).get(g,g)
    return text_names(d,c)
def display(g,c):
    """A grape's name as the Diploma gives it for country c: Shiraz in the Barossa, Spätburgunder in the Pfalz, Albariño in Rías Baixas."""
    p=prime(g); d=NAME_IN.get(c,{}).get(p) or NAME.get(p) or (p if p!=g else NAME.get(g,g))
    return LOCAL.get(c,{}).get(d,d)
NAME_IN={'germany':{'Pinot Noir Précoce':'Frühburgunder'},'spain':{'Garnacha Tinta':'Garnacha','Monastrell':'Monastrell','Mazuelo':'Mazuelo'},'italy':{'Tribidrag':'Primitivo','Garnacha Tinta':'Cannonau','Mazuelo':'Carignano'},
         'croatia':{'Tribidrag':'Crljenak Kaštelanski','Graševina':'Graševina'},'france':{'Douce Noire':'Douce Noire','Garnacha Blanca':'Grenache Blanc','Trebbiano Toscano':'Ugni Blanc','Garnacha Tinta':'Grenache','Mazuelo':'Carignan'}}
COUNTRY={'Turkiye':'turkey','Korea, Rep.':None}
STATE={'australia':{'tas':'tasmania'},'united-states':{'northwillamettevalley':'willamettevalley','southwillamettevalley':'willamettevalley'}}
WINE_REGIONS={'germany','austria','hungary','australia','new-zealand','south-africa','united-states'}   # the database names wine regions here, not administrative ones   # the database's state abbreviation where it is the whole state
NUTS={'austria':'AT','belgium':'BE','bulgaria':'BG','croatia':'HR','cyprus':'CY','czechia':'CZ','denmark':'DK','france':'FR','germany':'DE','greece':'EL',
      'hungary':'HU','italy':'IT','luxembourg':'LU','malta':'MT','netherlands':'NL','portugal':'PT','romania':'RO','slovakia':'SK','slovenia':'SI','spain':'ES',
      'switzerland':'CH','united-kingdom':'UK','north-macedonia':'MK','serbia':'RS','turkey':'TR'}
def rows(year):
    p=os.path.join(CA,'anderson',f'regional-{year}.json')
    if not os.path.exists(p):
        import openpyxl
        x=os.path.join(CA,'anderson',f'regional-{year}.xlsx')
        if not os.path.exists(x): urllib.request.urlretrieve({2016:'https://ndownloader.figshare.com/files/66222875',2023:'https://ndownloader.figshare.com/files/66222878'}[year],x)
        ws=openpyxl.load_workbook(x,read_only=True)['All countries']
        json.dump([list(r[:10]) for r in list(ws.iter_rows(values_only=True))[1:]],open(p,'w'),ensure_ascii=False,default=str)
    return jl(p)
_PRIME=None
def prime(name):
    """The database's prime name for a grape, from its synonym list (Garnacha Tinta for Grenache noir), or the name itself."""
    global _PRIME
    if _PRIME is None:
        p=os.path.join(ROOT,'regions','grape-synonyms.json')
        if not os.path.exists(p):
            import openpyxl
            x=os.path.join(CA,'anderson','synonyms.xlsx')
            os.makedirs(os.path.dirname(x),exist_ok=True)
            if not os.path.exists(x): urllib.request.urlretrieve('https://ndownloader.figshare.com/files/66222863',x)
            ws=openpyxl.load_workbook(x,read_only=True)['Synonyms and primes']
            json.dump({str(r[1]).strip():r[0] for r in list(ws.iter_rows(values_only=True))[1:] if r[0] and r[0]!='other' and r[1]},open(p,'w'),ensure_ascii=False)
        _PRIME={norm(k):v for k,v in jl(p).items()}; _PRIME.update({norm(v):v for v in sorted(set(_PRIME.values()))})
    return _PRIME.get(norm(name)) or _PRIME.get(norm(re.sub(r'\s+(noir|blanc|rouge|n|b|g|rs|rg)$','',name,flags=re.I))) or name
def legal(planted,rules):
    """For each grape planted, whether the appellation's rules let it into a wine sold under the appellation's name:
    'main' (a named grape), 'minor' (allowed in a smaller role), or 'no' (it has to be sold under another name)."""
    main={prime(g) for g,*_ in rules.get('grapes',[])}; minor={prime(g if isinstance(g,str) else g[0]) for g in rules.get('grapes_other',[])}
    return ['main' if g[3] in main else 'minor' if g[3] in minor else 'no' if g[0]!='Other' else '' for g in planted['grapes']]
def clean(s):
    s=re.sub(r'-\s*\n\s*','',str(s or '')).replace('\n',' ').replace('\xa0',' ').strip()
    s=re.sub(r'^\d+:\s*','',s); s=re.sub(r'\s*-\s*other$|\s*\((NSW|Vic|SA)\)$','',s,flags=re.I)
    return s.strip()
def boundaries():
    """Name -> geometry lookups for the places a region of the database can be: atlas places, NUTS, US counties, Chile, Argentina."""
    from shapely.geometry import shape
    S=shapes(); look=collections.defaultdict(dict)
    for n,g in S.items():
        c=n.split('/')[0]
        for m in [T[n]['name']]+T[n].get('also',[]):
            k=norm(m)
            if k and (k not in look[c] or T[n]['depth']<T[look[c][k][1]]['depth']): look[c][k]=(g,n)
    nuts=collections.defaultdict(dict)
    for L in (3,2,1):
        for f in jl(os.path.join(CA,'gisco',f'NUTS_RG_01M_2021_4326_LEVL_{L}.geojson'))['features']:
            p=f['properties']
            for m in {p['NUTS_NAME'],p['NAME_LATN']}:
                k=norm(m)
                if k: nuts[p['CNTR_CODE']].setdefault(k,(f['geometry'],p['NAME_LATN']))
    county=collections.defaultdict(dict)
    for f in jl(os.path.join(CA,'us-counties.json'))['features']: county[f['properties']['STATE']][norm(f['properties']['NAME'])]=(f['geometry'],f['properties']['NAME']+' County')
    chile={}
    for f in jl(os.path.join(CA,'chile','CHL_ADM1.geojson'))['features']:
        nm=f['properties']['shapeName']
        try: nm=nm.encode('latin1').decode('utf8')
        except UnicodeError: pass
        short=re.sub(r'^Regi[oó]n (de los |de la |del |de )?|\s+de Santiago$|\s+y .*$|\s+del Gral.*$','',nm); chile[norm(short)]=(f['geometry'],short)
    chile['ohiggins']=next((f['geometry'],"O'Higgins") for f in jl(os.path.join(CA,'chile','CHL_ADM1.geojson'))['features'] if 'Higgins' in f['properties']['shapeName'])
    chile['lbohiggins']=chile['ohiggins']; chile['delbiobio']=chile.get('biobio'); chile['delmaule']=chile.get('maule'); chile['deloslagos']=chile.get('loslagos')
    arg=collections.defaultdict(list)
    for f in jl(os.path.join(CA,'argentina','ARG_ADM2.geojson'))['features']: arg[norm(f['properties']['shapeName'])].append((f['geometry'],f['properties']['shapeName']))
    return S,look,nuts,county,chile,arg,shape
# Official figures where the database is plainly wrong. Its 2022 row for Vienna gives Riesling 274 of 561 ha (49%); Statistik
# Austria's 2020 census counts 87 ha of 667 (13%), with Grüner Veltliner first at 200 ha, as the database's own 2016 row had it.
OFFICIAL={'austria/wien':dict(table='RebsortenNachBL2020.ods',column='Wien',year=2020,source='statistik-austria')}
def austria_census(column):
    """Hectares by variety for one state, from Statistik Austria's Weingartengrunderhebung 2020 (data/cache/statistik-austria)."""
    import zipfile,xml.etree.ElementTree as ET
    T_='{urn:oasis:names:tc:opendocument:xmlns:table:1.0}'; P_='{urn:oasis:names:tc:opendocument:xmlns:text:1.0}p'
    root=ET.fromstring(zipfile.ZipFile(os.path.join(CA,'statistik-austria','RebsortenNachBL2020.ods')).read('content.xml'))
    rows=[]
    for r in root.iter(T_+'table-row'):
        cells=[]
        for c in r.findall(T_+'table-cell'):
            cells+=[' '.join(''.join(x.itertext()) for x in c.findall(P_))]*min(int(c.get(T_+'number-columns-repeated','1')),12)
        rows.append(cells)
    head=next(r for r in rows if r and r[0]=='Rebsorte'); col=head.index(column)+1   # the Austria column is split into 2015 and 2020
    out=collections.Counter(); colour={}; skin=None; skip=False
    for r in rows:
        if not r or not r[0]: continue
        if r[0] in ('Weißwein','Rotwein'): skin='W' if r[0]=='Weißwein' else 'R'; skip=False; continue
        if r[0]=='darunter': skip=True; continue   # the lines under "darunter" are already inside "Andere ..."
        if r[0]=='zusammen' or skin is None or len(r)<=col: skip=False if r[0]=='zusammen' else skip; continue
        if skip and not r[0].startswith('Gemischter Satz'): continue
        v=r[col].replace(' ','').replace(',','.')
        try: ha=float(v)
        except ValueError: continue
        names=[r[0].split(' (')[0]]+[x.strip() for x in re.findall(r'\(([^)]*)\)',r[0]) for x in x.split(',')]
        g=next((prime(x) for x in names if prime(x)!=x),None) or ('other' if re.match(r'Andere|Gemischter',r[0]) else names[0])
        out[g]+=ha; colour[g]=skin
    return out,colour
def plant():
    from shapely.geometry import shape as _s
    from shapely.strtree import STRtree
    S,look,nuts,county,chile,arg,shape=boundaries(); P=parents()
    cid={norm(t['name']):n for n,t in T.items() if t['depth']==0}
    regs=[]; national=collections.defaultdict(lambda:collections.Counter()); colour={}; nyear={}; unplaced=collections.Counter(); rowyear={}
    have={y:{r[0] for r in rows(y)} for y in (2016,2023)}
    years={c:(YEAR.get(c,2023) if c in have[YEAR.get(c,2023)] else 2016) for c in have[2016]|have[2023]}
    by=collections.defaultdict(lambda:collections.defaultdict(collections.Counter))
    for y in (2016,2023):
        R=rows(y); latest=collections.defaultdict(int)   # France's 2023 file carries a 2022 and a 2023 row for some grapes in a region:
        yr=lambda r:int(r[6]) if str(r[6] or '').strip().isdigit() else 0   # keep the newer of the two. Rows with no year are not duplicates
        for r in R: latest[tuple(r[:5])]=max(latest[tuple(r[:5])],yr(r))
        for r in R:
            if years.get(r[0])!=y or (yr(r) and yr(r)!=latest[tuple(r[:5])]): continue
            c=COUNTRY.get(r[0],cid.get(norm(r[0])))
            if not c or not r[5]: continue
            g=ROWFIX.get((r[0],r[1],r[4])) or ROWFIX.get((r[0],'*',r[4])) or r[4] or 'other'; colour[g]=r[8]; national[c][g]+=float(r[5]); nyear[c]=y; rowyear[c]=max(rowyear.get(c,0),yr(r))
            path=tuple(clean(x) for x in r[1:4] if clean(x))
            if path: by[c][path][g]+=float(r[5])
    named=collections.defaultdict(dict)   # every atlas place by name, shape or not
    for n,t in T.items():
        if n in P and t['depth']>0:
            for m in [t['name']]+t.get('also',[]): named[n.split('/')[0]].setdefault(norm(m),n)
    direct=collections.defaultdict(lambda:[collections.Counter(),[],0])
    for c,paths in by.items():
        for path,cnt in paths.items():
            nm=path[-1]; k=STATE.get(c,{}).get(norm(nm),norm(nm)); g=None; label=nm; hit=None
            def within_prov(n_):   # Argentina repeats department names across provinces: San Juan's San Martín is not Mendoza's
                if c!='argentina' or len(path)<2: return True
                up=[]; p_=P.get(n_)
                while p_: up.append(norm(T[p_]['name']) if p_ in T else ''); p_=P.get(p_)
                return norm(path[0]) in up
            if k in named[c] and not (c=='united-states' and k in county['06']) and within_prov(named[c][k]): d=direct[named[c][k]]; d[0].update(cnt); d[1].append(T[named[c][k]]['name']); d[2]=nyear[c]
            if k in ('','other','total','otherregions','noassociatedava','otherunverified') or k.endswith('total'): unplaced[c]+=sum(cnt.values()); continue
            hit=None
            if c=='united-states': hit=county['06'].get(k) or ((look[c][k][0],T[look[c][k][1]]['name']) if k in look[c] else None) or county['36'].get(k)
            elif c=='argentina':
                prov=look[c].get(norm(path[0]),(None,None))[0] if len(path)>1 else None
                hit=next(((_s(x),l) for x,l in arg.get(k,[]) if prov is None or prov.buffer(.05).contains(_s(x).representative_point())),None)
            elif c=='chile': hit=chile.get(k)
            own=(look[c][k][0],T[look[c][k][1]]['name']) if k in look[c] else None
            adm=nuts[NUTS[c]].get(k) if c in NUTS else None
            if hit is None: hit=(own or adm) if c in WINE_REGIONS else (adm or own)   # a département is drawn as the département, a wine region as itself
            if hit: g,label=hit
            if isinstance(g,dict): g=_s(g)
            if g is None or g.is_empty: unplaced[c]+=sum(cnt.values()); continue
            regs.append(dict(c=c,name=label,g=g.buffer(0),cnt=cnt,year=nyear[c]))
    tree=STRtree([r['g'] for r in regs]); area=[r['g'].area for r in regs]
    def pack(cnt,c):
        nm=lambda g:display(g,c)
        left={}   # the table and juice grapes taken out, biggest first, by what they are grown for
        for g,v in cnt.most_common():
            k=not_wine(g,c)
            if k and v>=.5: left.setdefault(k,[]).append(nm(g))
        cnt=collections.Counter({g:v for g,v in cnt.items() if not not_wine(g,c)})
        tot=sum(cnt.values()); top=[(g,v) for g,v in cnt.most_common() if g not in ('other','other red','other white')]
        rest=tot-sum(v for _,v in top[:12])
        merged={}   # two database names can share a Diploma name (Muscat Blanc and its pink form): one row each
        for g,v in top[:12]:
            d=nm(g); m=merged.setdefault(d,[d,0,colour.get(g) or '',g]); m[1]+=v
        out=dict(ha=round(tot),grapes=[[d,round(v),c_,g] for d,v,c_,g in merged.values()]+([['Other',round(rest),'','other']] if rest>=.5 else []))
        if left: out['left']={k:v[:4] for k,v in left.items()}
        return out
    out={}
    kidsP=collections.defaultdict(list)
    for k,v in P.items(): kidsP[v].append(k)
    def below(n):
        st=list(kidsP.get(n,[])); seen=[]
        while st: k=st.pop(); seen.append(k); st+=kidsP.get(k,[])
        return seen
    for n in list(direct):   # the database lists nested regions apart (Washington's Columbia Valley row is what is left after
        sub=[k for k in below(n) if k in direct]   # Yakima, Walla Walla and the rest), so a place's own figures take in its parts' rows
        if sub:
            cnt=collections.Counter(direct[n][0])
            for k in sub: cnt.update(direct[k][0])
            direct[n]=[cnt,direct[n][1]+[x for k in sub for x in direct[k][1]],direct[n][2]]
    for n,(cnt,names,y) in direct.items():   # a database region with an atlas place of the same name: its own figures
        out[n]=dict(scope='own',names=list(dict.fromkeys(names)),year=y,**pack(cnt,n.split('/')[0]))
    SH={}   # each place's share of area in each district
    for n,g in S.items():
        c=n.split('/')[0]
        if n in P and n!=c: g=g.buffer(0); ga=g.area or 1e-12; SH[n]={i:g.intersection(regs[i]['g']).area/ga for i in tree.query(g) if regs[i]['c']==c}
    sibs=collections.defaultdict(list)
    for n,p in P.items(): sibs[p].append(n)
    for n in sorted(P,key=lambda n:T[n]['depth']):
        if T[n].get('kind')=='group' and T[n].get('source')=='eu': out.pop(n,None); continue   # a list the EU register keeps (Spain's Vino de la Tierra, a country's PGIs), not a place: no figures, and none to pass down
        if n in out: continue
        c=n.split('/')[0]
        if n==c:
            if national.get(c): out[n]=dict(scope='country',names=[T[c]['name']],year=nyear[c],**pack(national[c],c))
            continue
        if n not in SH:
            p=out.get(P.get(n))
            if p and P.get(n)!=c: out[n]=dict(p,scope='parent')
            continue
        share=SH[n]; g=S[n]
        # every district that holds at least a tenth of the place, unless a neighbour of the same rank is mostly in it and this place only a little (Beaujolais's Rhône, for Burgundy)
        use=[i for i,v in share.items() if v>=.1 and not (v<.3 and any(SH.get(q,{}).get(i,0)>=.5 for q in sibs[P[n]] if q!=n))]
        ga=g.area or 1e-12
        use+=[i for i,v in share.items() if i not in use and v*ga>=.5*area[i]]   # and every district lying mostly inside it: all of Mendoza's departments, not just the two biggest
        pt=g.representative_point()
        if not use: use=[i for i in share if regs[i]['g'].contains(pt)][:1]
        if not use: continue
        cnt=collections.Counter()
        for i in use: cnt.update(regs[i]['cnt'])
        wide=sum(area[i] for i in use)>1.5*(g.area or 1e-12)   # the districts reach well beyond the place
        out[n]=dict(scope='around' if wide else 'within',names=list(dict.fromkeys(regs[i]['name'] for i in sorted(use,key=lambda i:-sum(regs[i]['cnt'].values())))),year=regs[use[0]]['year'],**pack(cnt,c))
    for n,o in OFFICIAL.items():
        cnt,col=austria_census(o['column']); colour.update({g:c for g,c in col.items() if g not in colour})
        out[n]=dict(scope='own',names=[T[n]['name']],year=o['year'],source=o['source'],**pack(cnt,n.split('/')[0]))
    meta=dict(source='Anderson, K., S. Nelgen and G. Puga, Database of Regional, National and Global Winegrape Bearing Areas by Variety, 2000 to 2023, Wine Economics Research Centre, University of Adelaide (CC BY 4.0)',
              url=ANDERSON,unplaced_ha={c:round(v) for c,v in unplaced.items() if v>=1})
    for n,v in out.items():   # the year the rows give (Argentina's 2023 file holds 2022 figures), not the file's edition
        c=n.split('/')[0]
        if v.get('year') in (2016,2023) and v.get('source') in (None,'anderson') and rowyear.get(c): v['year']=rowyear[c]
        if c=='france' and v.get('source') in (None,'anderson') and v.get('scope')!='country' and v.get('year') in (2022,2023):   # France's 2023 file dates its regional reds 2022 and gives its whites no year (an earlier survey, Anderson's notes): say so, and give no total that adds the two
            v['year']=2022; v['whites_older']=True
    json.dump({'$about':__doc__.split('\n')[0],**meta,'places':out},open(os.path.join(ROOT,'regions','atlas-plantings.json'),'w',encoding='utf-8'),ensure_ascii=False,indent=0)
    print(f'{len(regs)} database regions placed; {len(out)} places with plantings ({sum(1 for v in out.values() if v["scope"]=="within")} within, {sum(1 for v in out.values() if v["scope"]=="around")} around)')
    print('not placed (ha):',dict(sorted(meta['unplaced_ha'].items(),key=lambda x:-x[1])[:15]))

# ---------- terrain
TILE='https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'
DIRS=['N','NE','E','SE','S','SW','W','NW']
def tile_of(lon,lat,z):
    n=2**z; return int((lon+180)/360*n),int((1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*n)
def tile_box(x,y,z):
    from shapely.geometry import box
    n=2**z; lon=lambda x:x/n*360-180; lat=lambda y:math.degrees(math.atan(math.sinh(math.pi*(1-2*y/n))))
    return box(lon(x),lat(y+1),lon(x+1),lat(y))
def fetch_tile(t):
    import imagecodecs,numpy as np
    z,x,y=t
    for k in range(4):
        try:
            b=urllib.request.urlopen(urllib.request.Request(TILE.format(z=z,x=x,y=y),headers={'User-Agent':'pour-sheets-atlas'}),timeout=30).read()
            a=imagecodecs.png_decode(b)[:,:,:3].astype(np.float32); return a[:,:,0]*256+a[:,:,1]+a[:,:,2]/256-32768
        except Exception:
            time.sleep(1+k)
    return None
def terrain(max_tiles=16,only=None):
    """Elevation, slope and aspect for every place with a shape below the country level. Writes regions/atlas-terrain.json.
    Small places are read at zoom 12 (about 25 m a pixel at 45 degrees), the rest at zoom 11; a place spread over more than
    max_tiles tiles is read from an even sample of them. Tiles are read once, in memory, and not kept."""
    import numpy as np,shapely,hashlib
    from concurrent.futures import ThreadPoolExecutor
    S=shapes(); plan={}; users=collections.defaultdict(list)
    S=warm_shapes({n:g for n,g in S.items() if T[n]['depth']>0 and (not only or n in only)})   # elevation and slope of the warm ground, where vines can grow
    for n,g in S.items():
        g=g.buffer(0)
        for z in (12,11):
            x0,y0=tile_of(g.bounds[0],g.bounds[3],z); x1,y1=tile_of(g.bounds[2],g.bounds[1],z)
            if z==11 or (x1-x0+1)*(y1-y0+1)<=4: break
        ts=[(z,x,y) for x in range(x0,x1+1) for y in range(y0,y1+1)]
        if len(ts)>max_tiles*8: ts=sorted(ts,key=lambda t:hashlib.md5(f'{n}{t}'.encode()).hexdigest())[:max_tiles*8]
        ts=[t for t in ts if g.intersects(tile_box(t[1],t[2],t[0]))]
        if len(ts)>max_tiles: ts=sorted(ts,key=lambda t:hashlib.md5(f'{n}{t}'.encode()).hexdigest())[:max_tiles]
        plan[n]=(g,ts)
        for t in ts: users[t].append(n)
    res=_measure(plan,users)
    if only:   # a few places remeasured: keep everyone else's figures
        prev=jl(os.path.join(ROOT,'regions','atlas-terrain.json'))['places']; prev.update(res); res=prev
    _write_terrain(res)

def _measure(plan,users):
    """Elevation, slope and aspect over each place in plan {name:(shape,tiles)}, from the tiles in users {tile:[names]}."""
    import numpy as np,shapely
    from concurrent.futures import ThreadPoolExecutor
    print(f'{len(plan)} places, {len(users)} tiles to read',flush=True)
    EB=np.arange(-50,6001,10); SB=np.arange(0,90.5,.5)
    acc={n:dict(e=np.zeros(len(EB)-1),s=np.zeros(len(SB)-1),a=np.zeros(8),n=0) for n in plan}
    C=40075016.7; t0=time.time(); done=0
    def work(t):
        e=fetch_tile(t)
        if e is None: return t,None
        z,x,y=t; N=2**z; i=np.arange(256); lat=np.degrees(np.arctan(np.sinh(np.pi*(1-2*(y+(i+.5)/256)/N))))
        lon=(x+(i+.5)/256)/N*360-180; s=(C*np.cos(np.radians(lat))/(256*N))[:,None]
        gy=-np.gradient(e,axis=0)/s; gx=np.gradient(e,axis=1)/s
        slope=np.degrees(np.arctan(np.hypot(gx,gy))); az=(np.degrees(np.arctan2(-gx,-gy))+360)%360
        return t,(e,slope,az,lon,lat)
    def inside(t,r):   # on the main thread only: a prepared shape's point index is built lazily and is not safe to share
        e,slope,az,lon,lat=r; X,Y=np.meshgrid(lon,lat); out={}
        for n in users[t]:
            m=shapely.contains_xy(plan[n][0],X,Y)&(e>-20)
            if m.any(): out[n]=(e[m],slope[m],az[m])
        return out
    todo=list(users)
    def chunks():
        with ThreadPoolExecutor(16) as ex:
            for k in range(0,len(todo),64): yield from ex.map(work,todo[k:k+64])   # 64 at a time, so results never pile up
    if True:
        for t,r in chunks():
            out=inside(t,r) if r is not None else None
            done+=1
            if done%500==0: print(f'{done}/{len(users)} tiles {time.time()-t0:.0f}s',flush=True)
            for n,(e,sl,az) in (out or {}).items():
                A=acc[n]; A['e']+=np.histogram(np.clip(e,-49,5999),EB)[0]; A['s']+=np.histogram(np.clip(sl,0,89.9),SB)[0]; A['n']+=len(e)
                k=sl>=2; A['a']+=np.bincount(((az[k]+22.5)%360//45).astype(int),minlength=8)[:8]
    def pct(h,b,q):
        c=np.cumsum(h); return float(b[np.searchsorted(c,q*c[-1])+1]) if c[-1] else None
    res={}
    for n,A in acc.items():
        if A['n']<9: continue
        e,sl=A['e'],A['s']; mid=(SB[:-1]+SB[1:])/2
        res[n]=dict(elev=[round(pct(e,EB,q)) for q in (.1,.5,.9)],slope=round(float((sl*mid).sum()/sl.sum()),1),
                    flat=round(float(sl[mid<2].sum()/sl.sum()),2),steep=round(float(sl[mid>=10].sum()/sl.sum()),2),
                    aspect={d:round(float(v/A['a'].sum()),2) for d,v in zip(DIRS,A['a'])} if A['a'].sum() else None,
                    zoom=plan[n][1][0][0],tiles=len(plan[n][1]),cells=int(A['n']))
    print(f'{len(res)} places measured in {time.time()-t0:.0f}s')
    return res
def _write_terrain(res):
    json.dump({'$about':'Elevation (m, 10th/50th/90th percentile), mean slope (degrees), the share of flat (<2 degrees) and steep (10+ degrees) ground, and the share of sloping ground facing each way. src/atlasland.py terrain.',
               'source':'AWS Terrain Tiles (Terrarium), from SRTM, GMTED2010, ETOPO1 and national elevation models','url':'https://registry.opendata.aws/terrain-tiles/',
               'places':res},open(os.path.join(ROOT,'regions','atlas-terrain.json'),'w',encoding='utf-8'),separators=(',',':'))

def plots():
    """Elevation, slope and aspect over the real boundary of each grand cru and single-vineyard appellation, from the INAO
    delimitations (regions/grand-crus.json). The EU draws these by whole commune, which says nothing of the plot itself.
    Read at zoom 13 (about 13 m a pixel at 47 degrees). Writes regions/atlas-plots.json."""
    import subprocess,shapely
    from shapely.geometry import shape
    from shapely.ops import unary_union
    ODW='https://raw.githubusercontent.com/24eme/opendatawine/9d65ed62f55097faf109bcd4c44805f596981bda/delimitation_aoc'
    FG='https://raw.githubusercontent.com/gregoiredavid/france-geojson/5d34ee6d0140c29f785fdb047d9329f1aab58833'
    def get(url,name):
        p=os.path.join(CA,name)
        if not os.path.exists(p) and not os.path.exists(p+'.missing'):
            if subprocess.run(['curl','-s','-f','-m','120','-o',p,url]).returncode: open(p+'.missing','w').close()
        return p if os.path.exists(p) else None
    L=jl(os.path.join(ROOT,'regions','grand-crus.json')); ids=L['cote_d_or']+L['alsace']+L['other']
    names=lambda n:{norm(x) for a in [T[n]['name']]+T[n].get('also',[]) for x in [a]+a.split(' ou ')}
    want=collections.defaultdict(set)
    for n in ids:
        for x in names(n): want[x].add(n)
    hits=collections.defaultdict(set)
    def scan(code):
        p=get(f'{ODW}/{code[:2]}/{code}/delimitations.json',f'd{code}.json')
        for app,f in (jl(p) if p else {}).items():
            for x in {norm(app)}|{norm(y) for y in app.split(' ou ')}:
                for n in want.get(x,()): hits[n].add((code,f))
    for dep,dn in ((67,'67-bas-rhin'),(68,'68-haut-rhin')):   # Alsace: only the communes each grand cru's rules name
        C=collections.defaultdict(list)
        for x in jl(get(f'{FG}/departements/{dn}/communes-{dn}.geojson',f'c{dep}.json'))['features']: C[norm(x['properties']['nom'])].append(x['properties']['code'])
        for n in L['alsace']:
            for c in (jl(os.path.join(OUT,'facts',n.replace('/','__')+'.json')).get('rules') or {}).get('communes') or []:
                for code in C.get(norm(c),[]): scan(code)
    for p in os.listdir(CA):
        if re.fullmatch(r'd\d{2}[\dAB]\d{2}\.json',p) and p[1:3] not in ('67','68'): scan(p[1:6])
    plan={}; users=collections.defaultdict(list); z=13; miss=[]
    for n in ids:
        gs=[shape(x['geometry']).buffer(0) for c,f in sorted(hits[n]) for p in [get(f'{ODW}/{c[:2]}/{c}/{f}',f'g{c}-{f}')] if p for x in jl(p)['features']]
        if not gs: miss.append(n); continue
        g=unary_union(gs).buffer(0); shapely.prepare(g)
        x0,y0=tile_of(g.bounds[0],g.bounds[3],z); x1,y1=tile_of(g.bounds[2],g.bounds[1],z)
        ts=[(z,x,y) for x in range(x0,x1+1) for y in range(y0,y1+1) if g.intersects(tile_box(x,y,z))]
        plan[n]=(g,ts)
        for t in ts: users[t].append(n)
    if miss: print('no INAO boundary for',miss)
    res=_measure(plan,users)
    json.dump({'$about':'The same measures as atlas-terrain.json, over each grand cru\'s own vineyard boundary. src/atlasland.py plots.','source':L['source'],'places':res},
              open(os.path.join(ROOT,'regions','atlas-plots.json'),'w',encoding='utf-8'),separators=(',',':'))

# ---------- the rock beneath
GEO_API='https://macrostrat.org/api/v2/geologic_units/map?lat={lat}&lng={lng}'
SCALES=['large','medium','small','tiny']
def warm_shapes(S):
    """Each place's shape cut to its warm ground: the WorldClim cells with a growing season of 13 °C or more, written by
    src/atlas.py climate (build/atlas/warmcells.json). A place with no such cells keeps its whole shape."""
    from shapely.geometry import box
    from shapely.ops import unary_union
    p=os.path.join(OUT,'warmcells.json')
    if not os.path.exists(p): return S
    W=jl(p); G=W['grid']; x0,y0,dx,dy=G['x0'],G['y0'],G['dx'],G['dy']; out={}
    for n,g in S.items():
        cs=W['cells'].get(n)
        if not cs: out[n]=g; continue
        w=unary_union([box(x0+c*dx,y0-(r+1)*dy,x0+(c+1)*dx,y0-r*dy) for r,c in cs]).intersection(g.buffer(0))
        out[n]=w if not w.is_empty and w.area>.02*g.area else g
    return out
def rock_points(g,k):
    """Up to k points spread over a shape: an even grid over its bounds, kept where it falls inside, thinned evenly."""
    import shapely
    x0,y0,x1,y1=g.bounds; pts=[]
    for n in (3,5,8,12,18):
        xs=[x0+(x1-x0)*(i+.5)/n for i in range(n)]; ys=[y0+(y1-y0)*(j+.5)/n for j in range(n)]
        pts=[(x,y) for y in ys for x in xs if g.contains(shapely.Point(x,y))]
        if len(pts)>=k: break
    if len(pts)>k: pts=[pts[round(i*(len(pts)-1)/(k-1))] for i in range(k)] if k>1 else pts[:1]
    if not pts: q=g.representative_point(); pts=[(q.x,q.y)]
    return [(round(x,3),round(y,3)) for x,y in pts]
def rocks():
    """The rock families under every place with a shape below the country level, from Macrostrat's geologic map: the
    most detailed map unit at 5 to 15 points over its warm ground, each point's lithologies sorted into the families in
    regions/rock-types.json. Writes regions/atlas-rocks.json. Points are cached in data/cache/macrostrat/points.json."""
    from concurrent.futures import ThreadPoolExecutor
    RT=jl(os.path.join(ROOT,'regions','rock-types.json'))
    defs={x['lith_id']:x for x in jl(os.path.join(CA,'macrostrat','liths.json'))['success']['data']}
    fam={}
    for i,d in defs.items():
        f=next((F['id'] for F in RT['families'] if d['name'] in F.get('liths',[])),None) or next((F['id'] for F in RT['families'] if d['type'] in F.get('types',[])),None)
        if f: fam[i]=f
    cp=os.path.join(CA,'macrostrat','points.json'); cache=jl(cp) if os.path.exists(cp) else {}
    S=shapes(); plan={}
    W=warm_shapes({n:g for n,g in S.items() if T[n]['depth']>0})   # the rock under the vineyards' warm ground, not the mountains
    for n,g in W.items():
        a=g.area*111.32**2*math.cos(math.radians(g.representative_point().y))
        plan[n]=rock_points(g.buffer(0),5 if a<50 else 9 if a<1000 else 15)
    todo=sorted({f'{x},{y}' for ps in plan.values() for x,y in ps}-set(cache))
    print(f'{len(plan)} places, {len(todo)} points to look up ({len(cache)} cached)',flush=True)
    def look(key):
        x,y=key.split(',')
        for k in range(4):
            try:
                d=json.loads(urllib.request.urlopen(urllib.request.Request(GEO_API.format(lat=y,lng=x),headers={'User-Agent':'pour-sheets-atlas'}),timeout=60).read())['success']['data']
                us=sorted([u for u in d if u.get('liths')],key=lambda u:SCALES.index(u['scale']) if u.get('scale') in SCALES else 9)
                return key,([us[0]['scale'],us[0]['liths'],(us[0].get('name') or '')[:80]] if us else None)
            except Exception: time.sleep(2+3*k)
        return key,'error'
    t0=time.time()
    with ThreadPoolExecutor(4) as ex:
        for i,(key,v) in enumerate(ex.map(look,todo),1):
            if v!='error': cache[key]=v
            if i%500==0:
                json.dump(cache,open(cp,'w')); print(f'{i}/{len(todo)} points {time.time()-t0:.0f}s',flush=True)
    json.dump(cache,open(cp,'w'))
    out={}
    for n,ps in plan.items():
        w=collections.Counter(); sc=collections.Counter(); got=0
        for x,y in ps:
            v=cache.get(f'{x},{y}')
            if not v: continue
            fs=[fam[i] for i in v[1] if i in fam]
            if not fs: continue
            got+=1; sc[v[0]]+=1
            for f in fs: w[f]+=1/len(fs)
        if got: tot=sum(w.values()); out[n]=dict(families=[[f,round(v/tot,2)] for f,v in w.most_common() if v/tot>=.05],points=got,scale=sc.most_common(1)[0][0])
    json.dump({'$about':'The rock families under each place, as shares of the points sampled (src/atlasland.py rocks).','source':RT['sources']['macrostrat'],'places':out},
              open(os.path.join(ROOT,'regions','atlas-rocks.json'),'w',encoding='utf-8'),separators=(',',':'))
    print(f'{len(out)} places with rock in {time.time()-t0:.0f}s')

# ---------- what the numbers mean, in plain words
def _f(c): return c*9/5+32
def _and(xs): xs=list(xs); return ', '.join(xs[:-1])+' and '+xs[-1] if len(xs)>1 else (xs[0] if xs else '')
def readings(f,CG):
    """What a place's climate, rock, soil and land mean for its vines: short labelled points [topic, why it matters] for
    climate and land, and plain paragraphs for soil ({'rock': ..., 'top': ...}).
    Built from the place's own numbers and the rules in regions/climate-grapes.json and rock-types.json. Each point says
    what the number does to the vines or the wine, and never just restates the number shown beside it."""
    out={}; c=f.get('climate'); so=f.get('soil'); te=f.get('terrain'); pl=f.get('planted'); big=f.get('large'); rk=f.get('rocks')
    G=CG['grapes']; AL=CG['also']
    import unicodedata
    fold=lambda x:unicodedata.normalize('NFKD',x).encode('ascii','ignore').decode().lower()
    GF={fold(g):g for g in G}
    def key(g):   # the rules spell grapes as the law does (Semillon, Sauvignon, Cot): match them through the synonym table
        d=prime(g); d=NAME.get(d,d); d=AL.get(d,AL.get(g,d))
        return d if d in G else GF.get(fold(d),GF.get(fold(g),d))
    # Only the place's own grapes are named: what is planted there, or else the main grapes its rules allow (a grand cru
    # has no planting figures of its own). With neither, no grape is named, since a list that fits the climate reads as
    # a list of what grows there.
    planted=[key(g) for g,ha,*_ in (pl or {}).get('grapes',[]) if g!='Other' and key(g) in G and ha>=.05*pl['ha']][:4] if pl and pl.get('scope') in ('own','within','country') else []
    main=[g for g,*_ in ((f.get('rules') or {}).get('grapes') or [])]
    if (f['id'].startswith('italy/') and len(main)>=10) or len(main)>6: main=[]   # Italy's EU lists are the province's; a long list is no place's identity
    if f['id'].startswith('france/') and not (f.get('rules') or {}).get('cahier'): main=[]
    if (f.get('rules') or {}).get('roles_unread'): main=[]   # roles not read apart: Saint-Romain's Pinot Gris is an accessory in its reds, not one of its wines   # the EU list has no roles: Pinot Gris is allowed in Pernand's red, not one of its grapes
    lead=next((g for g,ha,*_ in (pl or {}).get('grapes',[]) if g!='Other'),None)
    if lead and key(lead) not in G: planted=[]   # Verdejo leads in Rueda: judging only its minor grapes would mislead
    known=list(dict.fromkeys(key(g) for g in main if key(g) in G))
    share={key(g):ha for g,ha,*_ in (pl or {}).get('grapes') or f.get('_wider') or []}
    known.sort(key=lambda g:-share.get(g,0))   # the most planted first, even from a wider area's table: Merlot before Malbec in Saint-Émilion
    ruled=known[:4] if main and len(known)*2>len(set(map(key,main))) else []   # name the grapes only when most of them can be judged: not Chardonnay alone for Beaujolais
    label='Grown here'
    if not planted and ruled: planted,label=ruled,'Its grapes'
    cls=None
    if c and c.get('gst') is not None:
        t=c['gst']; cls=next(n for lo,hi,n in CG['classes'] if lo<=t<hi); r=[]
        if big: planted=[]
        # a place with grapes of its own is spoken of through them: the climate grid averages in the hills and towns around the
        # vines, so a cool reading over Wachau or an Alsace grand cru says more about the grid than about the vineyards
        elif cls=='too cool' and not planted: r.append(['Grapes','Too cool for most classic wine grapes. Only very early ripening ones do well here.'])
        elif cls=='too hot' and not planted: r.append(['Grapes','Too hot for most classic table-wine grapes. Heat like this suits fortified wine.'])
        ok=[g for g in planted if G[key(g)][0]<=t<=G[key(g)][1]]
        cool=[g for g in planted if t<G[key(g)][0]]; warm=[g for g in planted if t>G[key(g)][1]]
        ok=[display(g,f['id'].split('/')[0]) for g in ok]   # Spätburgunder in the Pfalz, Shiraz in the Barossa, as the tables say
        if ok: r.append([label,f'{_and(ok)} {"sit" if len(ok)>1 else "sits"} in {"their" if len(ok)>1 else "its"} sweet spot, so the wines can show the style {"they are" if len(ok)>1 else "it is"} known for.'])
        # no warm- or cool-limit verdicts: one average over a region cannot tell Clare's cool Riesling sites or Rioja Oriental's warm
        # Garnacha from the rest, and the verdicts read as judgements on benchmark wines
        out['climate']=r
    soil={}   # two short paragraphs, not labelled points: what the rock does, then what the topsoil does
    if rk and rk.get('families'):
        F={x['id']:x for x in (CG.get('rocks') or {}).get('families',[])}
        ss=[F[i]['effect'] for k,(i,v) in enumerate(rk['families'][:3]) if i in F and F[i]['effect'] and (k==0 or v>=.25)]
        if ss: soil['rock']=' '.join(ss)
    if so and not big:
        tx=so['texture']; ss=[]
        top=rk['families'][0][0] if rk and rk.get('families') else None
        drains=top in ('gravel','sand','granite','schist','sandstone','volcanic')
        if tx in ('sand','loamy sand','sandy loam'): ss.append('The soil drains fast and warms early in spring. Vines get little water, which keeps crops small and flavors concentrated, but drought bites hard.')
        elif drains: pass   # the rock text has said it drains fast; a water-holding sample from 30 to 60 cm would only contradict it
        elif tx.endswith('clay loam'): ss.append('The soil holds water well and drains at a steady pace, so vines rarely go thirsty or sit in wet ground.')
        elif 'clay' in tx: ss.append('The soil stores water through dry spells, but stays wet and cold after rain, which slows ripening and can swell the grapes.')
        elif tx in ('silt','silt loam'): ss.append('The soil holds plenty of water, which can push leafy, vigorous vines unless growers rein them in.')
        else: ss.append('The soil drains well and still stores water for dry spells, so vines grow evenly.')
        lime=bool(rk and rk.get('families') and rk['families'][0][0] in ('limestone','chalk','marl'))
        if lime and so['ph']<7.4: pass   # over limestone the sampled layer can read near neutral; saying so would contradict the rock
        elif so['ph']>=7.4: ss.append('Its high pH can starve vines of iron and yellow the leaves.')
        elif so['ph']<5.5: ss.append('It is strongly acid, which locks up nutrients, so growers spread lime to raise the pH.')
        elif so['ph']<6.5: ss.append('It is moderately acid, which most vines tolerate well.')
        else: ss.append('Its pH is close to neutral, so vines take up the nutrients they need easily.')
        if (so.get('stones') or 0)>=25: ss.append("Stones in it help water drain and store the day's heat, giving it back to the vines at night.")
        soil['top']=' '.join(ss)
    if soil.get('rock') and soil.get('top'): soil.pop('top')   # the rock text has said how the ground drains; a 1 km soil model would only contradict it
    # Not shown: the rock sentences describe map geology (Jerez's albariza reads as gravel, Uco's alluvium as volcanic bedrock) and the
    # soil model is a 1 km grid; both read as facts about the vineyards and too often contradict them. The figures stay, captioned.
    if te:
        r=[]; lo,mid,hi=te['elev']; dF=(hi-lo)*6.5/1000*1.8
        if False: r.append(['Height',f'The high ground runs about {round(dF)}°F cooler than the low ground. Higher vineyards ripen later and keep more acidity, so one grape can make lighter or richer wine here depending on height.'])
        if not big:
            # the terrain is measured over the whole warm ground, so it says how the land lies, not how a given vineyard is farmed
            pass   # no slope or height verdicts: a 30 m grid over a whole area cannot see Côte-Rôtie's terraces or tell the Napa valley floor from its hills
            a=te.get('aspect')
            if a and te['flat']<.8:
                south=(c or {}).get('lat',1)<0; way=lambda *ds:sum(a[d] for d in ds)
                toward,away=(way('NW','N','NE'),way('SE','S','SW')) if south else (way('SE','S','SW'),way('NW','N','NE'))
                # SE and SW count toward the sun first: Château-Grillet's south-east bowl is "plein sud" in its cahier, not a morning-sun slope; and the line says "toward the sun", not "midday sun", since Saering's slope is mostly south-east
                side=(toward,'sun') if toward>=.6 else (away,'shade') if away>=.6 else max(((toward,'sun'),(away,'shade'),(way('NE','E','SE'),'east'),(way('SW','W','NW'),'west')),key=lambda x:x[0])
                coolish=cls in ('too cool','cool','intermediate')
                if side[0]<.6: r.append(['Sun','Slopes face several ways, so growers can pick warmer or cooler spots to suit each grape.'])
                elif side[1]=='east': r.append(['Sun','Faces the morning sun. Early light dries the dew, which cuts disease, and the grapes are spared the hottest afternoon sun.'])
                elif side[1]=='west': r.append(['Sun','Faces the afternoon sun, the hottest of the day. Grapes ripen fuller, but morning dew lingers longer.'])
                elif side[1]=='sun' and not cls: r.append(['Sun','Faces toward the sun, which warms the vines and helps the grapes ripen.'])   # no climate shown (Alsace grands crus): say nothing about warm or cool
                elif side[1]=='shade' and not cls: r.append(['Sun','Faces away from the sun, so the grapes ripen more slowly.'])
                elif side[1]=='sun': r.append(['Sun','Faces toward the sun. In a climate this cool, that extra warmth is often what gets grapes fully ripe.' if coolish else 'Faces toward the sun, which pushes ripeness and alcohol up in a climate this warm.'])
                else: r.append(['Sun','Faces away from the sun. In a cool climate that makes ripening harder.' if coolish else 'Faces away from the sun. In a warm climate the shade keeps grapes fresher and slows ripening.'])
        if r: out['land']=r
    return out

if __name__=='__main__':
    cmd=sys.argv[1] if len(sys.argv)>1 else ''
    if cmd=='plant': plant()
    elif cmd=='rocks': rocks()
    elif cmd=='plots': plots()
    elif cmd=='terrain':
        import atlas; atlas.guard(); terrain(only=set(sys.argv[2:]) or None)
    else: print(__doc__)
