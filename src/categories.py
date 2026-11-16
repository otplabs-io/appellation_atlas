#!/usr/bin/env python3
"""The national quality category each place carries, in the words the WSET Diploma uses, in place of the EU's PDO and PGI.
Usage: python src/categories.py     writes regions/categories.json from the cached lists in data/cache/wikipedia/

The EU register knows only PDO and PGI. Each country names them its own way, and most of it follows from the country alone:
  France     PDO is AOC, PGI is IGP              Portugal  PDO is DOC, PGI is Vinho Regional
  Italy      PDO is DOC, or DOCG for the places on Wikipedia's "List of Italian DOCG wines"; PGI is IGT
  Spain      PDO is DO, DOCa for Rioja and Priorat, Vino de Pago for the places on Wikipedia's "Vino de Pago" list;
             PGI is Vino de la Tierra
  US         an AVA is an AVA, whatever the EU has also registered it as
Elsewhere the EU terms stay."""
import json,os,re,sys,unicodedata
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.path.dirname(HERE)
W=os.path.join(ROOT,'data','cache','wikipedia')
def jl(p): return json.load(open(p,encoding='utf-8'))
fold=lambda x:re.sub(r'[^a-z]','',unicodedata.normalize('NFKD',x).encode('ascii','ignore').decode().lower())
BY={'france':{'PDO':'AOC','PGI':'IGP'},'portugal':{'PDO':'DOC','PGI':'Vinho Regional'},'italy':{'PDO':'DOC','PGI':'IGT'},
    'spain':{'PDO':'DO','PGI':'Vino de la Tierra'}}
DOCA={'spain/rioja','spain/priorat'}
# Vinos de Pago recognised since the Wikipedia list was written, or missing from it (EU register and the Spanish ministry's list)
PAGO_MORE={'spain/tharsys','spain/abadia-retuerta','spain/chozas-carrascal','spain/el-vicario','spain/vallegarcia','spain/dehesa-penalba','spain/urbezo','spain/bolandin'}
NOT_DOCG={'italy/soave'}
DOCG_MORE={'italy/terre-alfieri','italy/canelli','italy/ciro-classico'}   # and Cirò Classico (EU Reg. 2025/1518)   # DOCGs since 2020 (Terre Alfieri) and 2023 (Canelli), after the cached list's revision   # Wikipedia's list item is "Soave Superiore": the Soave DOC itself is not a DOCG
GERMANY_13={'ahr','baden','franken','hessische-bergstrasse','mittelrhein','mosel','nahe','pfalz','rheingau','rheinhessen','saale-unstrut','sachsen','wurttemberg'}   # Spain's two Denominaciones de Origen Calificadas (Priorat's Catalan DOQ)
# names in the lists that the tree spells differently
SAME={'valdicornia':'valdicorniarosso','montecucco':'montecuccosangiovese','albanadiromagna':'romagnaalbana','valtellina':'valtellinasuperiore','dolcettodidoglianisuperiore':'dogliani',
      'terredicasauriadocg':'casauria','sagrantinodimontefalco':'montefalcosagrantino','casteldelmontenerodetroiareserva':'casteldelmontenerodetroiariserva',fold('Castel del Monte Nero di Troia Reserva'):fold('Castel del Monte Nero di Troia Riserva')}
def listed(page,country,T):
    d=jl(os.path.join(W,page))['parse']; t=d['wikitext']
    names=[(b or a).strip() for a,b in re.findall(r'^[*|]\s*(?:\'\')?\[\[([^\]|]+)(?:\|([^\]]+))?\]\]',t,re.M)]
    for line in re.findall(r'^\*(.+)$',t,re.M):   # the whole name, links and all: "[[Soave (wine)|Soave]] Superiore", "Gavi or [[Cortese di Gavi]]"
        x=re.sub(r'\[\[([^\]|]+)\|([^\]]+)\]\]',r'\2',line); x=re.sub(r'\[\[([^\]]+)\]\]',r'\1',x).strip(" '")
        head=re.split(r'\s*\(|,|\s+produced\b',x)[0].strip()
        names+=[h.strip() for h in re.split(r'\s+or\s+',head) if h.strip()]
    idx={}
    for k,v in T.items():
        if k.startswith(country+'/'):
            for nm in [v['name']]+v.get('also',[]): idx.setdefault(fold(nm),k)
    out=set()
    for nm in names:
        f=SAME.get(fold(nm),fold(nm)); k=idx.get(f) or idx.get(fold('pago'+nm)) or idx.get(fold('pago de '+nm)) or idx.get(fold(re.sub(r'^Pago (de |)','',nm)))
        if k: out.add(k)
    return sorted(out),d['revid']
def build():
    T=jl(os.path.join(ROOT,'regions','tree.json'))['nodes']
    docg,r1=listed('docg.json','italy',T); pago,r2=listed('vino-de-pago.json','spain',T); pago=sorted(set(pago)|{k for k in PAGO_MORE if k in T})
    docg=sorted({k for k in docg if k not in NOT_DOCG}|{k for k in DOCG_MORE if k in T})
    d=jl(os.path.join(W,'dac.json'))['parse']; r3=d['revid']
    names=[re.sub(r'\s*DAC$','',re.sub(r"\[\[|\]\]",'',m).split('|')[-1]).strip() for m in re.findall(r'(\[\[[^\]]+ DAC\]\]|[A-ZÄÖÜ][\w ]+ DAC)',d['wikitext'])]
    idx={fold(v['name']):k for k,v in T.items() if k.startswith('austria/')}
    dac=sorted({idx[fold(n)] for n in names if fold(n) in idx})
    json.dump({'$about':__doc__.split('\n')[0],'by_country':BY,'docg':docg,'doca':sorted(DOCA),'pago':pago,'dac':dac,
               'anbaugebiet':sorted('germany/'+x for x in GERMANY_13),
               'sources':{'docg':f'https://en.wikipedia.org/w/index.php?title=List_of_Italian_DOCG_wines&oldid={r1}',
                          'pago':f'https://en.wikipedia.org/w/index.php?title=Vino_de_Pago&oldid={r2}',
                          'dac':f'https://en.wikipedia.org/w/index.php?title=Districtus_Austriae_Controllatus&oldid={r3}'}},
              open(os.path.join(ROOT,'regions','categories.json'),'w',encoding='utf-8'),ensure_ascii=False,indent=1)
    print(f'{len(docg)} DOCGs, {len(pago)} Vinos de Pago, {len(dac)} DACs: {dac}')
def label(n,official,cats):
    """The place's categories in national words: ['DOCG'] for Barolo, ['AVA'] for Napa Valley."""
    c=n.split('/')[0]; out=[]
    for k in official or []:
        if c=='united-states' and k in ('PDO','PGI') and 'AVA' in official: continue
        if k=='PDO' and n in cats['docg']: out.append('DOCG')
        elif k=='PDO' and n in cats['doca']: out.append('DOCa')
        elif k=='PDO' and n in cats['pago']: out.append('Vino de Pago')
        elif k=='PDO' and n in cats.get('dac',[]): out.append('DAC')
        elif k=='PDO' and n in cats.get('anbaugebiet',[]): out.append('Anbaugebiet')   # one of Germany's 13 quality wine regions
        else: out.append(cats['by_country'].get(c,{}).get(k,k))
    return list(dict.fromkeys(out))
if __name__=='__main__': build()
