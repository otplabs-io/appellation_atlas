#!/usr/bin/env python3
"""Key facts for the classic places: the few things a Diploma student must know (a classification, an ageing rule, a defining
style or method), each taken from the place's full Wikipedia article at a fixed revision and cited on the page.
Usage: python src/keyfacts.py fetch     the full text of each listed place's article (data/cache/wikipedia/full/)
       python src/keyfacts.py packets   one packet per place: the article text and the topics to look for (build/keyfacts/packets/)
       python src/keyfacts.py check     every written fact has a packet and a short, plain sentence
Facts are written from the packets alone into regions/keyfacts/*.json as {id: {facts: [sentence, ...]}}. The topics are only
pointers to what to look for; a fact goes in only when the article says it."""
import json,os,re,sys,time,urllib.error,urllib.parse,urllib.request
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.path.dirname(HERE)
CACHE=os.path.join(ROOT,'data','cache','wikipedia','full'); OUT=os.path.join(ROOT,'build','keyfacts')
UA='AppellationAtlas/1.0 (non-commercial wine atlas build script)'
def jl(p): return json.load(open(p,encoding='utf-8'))
TOPICS=jl(os.path.join(ROOT,'regions','keyfacts-topics.json'))['places']
# places whose own article the notoriety step did not find; a country article stands in where the place has none, and the
# writer takes only what it says about the place itself
ART={'france/rhone-valley':('en','Rhône wine'),'south-africa/stellenbosch':('en','South African wine'),'south-africa/swartland':('en','South African wine'),
     'chile/maipo-valley':('en','Chilean wine'),'chile/casablanca-valley':('en','Chilean wine'),'argentina/valle-de-uco':('en','Argentine wine'),
     'canada/niagara-peninsula':('en','Ontario wine'),'france/muscadet-sevre-et-maine':('en','Muscadet')}
def article(k):
    if k in ART: return ART[k]
    n=jl(os.path.join(ROOT,'regions','notoriety.json'))['places'].get(k) or {}
    m=re.match(r'https://(\w+)\.wikipedia\.org/wiki/(.+)$',n.get('url') or '')
    return (m.group(1),urllib.parse.unquote(m.group(2)).replace('_',' ')) if m else None
def fetch():
    os.makedirs(CACHE,exist_ok=True)
    for k in TOPICS:
        a=article(k)
        if not a: print('no article:',k); continue
        p=os.path.join(CACHE,k.replace('/','__')+'.json')
        if os.path.exists(p): continue
        q=dict(action='query',prop='extracts|revisions',explaintext=1,rvprop='ids',redirects=1,format='json',formatversion=2,titles=a[1])
        for wait in (5,15,45,120):
            try:
                d=json.load(urllib.request.urlopen(urllib.request.Request(f'https://{a[0]}.wikipedia.org/w/api.php?'+urllib.parse.urlencode(q),headers={'User-Agent':UA}),timeout=60)); break
            except urllib.error.HTTPError as e:
                if e.code!=429: raise
                time.sleep(int(e.headers.get('Retry-After') or wait))
        pg=d['query']['pages'][0]; rev=pg['revisions'][0]['revid']
        json.dump(dict(lang=a[0],title=pg['title'],revid=rev,text=pg.get('extract',''),
                       url=f"https://{a[0]}.wikipedia.org/w/index.php?title={urllib.parse.quote(pg['title'].replace(' ','_'))}&oldid={rev}"),
                  open(p,'w',encoding='utf-8'),ensure_ascii=False)
        time.sleep(1.5)
    print('fetched')
def packets():
    os.makedirs(os.path.join(OUT,'packets'),exist_ok=True); n=0
    for k,topics in TOPICS.items():
        p=os.path.join(CACHE,k.replace('/','__')+'.json')
        if not os.path.exists(p): continue
        a=jl(p)
        json.dump(dict(id=k,topics=topics,article=dict(title=a['title'],lang=a['lang'],url=a['url'],text=a['text'][:30000])),
                  open(os.path.join(OUT,'packets',k.replace('/','__')+'.json'),'w',encoding='utf-8'),ensure_ascii=False,indent=1); n+=1
    print(n,'packets')
def written():
    d=os.path.join(ROOT,'regions','keyfacts'); out={}
    for fn in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if fn.endswith('.json') and ' ' not in fn: out.update(jl(os.path.join(d,fn)))
    return out
def check():
    K=written(); bad=[]
    for k,v in K.items():
        if not os.path.exists(os.path.join(OUT,'packets',k.replace('/','__')+'.json')): bad.append((k,'no packet'))
        for f in v.get('facts',[]):
            if re.search(r'[—–]|\[\d+\]|according to|wikipedia',f,re.I): bad.append((k,'dash or citation: '+f[:60]))
            if len(f.split())>40: bad.append((k,'long: '+f[:60]))
    print(f'{len(K)} places, {sum(len(v.get("facts",[])) for v in K.values())} facts, {len(bad)} problems'); [print(' ',x) for x in bad[:30]]
if __name__=='__main__':
    {'fetch':fetch,'packets':packets}.get(sys.argv[1] if len(sys.argv)>1 else '',check)()
