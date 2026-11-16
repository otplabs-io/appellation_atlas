"""Main and minor grapes for each French appellation, read from its cahier des charges (INAO, Licence Ouverte).

The EU dataset lists every allowed grape alike. A French cahier des charges sorts them: principal grapes make the
wine, complementary and accessory grapes may join in limited shares. This reads chapter V (Encepagement) of each
cahier and writes regions/inao-grapes.json, which src/atlas.py uses in place of the EU list for French places.

  python src/inao.py fetch    find each appellation's cahier on inao.gouv.fr and download it to data/cache/inao/
  python src/inao.py grapes   read the grapes and limits from the downloaded cahiers

Reading the PDFs uses pdftotext when it is installed, or macOS PDFKit through swift.
"""
import glob, hashlib, html, json, os, re, shutil, subprocess, sys, time, unicodedata, urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'data', 'cache', 'inao')
BASE = 'https://www.inao.gouv.fr'
MONTHS = {m: i + 1 for i, m in enumerate(['janvier', 'fevrier', 'mars', 'avril', 'mai', 'juin', 'juillet', 'aout', 'septembre', 'octobre', 'novembre', 'decembre'])}
TYPE = set('blanc blancs rouge rouges rose roses clairet ou et mousseux petillant nouveau primeur sec demi doux moelleux liquoreux vin vins de tranquille vendanges tardives selection grains nobles gris tuile ambre rancio hors d age'.split())
SKIN = {'n': 'red', 'b': 'white', 'g': 'pink', 'rs': 'pink', 'gr': 'pink', 'rg': 'pink'}


def fold(s):
    s = re.sub(r"[\u2018\u2019\u02bc\u00b4`]", "'", s)   # D’ANJOU and D'Anjou fold alike
    s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode().lower()
    return re.sub(r'[^a-z0-9]+', ' ', s).strip()


# ---------- fetch
_last = [0.0]
def get(url, binary=False):
    """One request a second, through curl."""
    wait = 1.0 - (time.time() - _last[0])
    if wait > 0: time.sleep(wait)
    for attempt in range(2):
        r = subprocess.run(['curl', '-sSL', '--fail', '--connect-timeout', '15', '--max-time', '90', url], capture_output=True)
        _last[0] = time.time()
        if r.returncode == 0: return r.stdout if binary else r.stdout.decode('utf-8', 'replace')
        err = RuntimeError(r.stderr.decode()[:200]); time.sleep(3 * (attempt + 1))
    raise err


def search(name, grapes):
    """Product pages whose title is the name, alone or followed only by colour, style or grape words."""
    want = fold(name); found = []
    for page in range(6):
        s = get(f'{BASE}/rechercher-un-produit?search_api_fulltext={urllib.parse.quote(name)}&page={page}')
        links = re.findall(r'href="(/produit/[^"]+)"[^>]*>(.*?)</a>', s, re.S)
        if not links: break
        for href, t in links:
            t = re.sub(r'\s+', ' ', re.sub('<[^>]+>', '', html.unescape(t))).strip(); ft = fold(t)
            rest = ft[len(want):].strip() if ft.startswith(want + ' ') else None
            if ft == want or (rest is not None and set(rest.split()) <= TYPE): found.append((0, len(ft), t, BASE + href))
            elif any(fold(a) == want or fold(a).startswith(want + ' ') and set(fold(a)[len(want):].split()) <= TYPE for a in re.split(r'\s+ou\s+', t)):
                found.append((0, len(ft), t, BASE + href))   # "Fleurie ou Fleurie cru du Beaujolais", "Moulis ou Moulis-en-Medoc"
            elif rest is not None and all(w in TYPE or w in grapes for w in rest.split()): found.append((1, len(ft), t, BASE + href))
        if found: break
    return [(x[2], x[3]) for x in sorted(found)]


def bodate(text):
    """The latest date a label gives, as yyyymmdd: an amended cahier names its newest change last."""
    best = 0
    for d, m, y in re.findall(r'(\d{1,2})(?:er)? ([a-z]+) (\d{4})', fold(text)):
        if m in MONTHS: best = max(best, int(y) * 10000 + MONTHS[m] * 100 + int(d))
    return best


SEEN = {}   # every cahier link met on any page, for appellations whose own page only points to Legifrance
def cahiers(url):
    """The cahier des charges PDFs a product page links to, newest first. Drafts put out for opposition (PNO) are left out."""
    s = get(url)
    links = [(html.unescape(h), re.sub(r'\s+', ' ', re.sub('<[^>]+>', '', html.unescape(t))).strip())
             for h, t in re.findall(r'<a [^>]*href="([^"]+)"[^>]*>(.*?)</a>', s, re.S)]
    pdfs = {h: (bodate(t), h, t) for h, t in links
            if ('agriculture.gouv.fr' in h and 'telechargement' in h and fold(t).startswith('cahier'))
            or (h.lower().endswith('.pdf') and '/fichier/' in h and not re.search(r'/fichier/pno', h, re.I))}
    for d, h, t in pdfs.values():
        if 'agriculture.gouv.fr' in h: SEEN[h] = t
    return sorted(pdfs.values(), reverse=True)


def download(rec, pdfs):
    """Every cahier a page links to. An appellation's newest-dated link is not always the bulletin that holds its own
    text, so all of them are kept and the reader picks. INAO's extranet is often out of reach; those are skipped on failure."""
    files = rec.setdefault('files', {})
    for date, url, label in pdfs:
        if url in files or url in rec.get('failed', []): continue
        fn = hashlib.sha1(url.encode()).hexdigest()[:16] + '.pdf'; path = os.path.join(OUT, 'pdf', fn)
        try:
            if not os.path.exists(path):
                data = get(url, binary=True)
                if not data.startswith(b'%PDF'): raise RuntimeError('not a PDF')
                open(path, 'wb').write(data)
            files[url] = fn
        except Exception:
            rec.setdefault('failed', []).append(url)
    return bool(files)


def fetch():
    os.makedirs(os.path.join(OUT, 'pdf'), exist_ok=True)
    grapes = {w for g in json.load(open(os.path.join(ROOT, 'regions', 'grape-synonyms.json'), encoding='utf-8')) for w in fold(g).split()}
    grapes -= {'de', 'du', 'la', 'le', 'grand', 'cru', 'premier', 'village', 'villages', 'cote', 'cotes'}
    places = {}
    for p in glob.glob(os.path.join(ROOT, 'public', 'facts', 'france__*.json')):
        if re.search(r' \d+\.json$', p): continue
        d = json.load(open(p, encoding='utf-8'))
        if d.get('rules'): places[d['id']] = [d['name']] + d.get('also', [])
    mp = os.path.join(OUT, 'map.json')
    M = json.load(open(mp, encoding='utf-8')) if os.path.exists(mp) else {}
    save = lambda: json.dump(M, open(mp, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    for pid, names in sorted(places.items()):
        rec = M.get(pid) or {}
        rec['names'] = names
        if 'cands' in rec and all(u in rec.get('files', {}) or u in rec.get('failed', []) for _, u, _ in rec['cands']): continue
        try:
            if not rec.get('product'):
                hits = []
                for n in names:
                    hits = search(n, grapes)
                    if hits: break
                if hits: rec['title'], rec['product'] = hits[0]
            if rec.get('product'):
                rec['cands'] = [list(c) for c in cahiers(rec['product'])]
                download(rec, rec['cands'])
            rec.pop('error', None)
        except Exception as e:
            rec['error'] = str(e)
        M[pid] = rec
        print(pid, '->', rec.get('title'), len(rec.get('files', {})), 'cahiers', rec.get('error', ''), flush=True)
        M['$seen'] = {**M.get('$seen', {}), **SEEN}
        save()
    # an appellation whose page links only Legifrance: its cahier is often in a bulletin another appellation's page links
    pool = M.get('$seen', {})
    for pid, names in sorted(places.items()):
        rec = M.get(pid, {})
        if rec.get('files'): continue
        want = [fold(n) for n in names]
        extra = [[bodate(t), h, t] for h, t in pool.items() if any(re.search(r'\b' + re.escape(w) + r'\b', fold(t)) for w in want)]
        if extra:
            rec['cands'] = rec.get('cands', []) + extra; rec['via'] = 'bulletins other appellations link'
            download(rec, extra); M[pid] = rec
            print(pid, '->', len(rec.get('files', {})), 'cahiers from other pages', flush=True)
    save()
    print(len(places), 'places,', sum(1 for k in places if M.get(k, {}).get('files')), 'with a cahier')


# ---------- read
SWIFT = '''import Foundation
import PDFKit
for a in CommandLine.arguments.dropFirst() {
    let u = URL(fileURLWithPath: a), o = u.deletingPathExtension().appendingPathExtension("txt")
    guard let d = PDFDocument(url: u) else { continue }
    var t = ""
    for i in 0..<d.pageCount { t += (d.page(at: i)?.string ?? "") + "\\n" }
    try? t.write(to: o, atomically: true, encoding: .utf8)
}
'''


def texts():
    """Text of every downloaded cahier, extracted once and kept beside the PDF."""
    todo = [p for p in glob.glob(os.path.join(OUT, 'pdf', '*.pdf')) if not os.path.exists(p[:-4] + '.txt')]
    if not todo: return
    if shutil.which('pdftotext'):
        for p in todo: subprocess.run(['pdftotext', '-layout', p, p[:-4] + '.txt'], check=False)
    else:
        sw = os.path.join(OUT, 'pdftext.swift'); open(sw, 'w').write(SWIFT)
        subprocess.run(['swift', sw] + todo, check=False)


HEAD = re.compile(r"cahier des charges (?:de l\W*appellation d\W*origine contr[oô]l[ée]e|des (?:\w+ )?appellations d\W*origine contr[oô]l[ée]es)\s*((?:[^«]{0,40}«\s*[^»\n]+?\s*»[\s,]*(?:ou|et)?\s*)+)", re.I)


def section(text, names):
    """The part of a bulletin that is this appellation's own cahier. Bulletins often carry several, and one cahier can
    cover several appellations (the Alsace grand crus, the Muscadets)."""
    heads = [(m.start(), [fold(x) for x in re.findall(r'«\s*([^»]+?)\s*»', m.group(1))]) for m in HEAD.finditer(text)]
    want = {fold(n) for n in names}
    def hit(ns):
        return any(n in want for n in ns) or any(n.endswith('grand cru') and any(w.startswith(n + ' ') for w in want) for n in ns)
    for i, (at, ns) in enumerate(heads):
        if hit(ns):
            # the same heading repeats on later pages of one cahier; run on to the next different appellation
            end = next((a for a, n in heads[i + 1:] if not set(n) & set(ns)), len(text))
            sec = text[at:end]
            # a title in a page footer comes after the first page it heads
            return text[:end] if i == 0 and not chapter(sec) else sec
    return text if not heads else None


def grape_list(s):
    """'pinot noir N, chardonnay B (melon) et pinot gris G' -> [['pinot noir', 'red'], ...]"""
    s = re.sub(r'\([^)]*\)', ' ', s)
    s = re.sub(r'«[^»]*»', ',', s)   # names in a table row: « Pouilly-Fumé » sauvignon B
    s = re.sub(r"(?:vari[ée]t[ée]s )?«?\s*d.int[ée]r[êe]t [àa] fin d.adaptation\s*»?", ' ', s, flags=re.I)
    out = []
    for part in re.split(r',|;|\bet\b|\bou\b', s):
        part = re.sub(r"^[^a-zà-ÿœæ]+", '', part.strip(), flags=re.I)
        part = re.sub(r'^.*\bc[ée]pages?\s+(?=\S+(?:\s+\S+){0,4}\s+(?:N|B|G|Rs|Gr|Rg)\b)', '', part, flags=re.I)   # 'a l exploitation La proportion des cepages gamay N'
        part = re.sub(r'^.*\bvins?\s+(?:tranquilles\s+|mousseux\s+)?(?:blancs?|rouges?|ros[ée]s?)(?:\s+et\s+ros[ée]s?)?\s+(?=\S+(?:\s+\S+){0,4}\s+(?:N|B|G|Rs|Gr|Rg)\b)', '', part, flags=re.I)   # a table cell: '... lieu-dit Vins blancs auxerrois B'
        m = re.match(r"(?:(?:sont|issus|le|la|les|du|de|des|d'un|l'ensemble|ensemble|chacun|seuls?|c[ée]pages?|vari[ée]t[ée]s?|suivantes|vins?|tranquilles|mousseux|accessoires?|compl[ée]mentaires?|principa(?:l|ux)|blancs?|rouges?|ros[ée]s?)\s+)*([a-zà-ÿœæ'][a-zà-ÿœæ' -]*?)\s+(N|B|G|Rs|Gr|Rg)\b", part, re.I)
        if m and len(m.group(1).split()) <= 6: out.append([m.group(1).strip(), SKIN[m.group(2).lower()]])
        elif re.fullmatch(r'(?:pinot gris|pinot beurot)\s*\.?', part.strip(), re.I): out.append(['pinot gris', 'pink'])   # listed without its colour code (Bourgogne mousseux)
    return out


ROMAN = r'\b[IVX]{1,4}\s*[.\-–—―−]*\s*[-–—―−]?\s*'   # − is U+2212, which some cahiers use as a dash
def chapter(sec):
    """The grapes chapter, as one line of text."""
    m = re.search(ROMAN + r'Enc[ée]pagement', sec, re.I)
    if not m: return None
    end = re.search(ROMAN + r'Conduite', sec[m.end():], re.I)
    body = sec[m.end(): m.end() + (end.start() if end else 6000)]
    body = re.sub(r'(\n\s*\d+\s*)?\nPublié au BO[^\n]*\n(\s*\d+\s*\n)?', '\n', body)   # page footers, numbered before or after
    body = re.sub(r'(\w)-\n(\w)', r'\1\2', body)   # words split at the end of a line
    return re.sub(r'\s+', ' ', body.replace('\u2019', "'").replace('\u2212', '-'))


NOT_A_PLACE = r"(?:mentions?|indications?|d[ée]nomm[ée]e? localement|appel[ée]e? localement)\s+(?:«[^»]*»\s*(?:,|ou|et)?\s*)+"
def named_in(c):
    """The appellations a clause or table row names: not the styles it names ('mention « ambré »') nor local grape names."""
    c = re.sub(NOT_A_PLACE, ' ', re.sub(r'\([^)]*\)', ' ', c), flags=re.I)
    named = {fold(x) for x in re.findall(r'«\s*([^»]+?)\s*»', c)} - {fold(x) for x in ('vendanges tardives', 'sélection de grains nobles')}
    return {n for n in named if len(n.split()) <= 8 and not n.startswith('d interet')}


def rows(c):
    """A grapes table read as text: a new row starts where an appellation's name follows a grape list."""
    clean = re.sub(NOT_A_PLACE, lambda m: ' ' * len(m.group(0)), re.sub(r'\([^)]*\)', lambda m: ' ' * len(m.group(0)), c), flags=re.I)
    cuts, last = [0], 0
    for m in re.finditer(r'(?:D[ée]nominations? g[ée]ographiques? compl[ée]mentaires?\s*)?«', clean):
        if m.start() > last and re.search(r'\b(?:N|B|G|Rs|Gr|Rg)\b', clean[last:m.start()]):
            cuts.append(m.start()); last = m.start()
        elif m.start() >= last: last = max(last, cuts[-1])
    out = [c[a:b] for a, b in zip(cuts, cuts[1:] + [len(c)])]
    # a row of a table carries no "cepages :" of its own; give it one so its grapes read as a list
    return [out[0]] + [r if ':' in r else 'Les vins sont issus des cépages suivants : ' + r for r in out[1:]]


def owner(row):
    """Whose row it is: the names after 'suivie d'une denomination ...', else all the names that head it."""
    head = re.split(r'\b(?:N|B|G|Rs|Gr|Rg)\b', re.sub(NOT_A_PLACE, ' ', re.sub(r'\([^)]*\)', ' ', row), flags=re.I), maxsplit=1)[0]
    tail = re.split(r'd[ée]nominations? g[ée]ographiques? compl[ée]mentaires?', head, flags=re.I)[-1]
    return named_in(tail) or named_in(row)


def clauses(text, names):
    """The lettered clauses, or table rows, that apply to this appellation. One that names other appellations is
    theirs; when some clause names this one, the general clauses give way to it."""
    parts = [r for c in re.split(r'(?:^|\s)(?=[a-h]\)\s*[-–]?)', text) for r in rows(c)]
    want = {fold(n) for n in names}
    own, general, others = [], [], False
    for c in parts:
        named = owner(c)
        if named & want: own.append(c)
        elif not named: general.append(c)
        else: others = True
    # a cahier that names only itself: its own clauses add to the general ones rather than replace them
    return (own, general) if others else ([], general + own)


RANK = {'main': 0, 'complementary': 1, 'accessory': 2, 'adaptation': 3}
def role_of(label):
    f = fold(label)
    if 'adaptation' in f or 'interet' in f: return 'adaptation'
    if 'accessoire' in f: return 'accessory'
    if 'complementaire' in f: return 'complementary'
    return 'main'


def lists(text):
    """Every grape list in the text, with the role its label gives it."""
    out, prev = [], (None, None)
    for m in re.finditer(r':', text):
        start = max(text.rfind(ch, 0, m.start()) for ch in '.;:')
        label = text[start + 1: m.start()]
        if not re.search(r'c[ée]pages?|vari[ée]t[ée]s?|\bvins?\b', label, re.I) and 'suivants' not in label: continue
        role = role_of(label)
        # "cepages accessoires : - cepages blancs : ..." the colour heading sits under the role heading
        if role == 'main' and not re.search(r'principa', label, re.I) and start >= 0 and text[start] == ':' and prev[0] == start: role = prev[1]
        prev = (m.start(), role)
        rest = re.sub(r'^[\s\-–]+', ' ', text[m.end():])
        stop = re.search(r';\s*(?=[-–]|[a-h]\)|$)|\.\s|\.$|\s[-–]\s|\s[a-h]\)\s*[-–]?|sous r[ée]serve|(?i:;?\s*(?=\bc[ée]pages?\s+(?:principa|compl[ée]mentaire|accessoire)|\bvari[ée]t[ée]s d.int[ée]r[êe]t))', rest)   # the next role's heading ends this list
        body = rest[:stop.start()] if stop else rest
        out += [(g, sk, role) for g, sk in grape_list(body)]
    for m in re.finditer(r"issus (?:exclusivement |uniquement )?(?:du|des) (?:seuls? )?c[ée]pages? (?!suivants)([^.;:]+)", text, re.I):
        out += [(g, sk, 'main') for g, sk in grape_list(m.group(1))]
    for m in re.finditer(r"et des vari[ée]t[ée]s (.+?) sous r[ée]serve", text, re.I):   # "- et des varietes alvarinho B ... sous reserve ... d'une convention"
        out += [(g, sk, 'adaptation') for g, sk in grape_list(m.group(1))]
    for m in re.finditer(r"peuvent comporter (?:les |le )?c[ée]pages? accessoires?\s*:?\s*([^.;]+?)(?:dans|\.|;|$)", text, re.I):
        out += [(g, sk, 'accessory') for g, sk in grape_list(m.group(1))]
    return out


NUM = r'(\d+(?:,\d+)?)\s*%'
WINE = [('red and rosé', r'rouges? et ros[ée]s?'), ('white', r'blancs?'), ('red', r'rouges?'), ('rosé', r'ros[ée]s?')]
def wine_of(clause):
    """'b) - Vins rouges :' -> 'red'"""
    m = re.match(r'\s*(?:[a-h]\)\s*)?[-–]?\s*(?:AOC\s*«[^»]+»\s*\(\s*)?(?:pour les )?vins? (?:(?:tranquilles|mousseux) )?(\w+(?: et \w+)?)', clause, re.I)
    return next((k for k, pat in WINE if m and re.match(pat, m.group(1), re.I)), None)


EXEMPT = re.compile(r"(?:Les dispositions suivantes|Ces dispositions|Cette obligation|Les r[èe]gles de proportion)[^.]*?ne s.appliqu\w* pas.*?(?=\s[a-h]\)\s|\.\s+[A-Z]|$)", re.I)
def limits(parts, role):
    """Share limits: (grapes or a role, each?, min, max), with the wine they apply to and whether only to blends."""
    out = []
    parts = [EXEMPT.sub(' ', c) for c in parts]   # the small-grower exemption and its own conditions ("- respecte une proportion ... 50 %") are not rules
    # a table of rules carries one row per colour: 'Vins blancs - La proportion ...'
    parts = [r for c in parts for r in re.split(r'\s(?=Vins (?:(?:tranquilles|mousseux) )?(?:blancs|ros[ée]s|rouges)(?: et ros[ée]s)?\s*[-–:]?\s*(?:-|La|Le|Les|L\x27)\b)|\s(?=AOC\s*«[^»]+»\s*\(\s*Vins)', c)]   # also "AOC « Languedoc » (Vins blancs) La proportion"
    for clause in parts:
        if re.search(r"ne s.appliqu\w* pas", clause, re.I) and re.match(r'\s*[a-h]\)\s*[-–]?\s*(?:A|À) l.exception', clause): continue
        wine = wine_of(clause)
        for x in _limits(clause):
            x['wine'] = wine
            x['blend'] = bool(re.search(r'plusieurs c[ée]pages|assemblage', clause, re.I))
            if x not in out: out.append(x)
    return out


def _limits(text):
    out, last = [], None
    # sentences, and the rules inside one: '..., la proportion ...' and '... 50 % - La proportion ...'
    for sen in re.split(r"(?<=[.;])\s+(?=[A-Z\-–]|[a-h]\))|,\s+(?=la proportion)|\s(?=[-–]\s*(?:La |Le |Les |L'))", text):
        m = re.search(r"c[ée]pages? (accessoires?|compl[ée]mentaires?)", sen, re.I)
        if m and not re.search(r'proportion|limit', sen, re.I): last = role_of(m.group(1))   # "Les cepages accessoires sont..." then "Leur proportion..."
        if not re.search(r'proportion|limit', sen, re.I) or not re.search(NUM, sen): continue
        if re.search(r"ne s.appliqu\w* pas|d[ée]rogation|exception|\blorsque\b|\bdans le cas\b|\ben cas de\b|\bsi le c[ée]page", sen, re.I): continue   # exemptions and conditional rules ("lorsque le cépage carignan N est présent")   # exemptions for small growers and the like
        f = unicodedata.normalize('NFKD', sen).encode('ascii', 'ignore').decode()
        who = re.search(r'proportion(.*?)(?:\best\b|\bne\s+(?:peut|doit)|\bdoit\b|$)', f, re.I)
        who = who.group(1) if who else ''
        named = [fold(g) for g, _ in grape_list(who)]
        if not named and re.search(r'le plus important', who, re.I): named, grp = [], 'single'   # 'the largest grape'
        else: grp = None
        grp = grp if grp or named else next((k for k in ('adaptation', 'accessory', 'complementary', 'main') if role_of(who) == k and k != 'main'), None)
        if not named and not grp and re.search(r'principa', who, re.I): grp = 'main'
        if not named and not grp:
            m = re.search(r"c[ée]pages? (accessoires?|compl[ée]mentaires?|principaux)[^.]{0,120}?(?:dans la limite|dans une proportion maximale)", sen, re.I)
            if m: grp = role_of(m.group(1))
            elif re.match(r'\s*Leur', sen) and last: grp = last
            else: continue
        lo = hi = None
        m = re.search(r'comprise? entre\s+(\d+(?:,\d+)?)\s*%?\s+et\s+' + NUM, f, re.I)
        if m: lo, hi = m.group(1), m.group(2)
        elif re.search(r'\bne\s+(?:peut|doit)', f, re.I):
            m = re.search(r'inferieure?\s+a\s+' + NUM, f, re.I); lo = m and m.group(1)
            m = re.search(r'superieure?\s+a\s+' + NUM, f, re.I); hi = m and m.group(1)
        else:
            m = re.search(r'(?:inferieure ou egale a|inferieure a|limitee? a|maximale? de|au plus|n.exce?de pas)\s+' + NUM, f, re.I); hi = m and m.group(1)
            m = re.search(r'(?:superieure ou egale a|superieure a|au moins|minimale? de)\s+' + NUM, f, re.I); lo = m and m.group(1)
        if lo is None and hi is None: continue
        num = lambda v: float(v.replace(',', '.')) if v else None
        x = dict(grapes=named, role=grp, each=bool(re.search(r'chacun', sen, re.I)), min=num(lo), max=num(hi))
        if x not in out: out.append(x)
        last = grp or last
    return out


def white_only(sec, names):
    """Whether chapter III keeps this appellation to white wine, as Alsace grand cru does for all but three."""
    m = re.search(r'Types? de produits?(.{0,1500}?)' + ROMAN + r'Aires?', sec, re.I | re.S)
    if not m: return False
    want = {fold(n) for n in names}
    for sen in re.split(r'(?<=\.)\s+', re.sub(r'\s+', ' ', m.group(1))):
        if not re.search(r'r[ée]serv[ée]e?s? aux vins blancs(?! et)', sen, re.I): continue
        named = {fold(x) for x in re.findall(r'«\s*([^»]+?)\s*»', sen)}
        if re.search(r"exception", sen, re.I): return not (named & want)
        return not named or bool(named & want)
    return False


COLOUR_ROW = r'Vins? (?:tranquilles |(mousseux) )?((?:rouges?|ros[ée]s?|blancs?)(?: et (?:rouges?|ros[ée]s?|blancs?))?)(?:\s+(?:tranquilles|secs?|(mousseux)))?\s*\)?\s*(?:[-–:]|(?=\s*[-–]?\s*c[ée]pages?))'   # also "Vins blancs tranquilles :"   # also "AOC « Languedoc » (Vins blancs) - cépages"
MENTION_ROW = r'AOC\s*«\s*([^»]+?)\s*»(?:\s+suivie de la mention\s*«\s*([^»]+?)\s*»)?'
def versions(text):
    """The rows of a grapes table that give each wine its own roles: one per colour (Malepère: Merlot leads the red, Cabernet
    Franc the rosé) or per mention (Pacherenc: Petit Manseng alone leads the sweet wine, three grapes the sec). [(label, text)]"""
    marks = [(m.start(), next((('sparkling ' if (m.group(1) or m.group(3)) else '') + k for k, pat in WINE if re.match(pat, m.group(2), re.I)), None)) for m in re.finditer(COLOUR_ROW, text, re.I)]
    if len(marks) < 2:
        marks = [(m.start(), (m.group(1) + (' ' + m.group(2) if m.group(2) else ''))) for m in re.finditer(MENTION_ROW, text)]
    marks = [(a, l) for a, l in marks if l]
    if len(marks) < 2: return []
    segs = [(l, text[a:b]) for (a, l), (b, _) in zip(marks, marks[1:] + [(len(text), None)])]
    first = {}
    for l, t in segs: first.setdefault(l, t)   # the appellation's own rows come first; the same colours repeat for its sub-names (Languedoc Pézenas)
    return list(first.items()) if len(first) >= 2 else []


def parse(ch, names, sec=''):
    """Grapes by role, for all the appellation's wines together, and the share limits the cahier sets."""
    split = re.split(r'2\s*°\s*[-–]?\s*R[èe]gles? de proportion', ch, maxsplit=1)
    head, props = split[0], (split[1] if len(split) > 1 else '')
    if white_only(sec, names): head = re.sub(r'pour les vins rouges\s*:[^;.]*?(?=\s[a-h]\)|[;.]|$)', ' ', head, flags=re.I)
    own, general = clauses(head, names)
    role, members = {}, {}
    for g, sk, r in lists(' '.join(own or general)):
        k = fold(g) + ('' if sk == 'red' or re.search(r'\b(blanc|gris|rose|noir)\b', fold(g)) else ' ' + {'white': 'blanc', 'pink': 'gris'}[sk])   # Grenache N and Grenache B are two grapes
        k = k if any(fold(x) == fold(g) and y != sk for x, y, _ in lists(' '.join(own or general))) else fold(g)
        members.setdefault(r, [])
        if k not in members[r]: members[r].append(k)
        if k not in role or RANK[r] < RANK[role[k][2]]: role[k] = [g, sk, r]
    pown, pgen = clauses(props, names)
    lim = limits(pgen + pown, role)
    lim += [x for x in limits(own or general, role) if x not in lim]
    by = []   # roles per wine, kept only where they differ from one wine to the next
    for label, t in versions(' '.join(own or general)):
        r = {}
        for g, sk, rl in lists(t):
            if fold(g) not in r or RANK[rl] < RANK[r[fold(g)][2]]: r[fold(g)] = [g, sk, rl]
        if r: by.append([label, list(r.values())])
    if len(by) < 2 or all(sorted(map(tuple, b[1])) == sorted(map(tuple, by[0][1])) for b in by): by = []
    seen_roles = {}
    for g, sk, rl in lists(' '.join(own or general)): seen_roles.setdefault(fold(g), set()).add('main' if rl == 'main' else 'other')
    mixed = not by and any(len(v) > 1 for v in seen_roles.values())   # main in one wine, minor in another (Saumur's Cabernet Sauvignon), rows not separated
    return role, lim, members, (by or ('mixed' if mixed else []))



# ---------- base yields, wine types and recognition year, from the same cahier
_W = lambda s: re.sub(r'\s+', ' ', s)
COL = r'(?:blancs?|rouges?|ros[ée]s?|gris|clairets?)'
COLEN = {'blanc': 'white', 'rouge': 'red', 'rose': 'rosé', 'gris': 'gris', 'clairet': 'clairet'}
def _part(s, a, b, n=1500):
    m = re.search(a, s, re.I)
    if not m: return None
    e = re.search(b, s[m.end():], re.I)
    return s[m.end():m.end() + (e.start() if e else n)]
def _colours(t):
    return [COLEN[fold(c) if fold(c) in COLEN else fold(c)[:-1]] for c in re.findall(COL, t, re.I)]
def base_yield(sec):
    """Chapter VIII's rendement (the yield the rules set), not the rendement butoir (the ceiling some years allow):
    [[colour or '', value, unit], ...]. Per colour when the cahier gives a table."""
    y = _part(sec, r'VIII\.?\s*[-–―]?\s*Rendements?.{0,80}?1°\s*[-–―]?\s*Rendements?\b', r'2°\s*[-–―]?\s*Rendement butoir|2°|\bIX\.?\s*[-–―]', 900)
    if not y: return None
    unit = 'kg/ha' if re.search(r'kilogramme', y, re.I) else 'hl/ha'
    num = lambda v: float(v.replace(' ', '').replace('\u00a0', '').replace(',', '.'))
    both = bool(re.search(r'rendement butoir\s*\(', y, re.I))   # one table with the rendement and the butoir side by side: "Vins blancs 68 75"
    out, seen = [], set()
    for v, kind in re.findall(r'(\d+(?:[.,]\d+)?)\s*hectolitres par hectare pour les vins ((?:tranquilles|mousseux|' + COL[3:-1] + r')(?:\s+(?:secs|avec sucres r[ée]siduels|moelleux|liquoreux|doux))?)', y, re.I):
        k = fold(kind); lab = 'still' if k.startswith('tranquille') else 'sparkling' if k.startswith('mousseux') else (_colours(kind) or [''])[0]
        lab = ('dry ' if ' sec' in k else 'sweet ' if re.search(r'sucres|moelleux|liquoreux|doux', k) else '') + lab   # Graves: dry white 58, sweet white 40
        if lab not in seen: seen.add(lab); out.append([lab, num(v), unit])
    for cols, v in re.findall(r'pour les vins (' + COL + r'(?:\s*(?:,|et|ou)\s*' + COL + r')*)\b[^.]{0,140}?à\s*(\d+(?:[.,]\d+)?)\s*hectolitres', y, re.I):
        cs = [c for c in _colours(cols) if c not in seen]
        if cs: seen.update(cs); out.append([' and '.join(cs), num(v), unit])
    rows = r'Vins? (?:tranquilles )?(' + COL + r'(?:\s*(?:,|et|ou)\s*' + COL + r')*)(?:\s*\((secs?|autres?|moelleux|doux|liquoreux)\))?\s*\)?\s*:?\s*(\d+(?:[.,]\d+)?)' + (r'\s+\d+' if both else r'\b')
    for cols, q, v in re.findall(rows, y, re.I):   # the first row for each colour is the appellation's own; later rows are its mentions (supérieur, Villages)
        pre = {'sec': 'dry ', 'secs': 'dry ', 'autre': 'other ', 'autres': 'other '}.get(fold(q), 'sweet ' if q else '')   # Graves de Vayres: "Vins blancs (secs) 55", "(autres) 50"
        cs = [pre + c for c in _colours(cols) if pre + c not in seen]
        if cs: seen.update(cs); out.append([' and '.join(cs), num(v), unit])
    if both:
        if out: return out
        m = re.search(r'(?:»|\))\s*(\d+(?:[.,]\d+)?)\s+\d', y)
        return [['', num(m.group(1)), unit]] if m else None
    if out: return out
    m = re.search(r'fix[ée]s?\b[^.]{0,120}?à\s*:?\s*(\d{1,3}(?:[ \u00a0]\d{3})*(?:[.,]\d+)?)\s*(?:hectolitres|kilogrammes)', y, re.I)
    return [['', num(m.group(1)), unit]] if m else None
KIND = [(r'mousseux', 'Sparkling {}'), (r'p[ée]tillants?', 'Lightly sparkling {}'), (r'doux naturels?', 'Vin doux naturel ({})'), (r'de liqueur', 'Vin de liqueur ({})')]
STILL = {'white': 'White wine', 'red': 'Red wine', 'rosé': 'Rosé wine', 'gris': 'Gris (pale rosé)', 'clairet': 'Clairet'}
def sweet(sec):
    """Whether every wine must keep residual sugar: Barsac's 45 g/l of fermentable sugars makes it a sweet wine, though chapter I says white."""
    m = re.search(r'(?:Les vins (?:blancs )?(?:pr[ée]sentent|ont)|doivent pr[ée]senter|Tout lot de vin[^.]{0,60}?pr[ée]sente)\b[^.]{0,100}?sucres fermentescibles[^.]{0,120}?(?:sup[ée]rieure? ou [ée]gale? [àa]|au moins|minimale? de)\s*(\d+)\s*g', sec, re.I)   # a requirement, not "les vins présentant ..." (Condrieu)
    return bool(m) and int(m.group(1)) >= 45 and not re.search(r'vins? (?:blancs? )?secs?\b', sec[:6000], re.I)
def wine_types(sec):
    """Chapter I's colours and types: "réservée aux vins tranquilles rouges et rosés" is ['Red wine', 'Rosé wine']."""
    t = _part(sec, r'(?:III|II)\.?\s*[-–―]?\s*Couleurs? et types? de produits?', r'\bIV\.?\s*[-–―]|\bIII\.?\s*[-–―]', 600)
    if not t: return None
    out = []
    for pre, cols, post in re.findall(r'vins?\s+((?:tranquilles|mousseux|p[ée]tillants?|doux naturels|de liqueur)\s+)?(' + COL + r'(?:\s*(?:,|et|ou)\s*' + COL + r')*)(\s+(?:tranquilles|mousseux|p[ée]tillants?|doux naturels))?', t, re.I):
        k = (pre + ' ' + post).lower()
        for c in _colours(cols):
            f = next((f for pat, f in KIND if re.search(pat, k)), None)
            out.append(f.format(c) if f else STILL[c])
    return list(dict.fromkeys(out)) or None
def recognised(sec, names=(), own_only=False):
    """The year the appellation was first recognised, when the cahier says ("initialement reconnue par le décret du 2 mai 2007"), or,
    in a cahier shared by several (Alsace's grands crus), the year it gives for this one ("« Alsace grand cru Brand » est reconnue en 1983")."""
    for n in names:
        m = re.search(r'«\s*' + re.escape(n) + r'\s*»\s*(?:a été|est)\s+reconnue\s+en\s+(\d{4})', sec, re.I)
        if m: return int(m.group(1))
    if own_only: return None
    m = re.search(r'reconnue?s?\s+(?:en\s+appellation\s+d.origine\s+contr[ôo]l[ée]e\s+)?par\s+(?:le\s+)?d[ée]cret\s+du\s+(?:\d{1,2}|1er)\s+\w+\s+(\d{4})', sec[:4000], re.I)
    return int(m.group(1)) if m else None

def grapes():
    texts()
    M = json.load(open(os.path.join(OUT, 'map.json'), encoding='utf-8'))
    out, miss = {}, {}
    FILES = {r['files'][u]: (d, u, l) for r in M.values() if isinstance(r, dict) for d, u, l in r.get('cands', []) if r.get('files', {}).get(u)}
    cache = {}
    TEXT = lambda tp: cache.get(tp) or cache.setdefault(tp, fold(open(tp, encoding='utf-8').read()))
    hcache = {}
    def HEADS(fn):   # the appellations a cached cahier's headings name
        if fn not in hcache:
            tp = os.path.join(OUT, 'pdf', fn[:-4] + '.txt')
            t = open(tp, encoding='utf-8').read() if os.path.exists(tp) else ''
            hcache[fn] = {fold(x) for m in HEAD.finditer(t) for x in re.findall(r'«\s*([^»]+?)\s*»', m.group(1))}
        return hcache[fn]
    for pid, r in sorted(M.items()):
        if pid.startswith('$'): continue
        names = r['names'] + [a for a in re.split(r'\s+ou\s+', r.get('title', '')) if a]
        names += [re.sub(r'(\s+(' + '|'.join(TYPE) + r'))+$', '', n, flags=re.I) for n in names]
        found = []
        for d, url, label in r.get('cands', []):
            fn = r.get('files', {}).get(url); tp = fn and os.path.join(OUT, 'pdf', fn[:-4] + '.txt')
            if not tp or not os.path.exists(tp): continue
            text = unicodedata.normalize('NFC', open(tp, encoding='utf-8').read())
            sec = section(text, names)
            if sec is None or not chapter(sec): continue
            found.append((max(d, bodate(sec[:400])), url, label, sec))
        if not found:   # INAO sometimes links the wrong bulletin; look in every bulletin the other pages link
            for fn, (d, url, label) in FILES.items():
                tp = os.path.join(OUT, 'pdf', fn[:-4] + '.txt')
                if not os.path.exists(tp) or not any(fold(n) in TEXT(tp) for n in names): continue
                text = unicodedata.normalize('NFC', open(tp, encoding='utf-8').read())
                sec = section(text, names)
                if sec is not None and len(sec) < len(text) and chapter(sec): found.append((max(d, bodate(sec[:400])), url, label, sec))
        want = {fold(n) for n in names}; best = max((x[0] for x in found), default=0)
        for fn, (d, url, label) in FILES.items():   # a newer cahier whose heading names this one, though its own page does not link it (Rosé d'Anjou in the 2026 Anjou cahier)
            if d <= best or not (HEADS(fn) & want) or any(url == x[1] for x in found): continue
            tp = os.path.join(OUT, 'pdf', fn[:-4] + '.txt'); text = unicodedata.normalize('NFC', open(tp, encoding='utf-8').read())
            sec = section(text, names)
            if sec is not None and chapter(sec): found.append((max(d, bodate(sec[:400])), url, label, sec))
        if not found: miss[pid] = 'its own text is in none of the cahiers' if r.get('files') else (r.get('error') or 'no cahier'); continue
        date, url, label, sec = max(found, key=lambda x: x[0])
        r = dict(r, date=date, url=url, label=label)
        ch = chapter(sec)
        if not ch: miss[pid] = 'no grape chapter'; continue
        role, limits, members, by_wine = parse(ch, names, sec)
        if not role: miss[pid] = 'no grapes read'; continue
        ws = _W(sec)
        hd = HEAD.search(sec[:1500]); hn = [fold(x) for x in re.findall(r'«\s*([^»]+?)\s*»', hd.group(1))] if hd else []
        seps = re.findall(r'»\s*(.*?)\s*«', hd.group(1)) if hd else []   # « Pouilly-Fumé » ou « Blanc Fumé de Pouilly » is one appellation by two names
        shared = len(hn) > 1 and any(not re.fullmatch(r'ou', x.strip(' ,'), re.I) for x in seps)   # one cahier for several (Anjou, Cabernet d'Anjou, Rosé d'Anjou): take only what names this one
        mixed = by_wine == 'mixed'; by_wine = [] if mixed else by_wine
        out[pid] = dict(grapes=list(role.values()), members=members, limits=limits, by_wine=by_wine, mixed_roles=mixed, date=r.get('date'), url=r['url'], label=r.get('label'),
                        base_yield=None if shared else base_yield(ws), types=None if shared else [('Sweet white wine' if t == 'White wine' and sweet(ws) else t) for t in (wine_types(ws) or [])] or None,
                        recognised=recognised(ws, names) if not shared else recognised(ws, names, own_only=True))
    meta = dict(source="INAO, cahiers des charges des appellations d'origine contrôlées, as published in the Bulletin officiel du ministère de l'Agriculture (Licence Ouverte)",
                url='https://www.inao.gouv.fr/rechercher-un-produit')
    json.dump({'$about': __doc__.split('\n')[0], **meta, 'missing': miss, 'places': out},
              open(os.path.join(ROOT, 'regions', 'inao-grapes.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
    print(len(out), 'appellations read,', len(miss), 'missed')
    for k, v in sorted(miss.items()): print('  ', k, v)


if __name__ == '__main__':
    {'fetch': fetch, 'grapes': grapes}[sys.argv[1]]()
