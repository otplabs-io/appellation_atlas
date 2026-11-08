#!/usr/bin/env python3
"""How well known each place in regions/tree.json is, from Wikipedia. The Appellation Atlas shades by it.
Usage: python src/notoriety.py fetch     (asks Wikidata and Wikipedia; every answer is cached in data/cache/notoriety/)
       python src/notoriety.py build     (writes regions/notoriety.json from the cache)
       python src/notoriety.py check     (prints the top places per country and the places with no article)

A place's article is found, in this order:
  EU PDO and PGI   the Wikidata item that carries its eAmbrosia id (P9854), the EU register's own id
  everything else  the first English Wikipedia title that exists among the usual names for a wine place: "<name> wine",
                   "<name> AOC", "<name> DOCG", "<name> (DO)", "<name> AVA", "<name> wine region" and so on, by country;
                   for a country "French wine", "Wine in <country>" and the like. A bare place name never counts, so the
                   town of Bordeaux is not taken for Bordeaux wine. (Wikipedia's search refused this many queries.)
                   Titles go 50 to a request and redirects count: "Barolo DOCG" redirects to "Barolo" and still belongs to Barolo DOCG.
Two measures, both public and repeatable:
  langs   how many Wikipedias have an article on it (Wikidata sitelinks)
  views   page views over the 60 days before the fetch, English Wikipedia plus the country's own language
          (the batched query's limit; a year would be one request per article, hours under Wikimedia's throttle)
score is the mean of the two percentiles over every place with an article, 0 to 100. A country or region is scored from
its parts instead: the mean of the percentile of all page views across it and everything in it (each article once, set
against the places at the same depth) and the score of its best-known single place. So Côte d'Or, which has no English
article, is scored from Côte de Nuits, Côte de Beaune and their villages. Any other place with no article has no score and
the atlas draws it in the lightest shade."""
import concurrent.futures as cf,datetime,hashlib,json,math,os,re,sys,time,unicodedata,urllib.parse,urllib.request
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.path.dirname(HERE)
CA=os.path.join(ROOT,'data','cache','notoriety'); OUT=os.path.join(ROOT,'regions','notoriety.json')
T=json.load(open(os.path.join(ROOT,'regions','tree.json'),encoding='utf-8'))['nodes']
UA='PourSheetsAtlas/0.1 (home wine-learning project; contact via Wikimedia talk not needed) python-urllib'
LANG={'france':'fr','italy':'it','spain':'es','germany':'de','austria':'de','portugal':'pt','greece':'el','hungary':'hu','romania':'ro','bulgaria':'bg',
      'croatia':'hr','slovenia':'sl','czechia':'cs','slovakia':'sk','cyprus':'el','netherlands':'nl','belgium':'fr','denmark':'da','luxembourg':'de',
      'argentina':'es','chile':'es','mexico':'es','uruguay':'es','brazil':'pt','switzerland':'de','canada':'fr','turkey':'tr','armenia':'hy','georgia':'ka',
      'moldova':'ro','ukraine':'uk','serbia':'sr','north-macedonia':'mk','israel':'he','lebanon':'fr','morocco':'fr','china':'zh','japan':'ja'}
def norm(s): return re.sub(r'[^a-z0-9]','',unicodedata.normalize('NFKD',s or '').encode('ascii','ignore').decode().lower())
def cached(key,fetch):
    p=os.path.join(CA,hashlib.sha1(key.encode()).hexdigest()[:20]+'.json')
    if os.path.exists(p): return json.load(open(p,encoding='utf-8'))['v']
    v=fetch(); json.dump(dict(k=key,v=v),open(p,'w',encoding='utf-8'),ensure_ascii=False); return v
_last=[0.0]; _lock=__import__('threading').Lock()
def get(url,tries=40):
    """One request at a time, at most two a second, waiting out every 429 (Wikimedia throttles bursts)."""
    for i in range(tries):
        with _lock:
            w=_last[0]+.5-time.time()
            if w>0: time.sleep(w)
            _last[0]=time.time()
        try:
            with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':UA,'Accept':'application/json'}),timeout=60) as r: v=json.load(r)
            if isinstance(v,dict) and 'error' in v:
                if v['error'].get('code') in ('maxlag','ratelimited'): time.sleep(10*(i+1)); continue
                raise SystemExit(f"{url}: {v['error'].get('code')} {v['error'].get('info','')[:200]}")
            return v
        except urllib.error.HTTPError as e:
            if e.code==404: return None
            if e.code==429 or e.code>=500: time.sleep(min(300,int(e.headers.get('Retry-After') or 0) or 15*(i+1))); continue
            raise
        except (urllib.error.URLError,TimeoutError): time.sleep(3*(i+1))
    raise SystemExit('gave up on '+url)
def api(host,**q): return get(f'https://{host}/w/api.php?'+urllib.parse.urlencode(dict(q,format='json',formatversion=2)))
def country(n): return T[n]['path'].split('/')[0]
# ---- finding each place's Wikidata item
def eu_items():
    """eAmbrosia id -> Wikidata item, for every item that carries one (a search for the statement, then the items' claims)."""
    qs=[]; off=0
    while off is not None:
        r=cached(f'p9854:{off}',lambda:api('www.wikidata.org',action='query',list='search',srsearch='haswbstatement:P9854',srlimit=500,sroffset=off,srprop=''))
        qs+=[h['title'] for h in r['query']['search']]; off=(r.get('continue') or {}).get('sroffset')
    out={}
    for i in range(0,len(qs),50):
        part=qs[i:i+50]; r=cached('claims:'+'|'.join(part),lambda:api('www.wikidata.org',action='wbgetentities',ids='|'.join(part),props='claims'))
        for q,e in r['entities'].items():
            for c in e.get('claims',{}).get('P9854',[]):
                v=c['mainsnak'].get('datavalue',{}).get('value')
                if v: out.setdefault(v,q)
    return out
SKIP=('commonswiki','specieswiki','metawiki','wikidatawiki','sourceswiki')
def per_key(name,keys,ask,read):
    """A cache with one entry per key (title or item), in data/cache/notoriety/<name>.json, so a rerun with a changed set of
    keys asks only for the new ones. ask(part) makes one request for up to 50 keys; read(part, reply) gives {key: value} for
    every key in part, None when there is nothing. Older batch replies in the cache are read back in first."""
    p=os.path.join(CA,name+'.json'); store=json.load(open(p,encoding='utf-8')) if os.path.exists(p) else {}
    if not store:
        for f in os.listdir(CA):
            if f.startswith('_') or not f.endswith('.json') or len(f)!=25: continue
            d=json.load(open(os.path.join(CA,f),encoding='utf-8'))
            part=OLD.get(name,lambda k:None)(d['k'])
            if part and d['v']: store.update(read(part,d['v']))
    todo=sorted({k for k in keys if k not in store})
    for i in range(0,len(todo),50):
        part=todo[i:i+50]; store.update(read(part,ask(part)))
        if i//50%10==9 or i+50>=len(todo): json.dump(store,open(p,'w',encoding='utf-8'),ensure_ascii=False)
    if not todo and not os.path.exists(p): json.dump(store,open(p,'w',encoding='utf-8'),ensure_ascii=False)
    return {k:store[k] for k in keys if store.get(k) is not None}
def _old(prefix,cut=None):
    def f(k):
        if not k.startswith(prefix): return None
        k=k[len(prefix):]
        if cut:
            if not k.endswith(cut): return None
            k=k[:-len(cut)]
        return k.split('|')
    return f
def _ids(k):
    if not k.startswith('wbget:'): return None
    a=json.loads(k[6:]); return a['ids'].split('|') if 'ids' in a else None
OLD={'items':_ids,'meta':_old('meta:'),'pp-enwiki':_old('pp:enwiki:')}
def entities(ids):
    """Wikidata items' sitelinks: {item: {'q':..., 'links':{site: title}}}."""
    def read(part,r):
        out=dict.fromkeys(part)
        for q,e in (r or {}).get('entities',{}).items():
            if 'missing' in e or q.startswith('-'): continue
            out[q]=dict(q=q,links={s:v['title'] for s,v in e.get('sitelinks',{}).items() if s.endswith('wiki') and s not in SKIP})
        return out
    return per_key('items',ids,lambda part:api('www.wikidata.org',action='wbgetentities',props='sitelinks',ids='|'.join(part)),read)
ADJ={'france':'French','italy':'Italian','spain':'Spanish','germany':'German','portugal':'Portuguese','austria':'Austrian','hungary':'Hungarian','greece':'Greek',
     'romania':'Romanian','bulgaria':'Bulgarian','croatia':'Croatian','slovenia':'Slovenian','czechia':'Czech','slovakia':'Slovak','cyprus':'Cypriot','netherlands':'Dutch',
     'belgium':'Belgian','denmark':'Danish','luxembourg':'Luxembourgish','malta':'Maltese','argentina':'Argentine','australia':'Australian','south-africa':'South African',
     'canada':'Canadian','chile':'Chilean','mexico':'Mexican','new-zealand':'New Zealand','turkey':'Turkish','armenia':'Armenian','israel':'Israeli','serbia':'Serbian',
     'united-kingdom':'British','uruguay':'Uruguayan','switzerland':'Swiss','ukraine':'Ukrainian','china':'Chinese','lebanon':'Lebanese','georgia':'Georgian',
     'moldova':'Moldovan','japan':'Japanese','morocco':'Moroccan','north-macedonia':'Macedonian','brazil':'Brazilian','united-states':'American'}
SUFFIX={'france':['wine','AOC','(AOC)','(wine)','wine region'],'italy':['DOCG','DOC','(wine)','wine','wine region'],'spain':['(DO)','DO','DOCa','(wine)','wine','wine region'],
        'portugal':['DOC','(DOC)','wine','(wine)','wine region'],'germany':['(wine region)','wine region','wine'],'austria':['DAC','(wine region)','wine region','wine'],
        'united-states':['AVA','wine','(wine region)','wine region']}
TIER=re.compile(r'\s+(?:DOCG|DOC|DOCa|DOQ|DO|AOC|AOP|IGP|IGT|PDO|PGI|AVA|DAC|VDP|VQA|WO|GI)$')
def base(n):
    """n's names without a trailing tier ("Prosecco DOC" is tried as "Prosecco ..."), each also as written.
    Two South African names carry a stray '|' in the tree."""
    out=[]
    for m in [T[n]['name']]+T[n].get('also',[]):
        m=m.split('|')[0].strip(); out+=[TIER.sub('',m),m]
    return list(dict.fromkeys(out))
def candidates(n):
    """The titles a wine place's English Wikipedia article usually has, most likely first. Never the bare place name."""
    x=T[n]; c=country(n); names=base(n)
    if x['depth']==0:
        C=x['name']; a=ADJ.get(c); return ([f'{a} wine'] if a else [])+[f'Wine in {C}',f'Winemaking in {C}',f'Wine of {C}',f'{C} wine',f'Viticulture in {C}',f'Wine industry in {C}']
    suf=(['AVA'] if x.get('cfr') else [])+SUFFIX.get(c,['(wine region)','wine region','(wine)','wine','GI','DOC','(DO)'])
    return list(dict.fromkeys(f'{nm} {s}' for nm in names for s in suf))
def hops(q):
    hop={}
    for k in ('normalized','redirects'):
        for m in q.get(k,[]): hop[m['from']]=m['to']
    def end(t):
        for _ in range(4): t=hop.get(t,t)
        return t
    return end
def resolve(site,titles):
    """Each title's Wikidata item on one Wikipedia, following redirects: {asked title: [final title, item]}."""
    host=site[:-4].replace('_','-')+'.wikipedia.org'
    def read(part,r):
        q=(r or {}).get('query',{}); end=hops(q)
        item={g['title']:g.get('pageprops',{}).get('wikibase_item') for g in q.get('pages',[]) if not g.get('missing') and not g.get('invalid')}
        return {t:([end(t),item[end(t)]] if item.get(end(t)) else None) for t in part}
    return per_key('pp-'+site,titles,lambda part:api(host,action='query',prop='pageprops',ppprop='wikibase_item',redirects=1,titles='|'.join(part)),read)
WINE=re.compile(r'\bwines?\b|\bvins?\b|vineyard|appellation|viticultur|wine-producing|winegrowing|\bAVA\b|\bAOC\b|\bDOCG?\b',re.I)
# Wikidata classes that mean a wine place or a wine, picked by hand from the classes the wine-titled matches carry
CLASSES={'Q166247','Q2140699','Q22715','Q451752','Q117085231','Q2858704','Q13439060','Q3139487','Q1565828','Q2305591','Q3560266',
         'Q13582250','Q1016093','Q630531','Q1432594','Q282','Q1827','Q321263'}
# AVA, wine-producing region, vineyard, DOC (Portugal), geographical indication, appellation, PDO, DO, AOC, DOCG, vinho regional,
# IPR, Burgundy wine region, French wine, Spanish wine, wine, red wine, sparkling wine
NOT={'Q958314'}
# A bare name that lands on a town, commune, city, region of a country, federal state or winery is that place, not its wine
# (Cafayate the town, Salta the city, Ischia and Samos the islands), unless the item is also a wine place.
SETTLED={'Q23442','Q1161185','Q34763','Q1620908','Q1234255','Q148837','Q82794',   # island, volcanic island, peninsula, historical region, regional unit, polis, region
         'Q515','Q3957','Q747074','Q484170','Q486972','Q15284','Q1134686','Q13218690','Q13539802','Q133442','Q16110','Q261543','Q1710033','Q156362'}
PLACE={'Q166247','Q2140699','Q451752','Q117085231','Q2858704','Q13439060','Q3139487','Q1565828','Q2305591','Q3560266','Q13582250','Q1016093','Q3104453','Q868979','Q325668'}   # grape variety: "Vermentino di Gallura DOCG" redirecting to the grape is not the place
def meta(ids):
    """English description and 'instance of' (P31) classes of each item: {q: [description, [classes]]}."""
    def read(part,r):
        out=dict.fromkeys(part)
        for q,e in (r or {}).get('entities',{}).items():
            c={x['mainsnak'].get('datavalue',{}).get('value',{}).get('id') for x in e.get('claims',{}).get('P31',[])}
            out[q]=[e.get('descriptions',{}).get('en',{}).get('value',''),sorted(c-{None})]
        return out
    return per_key('meta',ids,lambda part:api('www.wikidata.org',action='wbgetentities',ids='|'.join(part),props='descriptions|claims',languages='en'),read)
NOT_PLACE={'italy/novello':'"Novello wine" leads to vino novello, a style of young wine, not the Barolo village'}
def cats(site,titles):
    """Each article's categories on one Wikipedia: {title: [category, ...]}."""
    host=site[:-4].replace('_','-')+'.wikipedia.org'
    def ask(part):
        pages=[]; cont={}
        while True:
            r=api(host,action='query',prop='categories',cllimit='max',clshow='!hidden',redirects=1,titles='|'.join(part),**cont)
            pages+=(r or {}).get('query',{}).get('pages',[]); cont={k:v for k,v in ((r or {}).get('continue') or {}).items() if k!='continue'}
            if not cont: return dict(query=dict((r or {}).get('query',{}),pages=pages))
    def read(part,r):
        q=(r or {}).get('query',{}); end=hops(q); got={}
        for g in q.get('pages',[]): got.setdefault(g['title'],[]).extend(c['title'] for c in g.get('categories',[]))
        return {t:got.get(end(t),[]) for t in part}
    return per_key('cats-'+site,titles,ask,read)
WINECAT=re.compile(r'wine|viticultur|vineyard|appellation',re.I)
def find_all():
    eu=eu_items(); found={}
    ent=entities(ids=sorted({eu[x['eu_id']] for x in T.values() if x.get('eu_id') in eu}))
    ME=meta(sorted(ent))
    def winey(q):   # some editors put the EU id on the island or town itself (Ischia, Samos): that item's readers are not wine's
        d,c=ME.get(q,('',[])); return bool(WINE.search(d) or set(c)&(PLACE|CLASSES))
    for n,x in T.items():   # an EU item with no article anywhere, or not about wine, falls through to the title lookup
        q=eu.get(x.get('eu_id'))
        if q and q in ent and ent[q]['links'] and winey(q): found[n]=dict(via='eAmbrosia id on Wikidata',**ent[q])
    rest={n:candidates(n) for n in T if n not in found}
    bare={n:base(n) for n in rest if T[n]['depth']>0 and T[n].get('kind') not in ('group','state','region')}   # a bare "Salta" is the city
    hit=resolve('enwiki',[t for ts in rest.values() for t in ts]+[t for ts in bare.values() for t in ts]); print(f'{len(hit)} titles exist',flush=True)
    M=meta([q for _,q in hit.values()])
    LK=entities(sorted({q for f,q in hit.values()}))
    def named(n,q):   # the item's article, in some language, carries the place's name: Pfalz is "Pfalz (Weinanbaugebiet)" in German
        ts=[norm(v) for v in LK.get(q,{}).get('links',{}).values()]
        return any(m and any(m in x for x in ts) for m in map(norm,base(n)))
    CT=cats('enwiki',sorted({t for n,ts in bare.items() for t in ts if t in hit}))   # Colchagua Valley is in "Wine regions of Chile"
    def ok(t,b):   # a bare name, or a title that redirects, counts only when the item it lands on is a wine place: a description
        f,q=hit[t]; d,c=M.get(q,('',[])); c=set(c)   # that says so, or one of CLASSES. That keeps out communes, lakes, towns, grapes, disambiguations.
        if b and c&SETTLED and not c&PLACE: return False
        return not (b or f!=t) or not ('disambiguation' in d or c&NOT or not (WINE.search(d) or c&CLASSES or (b and any(WINECAT.search(x) for x in CT.get(t,[])))))
    pick={}
    for n,ts in rest.items():   # the first of its usual titles that has an article; the bare name only as a last resort
        if n in NOT_PLACE: continue
        good=lambda t:hit[t][0]==t or named(n,hit[t][1])   # a redirect must land on an article about this place, not "Sparkling wine"
        t=next(((t,False) for t in ts if t in hit and ok(t,False) and good(t)),None) or next(((t,True) for t in bare.get(n,[]) if t in hit and ok(t,True) and good(t)),None)
        if t: pick[n]=t+tuple(hit[t[0]])
    # One article, one place: a title that is the article itself beats a redirect to it, then the broader place.
    best={}
    for n,(t,b,f,q) in pick.items():
        k=(f!=t,b,T[n]['depth'])
        if q not in best or k<best[q][0]: best[q]=(k,n)
    for n,x in found.items(): best[x['q']]=((False,False,-1),n)
    ent=entities(ids=sorted({q for *_,q in pick.values()}))
    for n,(t,b,f,q) in pick.items():
        if best[q][1]==n and q in ent:
            found[n]=dict(via=f'English Wikipedia "{t}"'+(f' (redirects to "{f}")' if f!=t else '')+(' (a wine place on Wikidata)' if b else ''),**ent[q])
    print(f'{len(found)} of {len(T)} places have an article',flush=True)
    return found
# ---- page views
DAYS=60   # the most the batched pageviews query gives; 12 months would be one request per article, hours at Wikimedia's throttle
def views(site,titles):
    """Each article's user page views over the last DAYS days: {title: views}."""
    host=site[:-4].replace('_','-')+'.wikipedia.org'
    def ask(part):
        pages=[]; cont={}; first=None
        while True:
            r=api(host,action='query',prop='pageviews',pvipdays=DAYS,redirects=1,titles='|'.join(part),**cont)
            q=(r or {}).get('query',{}); first=first or q; pages+=q.get('pages',[])
            cont={k:v for k,v in ((r or {}).get('continue') or {}).items() if k!='continue'}
            if not cont: return dict(query=dict(first,pages=pages))
    def read(part,r):
        q=(r or {}).get('query',{}); end=hops(q); got={}
        for g in q.get('pages',[]):
            if 'pageviews' in g: got[g['title']]=got.get(g['title'],0)+sum(v or 0 for v in g['pageviews'].values())
        return {t:got.get(end(t),0) for t in part}
    return per_key(f'pv{DAYS}-{site}',titles,ask,read)
def fetch():
    os.makedirs(CA,exist_ok=True); found=find_all(); want={}
    for n,f in found.items():
        for s in {'enwiki',(LANG.get(country(n),'en')+'wiki')}:
            if s in f['links']: want.setdefault(s,[]).append(f['links'][s])
    got={s:views(s,ts) for s,ts in want.items()}; pv={}
    for n,f in found.items():
        for s in {'enwiki',(LANG.get(country(n),'en')+'wiki')}:
            if s in f['links']: pv.setdefault(n,{})[s]=got[s].get(f['links'][s],0)
    json.dump(dict(found=found,views=pv,days=DAYS,fetched=datetime.date.today().isoformat()),open(os.path.join(CA,'_all.json'),'w',encoding='utf-8'),ensure_ascii=False)
    print(f'{len(found)} of {len(T)} places have an article; {sum(len(v) for v in want.values())} page view counts')
def pct(vals):
    s=sorted(vals); N=len(s)
    def p(v):   # the share of places below v, ties counted half
        import bisect
        lo,hi=bisect.bisect_left(s,v),bisect.bisect_right(s,v); return 100*(lo+(hi-lo)/2)/N
    return p
def wiki_url(links,home):
    for s in ('enwiki',home+'wiki'):
        if s in links: return f"https://{s[:-4].replace('_','-')}.wikipedia.org/wiki/"+urllib.parse.quote(links[s].replace(' ','_'))
def build():
    d=json.load(open(os.path.join(CA,'_all.json'),encoding='utf-8')); F,PV=d['found'],d['views']
    rows={n:dict(langs=len(f['links']),views=sum(PV.get(n,{}).values())) for n,f in F.items()}
    pl,pvw=pct([r['langs'] for r in rows.values()]),pct([math.log10(r['views']+1) for r in rows.values()])
    out={}
    for n,r in rows.items():
        f=F[n]; out[n]=dict(score=round((pl(r['langs'])+pvw(math.log10(r['views']+1)))/2,1),langs=r['langs'],views=r['views'],
                            days=d['days'],wikidata=f['q'],article=f['links'].get('enwiki') or f['links'].get(LANG.get(country(n),'en')+'wiki'),via=f['via'],
                            url=wiki_url(f['links'],LANG.get(country(n),'en')))
    # A country or region is scored from its parts: the mean of (a) how much people read about all of it, every article in it
    # counted once, as a percentile among the places at the same depth, and (b) the score of its best-known single place.
    # (a) rewards depth, so France beats Uruguay; (b) keeps one star, Champagne or Napa, from being outvoted by a long list of
    # small appellations. A plain average of the parts would punish big registers: the US has 275 AVAs, most of them obscure.
    own={n:x['score'] for n,x in out.items()}; sub={}
    def walk(n):
        s=[n]
        for k in T[n].get('children',[]): s+=walk(k)
        sub[n]=s; return s
    for n in T:
        if T[n]['depth']==0: walk(n)
    parts={}
    for n,ks in sub.items():
        ks=[k for k in ks if k in own]
        if not T[n].get('children') or not ks: continue
        arts={out[k]['wikidata']:out[k]['views'] for k in ks}
        parts[n]=dict(total=sum(arts.values()),articles=len(arts),best=max(ks,key=lambda k:own[k]))
    level={}
    for n,x in parts.items(): level.setdefault(T[n]['depth'],[]).append(math.log10(x['total']+1))
    level={k:pct(v) for k,v in level.items()}
    for n,x in parts.items():
        out[n]=dict(out.get(n,{}),score=round((level[T[n]['depth']](math.log10(x['total']+1))+own[x['best']])/2,1),own=own.get(n),
                    articles=x['articles'],total=x['total'],best=None if x['best']==n else x['best'],days=d['days'])
    json.dump({'$about':'How well known each place is, from Wikipedia. Built by src/notoriety.py; the method is in its docstring.',
               '$sources':{'wikidata':'Wikidata, sitelinks and eAmbrosia ids (P9854), https://www.wikidata.org','pageviews':f"Wikipedia pageviews (MediaWiki API prop=pageviews), user views over the {d['days']} days before {d['fetched']}, https://www.mediawiki.org/wiki/Extension:PageViewInfo"},
               'fetched':d['fetched'],'places':dict(sorted(out.items()))},open(OUT,'w',encoding='utf-8'),ensure_ascii=False,indent=0)
    print(f'{len(out)} places scored, {len(T)-len(out)} with no article; wrote {os.path.relpath(OUT,ROOT)}')
def check():
    P=json.load(open(OUT,encoding='utf-8'))['places']
    tops=sorted([n for n in T if T[n]['depth']==0],key=lambda n:-P.get(n,{}).get('score',-1))
    for c in tops:
        x=P.get(c,{}); print(f"{T[c]['name']:<18} {x.get('score','-'):>5} langs {x.get('langs','-'):>3} views {x.get('views','-'):>8}  {x.get('article')}")
    for c in ('france','italy','united-states','france/burgundy','france/cote-d-or'):
        kids=sorted(T[c]['children'],key=lambda n:-P.get(n,{}).get('score',-1))
        print('\n'+T[c]['name']+': '+', '.join(f"{T[k]['name']} {P.get(k,{}).get('score','-')}" for k in kids))
    miss=[n for n in T if n not in P]; print(f'\nno article: {len(miss)}', ', '.join(miss[:40]))
if __name__=='__main__':
    {'fetch':fetch,'build':build,'check':check}[sys.argv[1] if len(sys.argv)>1 else 'check']()
