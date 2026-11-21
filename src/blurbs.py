#!/usr/bin/env python3
"""The short blurb at the top of each place's page: what the place is known for, leaning toward what the WSET Diploma
stresses (the styles and grapes a student meets there).
Usage: python src/blurbs.py fetch     the Wikipedia intro for every place with an article (data/cache/wikipedia/intros.json)
       python src/blurbs.py packets   what each blurb may draw on, one packet per place (build/blurbs/packets/*.json)
       python src/blurbs.py check     every written blurb has a packet, two or three sentences, no dashes or citations
       python src/blurbs.py cite      adds the Wikipedia article and revision each blurb read, for its Sources
Blurbs are written from the packets alone and kept in regions/blurbs/*.json as {id: {text, from: [source keys]}}.
A packet holds the place's own facts (rules, plantings, where it sits, whether the Diploma lists it) and, when it has one,
its Wikipedia article's intro. The source keys are 'wikipedia' (that article, at the revision read), 'rules' (the
EU product specification, AVA or GI record) and 'planted' (Anderson et al.)."""
import json,os,re,sys,time,urllib.error,urllib.parse,urllib.request
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.path.dirname(HERE)
CACHE=os.path.join(ROOT,'data','cache','wikipedia'); OUT=os.path.join(ROOT,'build','blurbs')
UA='AppellationAtlas/1.0 (non-commercial wine atlas build script)'
def jl(p): return json.load(open(p,encoding='utf-8'))
def places(scope='benchmark'):
    P=jl(os.path.join(ROOT,'public','places.json'))['places']
    return [k for k,x in P.items() if scope=='all' or (scope=='emerging')==(not x[6])]
def articles(ids):
    N=jl(os.path.join(ROOT,'regions','notoriety.json'))['places']
    out={}
    for k in ids:
        u=(N.get(k) or {}).get('url') or ''
        m=re.match(r'https://(\w+)\.wikipedia\.org/wiki/(.+)$',u)
        if m: out[k]=(m.group(1),urllib.parse.unquote(m.group(2)).replace('_',' '))
    return out
def fetch(scope='benchmark'):
    os.makedirs(CACHE,exist_ok=True); cp=os.path.join(CACHE,'intros.json')
    cache=jl(cp) if os.path.exists(cp) else {}
    want=sorted({a for a in articles(places(scope)).values() if f'{a[0]}:{a[1]}' not in cache})
    by={}
    for lang,t in want: by.setdefault(lang,[]).append(t)
    for lang,ts in by.items():
        for i in range(0,len(ts),20):
            q=dict(action='query',prop='extracts|revisions',exintro=1,explaintext=1,exlimit=20,rvprop='ids',redirects=1,format='json',formatversion=2,titles='|'.join(ts[i:i+20]))
            req=urllib.request.Request(f'https://{lang}.wikipedia.org/w/api.php?'+urllib.parse.urlencode(q),headers={'User-Agent':UA})
            for wait in (5,15,45,120,300):
                try: d=json.load(urllib.request.urlopen(req,timeout=60))['query']; break
                except urllib.error.HTTPError as e:
                    if e.code!=429: raise
                    time.sleep(int(e.headers.get('Retry-After') or wait))
            else: raise SystemExit('Wikipedia keeps refusing; try again later')
            back={x['to']:x['from'] for x in d.get('normalized',[])+d.get('redirects',[])}
            for p in d.get('pages',[]):
                if p.get('missing'): continue
                t=p['title']; src=back.get(t,t); src=back.get(src,src)
                rev=(p.get('revisions') or [{}])[0].get('revid')
                cache[f'{lang}:{src}']=dict(title=t,extract=p.get('extract',''),revid=rev,url=f'https://{lang}.wikipedia.org/w/index.php?title={urllib.parse.quote(t.replace(" ","_"))}&oldid={rev}')
            json.dump(cache,open(cp,'w',encoding='utf-8'),ensure_ascii=False)
            time.sleep(2)
    print(f'{len(cache)} intros cached, {len(want)} asked for')
def packets(scope='benchmark'):
    ids=places(scope); A=articles(places('all'))
    cache=jl(os.path.join(CACHE,'intros.json'))
    P=jl(os.path.join(ROOT,'public','places.json'))['places']
    os.makedirs(os.path.join(OUT,'packets'),exist_ok=True); n=0
    for k in ids:
        fp=os.path.join(ROOT,'public','facts',k.replace('/','__')+'.json')
        if not os.path.exists(fp): continue
        f=jl(fp); ru=f.get('rules') or {}; pl=f.get('planted') or {}
        kids=[P[c][0] for c in P if P[c][1]==k][:12]
        p=dict(id=k,name=f['name'],also=f.get('also',[]),kind=f.get('kind',[]),country=f['country'],within=[n for _,n in f.get('chain',[])],   # every larger place, nearest last (the chain leaves out the place itself)
               wset=bool(f.get('study')),benchmark=bool(P[k][6]),places_inside=kids)
        if ru: p['rules']={k2:ru[k2] for k2 in ('types','grapes','grapes_other','communes') if ru.get(k2)}
        else:   # the rules of the nearest larger place, for a village or zone with none of its own (Oger in Champagne)
            for a,an in reversed(f.get('chain',[])):
                ap=os.path.join(ROOT,'public','facts',a.replace('/','__')+'.json')
                ar=(jl(ap).get('rules') if os.path.exists(ap) else None) or {}
                if ar.get('grapes'): p['rules_of_wider']=dict(place=an,**{k2:ar[k2] for k2 in ('types','grapes','grapes_other') if ar.get(k2)}); break
        if f.get('ava'): p['ava']={k2:v for k2,v in f['ava'].items() if k2 in ('created','states','counties','within','contains')}
        if f.get('gi'): p['gi']={k2:v for k2,v in f['gi'].items() if k2 in ('type','area_km2','vines_ha','state') and v}
        if pl and pl.get('scope') in ('own','within','country'): p['planted']=dict(where=pl.get('names'),top=[[g,round(100*ha/pl['ha'])] for g,ha,*_ in pl['grapes'] if g!='Other'][:6])
        elif pl and pl.get('ha'): p['planted_wider']=dict(where=pl.get('names'),top=[[g,round(100*ha/pl['ha'])] for g,ha,*_ in pl['grapes'] if g!='Other'][:6])
        if k in A:
            w=cache.get(f'{A[k][0]}:{A[k][1]}')
            if w and w['extract'].strip(): p['wikipedia']=dict(lang=A[k][0],title=w['title'],intro=w['extract'][:3500],url=w['url'])
        if 'wikipedia' not in p:   # the nearest larger place's article, as context: Beaujolais for Morgon
            for a,an in reversed(f.get('chain',[])):
                w=cache.get(f'{A[a][0]}:{A[a][1]}') if a in A else None
                if w and w['extract'].strip(): p['wikipedia_of_wider']=dict(place=an,lang=A[a][0],title=w['title'],intro=w['extract'][:2000],url=w['url']); break
        json.dump(p,open(os.path.join(OUT,'packets',k.replace('/','__')+'.json'),'w',encoding='utf-8'),ensure_ascii=False,indent=1); n+=1
    print(f'{n} packets in {OUT}/packets')
def written():
    out={}
    d=os.path.join(ROOT,'regions','blurbs')
    for fn in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if fn.endswith('.json') and ' ' not in fn: out.update(jl(os.path.join(d,fn)))
    return {k:v for k,v in out.items() if not v.get('cut')}   # the audit (zaudit.json) drops a blurb with nothing left to keep
def cite():
    """Adds the Wikipedia article and revision each blurb read, from its packet, so the page can list it in Sources."""
    d=os.path.join(ROOT,'regions','blurbs')
    for fn in sorted(os.listdir(d)):
        if not fn.endswith('.json') or ' ' in fn: continue
        B=jl(os.path.join(d,fn))
        for k,b in B.items():
            pp=os.path.join(OUT,'packets',k.replace('/','__')+'.json')
            pk=jl(pp) if os.path.exists(pp) else {}
            for key in ('wikipedia','wikipedia_of_wider'):
                w=pk.get(key)
                if key in b.get('from',[]) and w: b['wiki']=dict(title=w['title'],lang=w['lang'],url=w['url']); break
            else: b.pop('wiki',None); b['from']=[x for x in b.get('from',[]) if x not in ('wikipedia','wikipedia_of_wider')]
        json.dump(B,open(os.path.join(d,fn),'w',encoding='utf-8'),ensure_ascii=False,indent=1)
def check():
    B=written(); bad=[]
    for k,b in B.items():
        t=b.get('text','')
        s=len(re.findall(r'[.!?](\s|$)',t))
        if not os.path.exists(os.path.join(OUT,'packets',k.replace('/','__')+'.json')): bad.append((k,'no packet'))
        if not 1<=s<=3: bad.append((k,f'{s} sentences'))
        if re.search(r'[—–]|\s-\s|\[\d+\]|\(source|according to',t,re.I): bad.append((k,'dash or citation'))
        if not b.get('from'): bad.append((k,'no source keys'))
    print(f'{len(B)} blurbs, {len(bad)} problems'); [print(' ',k,why) for k,why in bad[:40]]
if __name__=='__main__':
    cmd=sys.argv[1] if len(sys.argv)>1 else ''
    scope=sys.argv[2] if len(sys.argv)>2 else 'benchmark'
    if cmd in ('fetch','packets'): {'fetch':fetch,'packets':packets}[cmd](scope)
    elif cmd=='cite': cite()
    else: check()
