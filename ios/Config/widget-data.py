#!/usr/bin/env python3
"""The places the widget can show, as a small file inside the widget: every Benchmark region with a climate reading,
with the few facts a widget has room for. Built from ../public, the same data as the app and the website."""
import glob,json,os,sys
src,dst=sys.argv[1],sys.argv[2]
P=json.load(open(os.path.join(src,'places.json'),encoding='utf-8'))['places']
out=[]
for f in sorted(glob.glob(os.path.join(src,'facts','*.json'))):
    if os.path.basename(f)[-7:-5].strip().isdigit() and ' ' in os.path.basename(f): continue   # iCloud conflict copies
    d=json.load(open(f,encoding='utf-8'))
    p=P.get(d['id'])
    if not p or not p[6] or not d.get('climate') or d.get('depth',0)<1: continue
    c=d['climate']; pl=d.get('planted') or {}
    grape=pl['grapes'][0][0] if pl.get('scope') in ('own','within') and pl.get('grapes') and pl['grapes'][0][0]!='Other' else None
    if not grape and d.get('rules') and d['rules'].get('grapes'): grape=d['rules']['grapes'][0][0]
    kind=(d.get('kind') or ['Region'])[0]
    out.append(dict(id=d['id'],name=d['name'],where=', '.join(x for x in [d['chain'][-1][1] if d.get('chain') else '',d.get('country','')] if x and x!=d['name']),
                    kind=kind,climate=(c.get('gst_class') or '').capitalize(),gst=round(c['gst']*9/5+32) if c.get('gst') is not None else None,grape=grape))
os.makedirs(os.path.dirname(dst),exist_ok=True)
json.dump(out,open(dst,'w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
print(f'widget: {len(out)} places')
