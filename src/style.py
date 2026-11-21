#!/usr/bin/env python3
"""In the glass: what the wines of the WSET Level 2 and 3 places taste like (body, acidity, tannin, sweetness, flavors, how they age),
each note taken from a Wikipedia article at a fixed revision and cited on the page.
Usage: python src/style.py resolve   find each place's article: its own, else one its parents' articles stand in for (regions/style-articles.json)
       python src/style.py fetch     the full text of each article (data/cache/wikipedia/full/)
       python src/style.py packets   one short digest per place: the sentences that describe its wines (build/style/)
       python src/style.py check     every written note has an article and is a short, plain sentence
Notes are written from the digests alone into regions/style/*.json as {id: {notes: [sentence, ...], art: [title, ...]}}.
A place with no notes of its own shows the nearest region above it that has them, named as such."""
import json,os,re,sys,time,urllib.error,urllib.parse,urllib.request
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.path.dirname(HERE)
CACHE=os.path.join(ROOT,'data','cache','wikipedia','full'); OUT=os.path.join(ROOT,'build','style')
ARTS=os.path.join(ROOT,'regions','style-articles.json')
UA='AppellationAtlas/1.0 (non-commercial wine atlas; build script)'
def jl(p): return json.load(open(p,encoding='utf-8'))

def api(q,lang='en'):
    for wait in (5,15,45,120,240):
        try:
            return json.load(urllib.request.urlopen(urllib.request.Request(f'https://{lang}.wikipedia.org/w/api.php?'+urllib.parse.urlencode(q),headers={'User-Agent':UA}),timeout=60))
        except urllib.error.HTTPError as e:
            if e.code!=429: raise
            time.sleep(int(e.headers.get('Retry-After') or wait))
    raise SystemExit('Wikipedia kept saying too many requests')

def targets():
    W=jl(os.path.join(ROOT,'regions','wset-levels.json'))
    return list(dict.fromkeys(W['2']['places']+W['3']['places']))

def tree():
    return jl(os.path.join(ROOT,'public','places.json'))['places']

def resolve():
    """Each place's own article from the notoriety step, else the first wine article found under its name."""
    N=jl(os.path.join(ROOT,'regions','notoriety.json'))['places']; P=tree()
    A=jl(ARTS) if os.path.exists(ARTS) else {'$about':'The Wikipedia article each WSET place\'s style notes come from (src/style.py resolve). A title is the place\'s own article; ~title is a wider article that speaks for the place only where it names it.','places':{}}
    todo=[]
    for k in targets():
        if k in A['places']: continue
        m=re.match(r'https://(\w+)\.wikipedia\.org/wiki/(.+)$',(N.get(k) or {}).get('url') or '')
        if m and m.group(1)=='en': A['places'][k]=urllib.parse.unquote(m.group(2)).replace('_',' ')
        else: todo.append(k)
    cand={}
    for k in todo:
        n=P[k][0]
        for t in [f'{n} AOC',f'{n} wine',f'{n} (wine)',f'{n} DOC',f'{n} DOCG',f'{n} wine region',f'{n} (wine region)',f'{n} AVA',f'{n} (wine appellation)',n]:
            cand.setdefault(t,[]).append(k)
    ts=list(cand); hit={}
    for i in range(0,len(ts),40):
        d=api(dict(action='query',titles='|'.join(ts[i:i+40]),redirects=1,prop='extracts',exintro=1,explaintext=1,exsentences=2,exlimit='max',format='json',formatversion=2))
        red={r['from']:r['to'] for r in d['query'].get('redirects',[])}; norm={r['from']:r['to'] for r in d['query'].get('normalized',[])}
        pages={p['title']:p for p in d['query']['pages'] if not p.get('missing')}
        for t in ts[i:i+40]:
            tt=norm.get(t,t); tt=red.get(tt,tt)
            if tt in pages and re.search(r'\bwines?\b',pages[tt].get('extract',''),re.I):
                for k in cand[t]: hit.setdefault(k,tt)
        time.sleep(3)
    for k in todo: A['places'][k]=hit.get(k)
    json.dump(A,open(ARTS,'w',encoding='utf-8'),ensure_ascii=False,indent=1)
    print(sum(1 for v in A['places'].values() if v),'of',len(A['places']),'places have an article')

def cfile(title): return os.path.join(CACHE,'t__'+re.sub(r'[^\w.-]+','_',title)+'.json')

def subjects():
    """The WSET places and every region above them: a place with no notes of its own shows its region's."""
    P=tree(); out=[]
    for k in targets():
        q=k
        while q and q in P and q!='world':
            out.append(q); q=P[q][1]
    return list(dict.fromkeys(out))

def articles():
    """Every article a place's digest reads: its own and those of the regions above it."""
    A=jl(ARTS)['places']; P=tree(); out={}
    for k in subjects():
        chain=[]; q=k
        while q and q in P:
            if A.get(q): chain.append(A[q].lstrip('~'))
            q=P[q][1]
        out[k]=list(dict.fromkeys(chain))
    return out

# the grapes' own articles describe their wines place by place (Malbec in Mendoza, Sauvignon Blanc in Marlborough); a place
# takes a grape article's sentence only where it is named
GRAPES=['Cabernet Sauvignon','Merlot','Cabernet Franc','Pinot noir','Chardonnay','Sauvignon blanc','Sémillon','Riesling','Chenin blanc',
        'Syrah','Grenache','Mourvèdre','Carignan','Cinsaut','Malbec','Carménère','Pinotage','Zinfandel','Petite Sirah','Tempranillo','Mencía',
        'Gamay','Pinot gris','Pinot blanc','Gewürztraminer','Muscat (grape and wine)','Viognier','Marsanne','Roussanne','Melon de Bourgogne',
        'Nebbiolo','Sangiovese','Barbera','Dolcetto','Corvina','Garganega','Glera (grape)','Cortese (grape)','Montepulciano (grape)','Aglianico',
        'Fiano (grape)','Greco (grape)','Verdicchio','Nero d\'Avola','Negroamaro','Vermentino','Trebbiano','Albariño','Verdejo','Godello','Macabeo',
        'Xarel·lo','Parellada','Palomino (grape)','Pedro Ximénez (grape)','Touriga Nacional','Touriga Franca','Baga (grape)','Alvarinho','Loureiro',
        'Grüner Veltliner','Blaufränkisch','Zweigelt','Furmint','Assyrtiko','Xinomavro','Agiorgitiko','Torrontés','Bonarda','Tannat','Muscadelle',
        'Petit Verdot','Pinot Meunier','Aligoté','Silvaner','Müller-Thurgau','Colombard','Bobal','Monastrell','Piquepoul','Cabernet Sauvignon']

def fetch():
    os.makedirs(CACHE,exist_ok=True)
    A=jl(ARTS)['places']
    for k in targets():   # the regions above a WSET place need their articles too: Chilean wine for the valleys
        q=k; P=tree()
        while q and q in P:
            if q not in A: A[q]=None
            q=P[q][1]
    N=jl(os.path.join(ROOT,'regions','notoriety.json'))['places']
    for k,t in list(A.items()):
        if t: continue
        m=re.match(r'https://en\.wikipedia\.org/wiki/(.+)$',(N.get(k) or {}).get('url') or '')
        if m: A[k]=urllib.parse.unquote(m.group(1)).replace('_',' ')
    d=jl(ARTS); d['places']=A; json.dump(d,open(ARTS,'w',encoding='utf-8'),ensure_ascii=False,indent=1)
    for t in sorted({t.lstrip('~') for t in A.values() if t}|set(GRAPES)):
        p=cfile(t)
        if os.path.exists(p): continue
        d=api(dict(action='query',prop='extracts|revisions',explaintext=1,rvprop='ids',redirects=1,format='json',formatversion=2,titles=t))
        pg=d['query']['pages'][0]
        if pg.get('missing'): print('missing:',t); continue
        rev=pg['revisions'][0]['revid']
        json.dump(dict(lang='en',title=pg['title'],revid=rev,text=pg.get('extract',''),
                       url=f"https://en.wikipedia.org/w/index.php?title={urllib.parse.quote(pg['title'].replace(' ','_'))}&oldid={rev}"),
                  open(p,'w',encoding='utf-8'),ensure_ascii=False)
        print('fetched',t); time.sleep(2)

STYLE=re.compile(r'\b(bod(y|ied)|acid(ity|ic)?|tannins?|tannic|flavou?rs?|aromas?|aromatic|fruit(y|iness)?|cherr(y|ies)|plums?|blackcurrant|cassis|black ?berr(y|ies)|raspberr(y|ies)|strawberr(y|ies)|citrus|lemon|lime|grapefruit|apples?|pears?|peach(es)?|apricots?|melon|tropical|honey(ed)?|mineral(ity)?|herbaceous|grassy|spic(e|y)|pepper(y)?|earthy|toast(y)?|butter(y)?|nutty|almonds?|crisp|delicate|structured?|sweet(ness)?|dry|alcohol|age(ing|ing)? (potential|well|for)|cellar(ing)?|ruby|garnet|straw|perfumed?|floral|violets?|roses?|tar|leather|tobacco|chocolate|smoky|petrol|kerosene|elegan(t|ce)|powerful|concentrat(ed|ion)|rich(ness)?|light|full|lean|austere|soft|supple|velvety|robust|rustic|fresh(ness)?|zesty|steely|nose|palate|bouquet|style|gooseberr(y|ies)|passion ?fruit|herbal|bell pepper|green|vanilla|cedar|mint|eucalyptus|jammy|marmalade|quince|nuts|brioche|biscuit|yeasty|savou?ry|gamey|olives?|licorice|liquorice|lavender|garrigue|salty|saline|blackberr(y|ies)|red fruit|black fruit|ripe|tart|bitter|firm|intense|weighty|oily|waxy|smooth|charming|fragrant|truffle|mushroom|figs?|raisins?|dried fruit|caramel|toffee|coffee)\b',re.I)
def sentences(text):
    text=re.sub(r'\n+=+[^=\n]+=+\n+','\n',text)
    out=[]
    for para in text.split('\n'):
        for s in re.split(r'(?<=[.!?])\s+(?=[A-Z"“(])',para.strip()):
            if 25<len(s)<600: out.append(s)
    return out

DEMONYM={'argentina':'Argentine|Argentinian','australia':'Australian','austria':'Austrian','canada':'Canadian','chile':'Chilean','france':'French',
         'germany':'German','greece':'Greek','hungary':'Hungarian','italy':'Italian','new-zealand':'New Zealand','portugal':'Portuguese',
         'south-africa':'South African','spain':'Spanish','united-states':'American','united-states/california':'Californian'}
def packets():
    os.makedirs(OUT,exist_ok=True); P=tree(); AR=articles(); n=0; A=jl(ARTS)['places']
    for k in subjects():
        name=P[k][0]; base=re.sub(r'\s*\(.*\)','',name)
        ns={name,base,re.sub(r'^(Valle de |Valle del )|( Valley| County| Region)$','',base)}|set(P[k][5] or [])
        keys=[r'(?<![\w-])'+re.escape(x)+r'(?![\w-])' for x in ns if len(x)>3]+([r'\b('+DEMONYM[k]+r')\b'] if k in DEMONYM else [])   # Napa as well as Napa Valley, Argentine Malbec, never Tours-sur-Marne
        own=A.get(k); own=own if own and not own.startswith('~') else None
        lines=[]
        for t in AR[k]+[g for g in GRAPES if g not in AR[k]]:
            p=cfile(t)
            if not os.path.exists(p): continue
            a=jl(p); mine=t==own
            for s in sentences(a['text']):
                m=len(STYLE.findall(s)); named=re.search('|'.join(keys),s)
                if not (named and m>=1 or mine and m>=2): continue   # another article speaks for the place only where it names it
                lines.append((a['title'],s))
        top=sorted(range(len(lines)),key=lambda i:-len(STYLE.findall(lines[i][1])))[:14 if '/' in k else 24]   # the sentences that say most about the wine, in article order
        dig=dict(id=k,name=name,own=own,wset=k in targets(),lines=[lines[i] for i in sorted(top)])
        json.dump(dig,open(os.path.join(OUT,k.replace('/','__')+'.json'),'w',encoding='utf-8'),ensure_ascii=False,indent=1); n+=1
    print(n,'digests')

def written():
    d=os.path.join(ROOT,'regions','style'); out={}
    for fn in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if fn.endswith('.json') and ' ' not in fn: out.update(jl(os.path.join(d,fn)))
    return out

def refs():
    """The style sources that are not Wikipedia: official specifications, national wine bodies, a GI register (regions/style-sources.json)."""
    p=os.path.join(ROOT,'regions','style-sources.json')
    return jl(p)['sources'] if os.path.exists(p) else {}

def source(title):
    p=cfile(title)
    return jl(p) if os.path.exists(p) else None

def check():
    S=written(); R=refs(); bad=[]
    for k,v in S.items():
        for r in v.get('ref',[]):
            if r not in R: bad.append((k,'no source: '+r))
        for t in v.get('art',[]):
            if not source(t): bad.append((k,'no article: '+t))
        for f in v.get('notes',[]):
            if re.search(r'[—–]|\[\d+\]|according to|wikipedia',f,re.I): bad.append((k,'dash or citation: '+f[:60]))
            if len(f.split())>40: bad.append((k,'long: '+f[:60]))
            if re.search(r'\b(flavour|colour|savoury|ageing|aluminium|centre)\b',f): bad.append((k,'British spelling: '+f[:60]))
    print(f'{len(S)} places, {sum(len(v.get("notes",[])) for v in S.values())} notes, {len(bad)} problems'); [print(' ',x) for x in bad[:40]]

if __name__=='__main__':
    {'resolve':resolve,'fetch':fetch,'packets':packets}.get(sys.argv[1] if len(sys.argv)>1 else '',check)()
