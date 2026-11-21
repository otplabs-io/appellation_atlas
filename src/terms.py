#!/usr/bin/env python3
"""What the words on a label mean: the labelling terms the WSET Level 2 and Level 3 specifications list, each defined from a
Wikipedia article at a fixed revision (data/cache/wikipedia/terms), and the places whose pages show them.
Usage: python src/terms.py fetch     the articles the definitions are written from
       python src/terms.py check     every term has a definition, a source and a short, plain sentence
Definitions are written from the articles alone into regions/label-terms.json."""
import json,os,re,sys,time,urllib.error,urllib.parse,urllib.request
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.path.dirname(HERE)
CACHE=os.path.join(ROOT,'data','cache','wikipedia','terms'); TERMS=os.path.join(ROOT,'regions','label-terms.json')
UA='AppellationAtlas/1.0 (non-commercial wine atlas; build script)'
ARTICLES=['Appellation d\'origine contrôlée','Vin de pays','Vin de France','Cru Bourgeois','Bordeaux Wine Official Classification of 1855',
  'Classification of Saint-Émilion wine','Graves (wine)','Bordeaux wine','Burgundy wine','Alsace Grand Cru AOC','Alsace wine','Beaujolais nouveau','Beaujolais',
  'Muscadet','Champagne','Blanc de blancs','Blanc de noirs','Sweetness of wine','German wine classification','Verband Deutscher Prädikatsweingüter','Sekt',
  'Austrian wine','Tokaji','Italian wine','Chianti Classico','Ripasso','Spanish wine','Rioja (wine)','Sherry','Port wine','American Viticultural Area',
  'Vintners Quality Alliance','Chilean wine','Wine of Origin','Cap Classique','Pinotage','Australian Geographical Indication','Old vine','Late harvest wine',
  'Ice wine','Noble rot','Vintage','Recioto','Amarone','Chianti','Cava (Spanish wine)','Prosecco','Asti (wine)','Crémant','Riserva']
def fetch():
    os.makedirs(CACHE,exist_ok=True)
    for t in ARTICLES:
        p=os.path.join(CACHE,re.sub(r'[^\w]+','_',t)+'.json')
        if os.path.exists(p): continue
        q=dict(action='query',prop='extracts|revisions',explaintext=1,rvprop='ids',redirects=1,format='json',formatversion=2,titles=t)
        for wait in (10,30,90,240):
            try: d=json.load(urllib.request.urlopen(urllib.request.Request('https://en.wikipedia.org/w/api.php?'+urllib.parse.urlencode(q),headers={'User-Agent':UA}),timeout=60)); break
            except urllib.error.HTTPError as e:
                if e.code!=429: raise
                time.sleep(int(e.headers.get('Retry-After') or wait))
        pg=d['query']['pages'][0]
        if pg.get('missing'): print('missing:',t); continue
        rev=pg['revisions'][0]['revid']
        json.dump(dict(title=pg['title'],revid=rev,text=pg.get('extract',''),url=f"https://en.wikipedia.org/w/index.php?title={urllib.parse.quote(pg['title'].replace(' ','_'))}&oldid={rev}"),
                  open(p,'w',encoding='utf-8'),ensure_ascii=False)
        print(pg['title'],len(pg.get('extract','')),flush=True); time.sleep(4)
def check():
    T=json.load(open(TERMS,encoding='utf-8')); bad=[]
    arts={json.load(open(os.path.join(CACHE,f),encoding='utf-8'))['title'] for f in os.listdir(CACHE)}
    for k,v in T['terms'].items():
        if v.get('source') not in arts and not v.get('source','').startswith('SRC:'): bad.append((k,'no source article'))
        if re.search(r'[—–]|\[\d+\]|wikipedia',v.get('def',''),re.I): bad.append((k,'dash or citation'))
        if len(v.get('def','').split())>45: bad.append((k,'long'))
    for k,ts in T['places'].items():
        for t in ts:
            if t not in T['terms']: bad.append((k,'unknown term '+t))
    print(len(T['terms']),'terms,',len(T['places']),'places,',len(bad),'problems'); [print(' ',b) for b in bad]
if __name__=='__main__': {'fetch':fetch}.get(sys.argv[1] if len(sys.argv)>1 else '',check)()
