#!/usr/bin/env python3
"""Cahiers des charges from the ministry's Bulletin officiel (BO-agri) for the French appellations whose INAO page links only
INAO's extranet (often out of reach) or Légifrance. Searches BO-agri by name, opens each "Cahier des charges" result, and
keeps the newest whose subject names the appellation. Adds them to data/cache/inao/map.json for src/inao.py grapes.
Usage: python src/inao_bo.py     (one request a second)"""
import html, json, os, re, sys, urllib.parse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inao
BO = 'https://info.agriculture.gouv.fr/boagri'
def text(s): return re.sub(r'\s+', ' ', html.unescape(re.sub('<[^>]+>', ' ', re.sub(r'<script.*?</script>|<style.*?</style>', '', s, flags=re.S))))
def results(name):
    s = inao.get(f'{BO}/recherche/resultat_recherche_rapide?' + urllib.parse.urlencode({'titre': name}))
    return list(dict.fromkeys(h for h, t in re.findall(r'<a[^>]*href="([^"]*document_administratif-[0-9a-f-]+)"[^>]*>(.*?)</a>', s, re.S)
                              if 'cahier des charges' in inao.fold(text(t))))
def doc(url):
    t = text(inao.get(url))
    m = re.search(r'Cahier des charges du (\d\d)-(\d\d)-(\d{4})', t); d = int(m.group(3) + m.group(2) + m.group(1)) if m else 0
    obj = re.search(r'OBJET\s*:\s*(.*?)(?:\(\s*Télécharger|REFERENCE EXTERNE)', t)
    return d, (obj.group(1).strip() if obj else ''), ('abrogé par' in t and "n'est abrogé par aucun" not in t)
def main():
    M = json.load(open(os.path.join(inao.OUT, 'map.json'), encoding='utf-8'))
    miss = json.load(open(os.path.join(inao.ROOT, 'regions', 'inao-grapes.json'), encoding='utf-8'))['missing']
    for pid in sorted(miss):
        rec = M.get(pid, {}); names = rec.get('names') or []
        if any('BO-agri' in str(c[2]) for c in rec.get('cands', [])) and rec.get('files'): continue   # found already; the reader is what misses it
        want = {inao.fold(n) for n in names}
        best = None
        for n in names:
            try: hits = results(n)
            except Exception as e: print(pid, 'search failed', e); continue
            for url in hits[:20]:
                try: d, obj, gone = doc(url)
                except Exception: continue
                named = {inao.fold(x) for x in re.findall(r'«\s*([^»]+?)\s*»', obj)}
                if gone or not (named & want): continue
                if not best or d > best[0]: best = (d, url + '/telechargement', 'BO-agri: ' + obj)
            if best: break
        if best:
            rec.setdefault('cands', []); rec['cands'] = [c for c in rec['cands'] if c[1] != best[1]] + [list(best)]
            rec['via'] = 'BO-agri search'
            inao.download(rec, [best])
        M[pid] = rec
        print(pid, '->', best and best[2][:90], '| file' if best and best[1] in rec.get('files', {}) else '', flush=True)
        json.dump(M, open(os.path.join(inao.OUT, 'map.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
if __name__ == '__main__': main()
