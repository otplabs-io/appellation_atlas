"""Figures with units inside place text, marked so the site and the app can show them in US or metric units.

Sentences come from many sources, some in feet and acres, some in meters and hectares. Each figure is found once
here, at build time, and replaced by a mark holding both wordings:

    ⟦kind|US wording|metric wording⟧

kind is temp, rain, elev (heights and short lengths), dist or area, the same kinds as the Units setting. The site
(unitText in web/atlas.js) and the app (Units.text in Units.swift) only pick one side, so the rules live here alone.

A converted figure keeps the precision of the source figure (its significant digits, at least two), so "about 920
feet" becomes "about 280 m", not "280.4 m". A figure already given in both units, like "18°F (−8°C)" or "163 acres,
about 66 ha", keeps the source's own two numbers. A temperature difference (a day-night swing, a gap) converts
without the 32° offset. Yields and densities (hl/ha, kg/ha, per ha) are figures set by law and are never touched.
"""
import re

FT, MI, IN, AC, SQMI = 0.3048, 1.609344, 25.4, 0.40468564, 2.589988

# unit words: (kind, system, factor to the metric unit, how the metric/US side writes the other unit)
UNITS = {
    'feet': ('elev', 'us', FT), 'foot': ('elev', 'us', FT), 'ft': ('elev', 'us', FT),
    'metres': ('elev', 'm', 1), 'meters': ('elev', 'm', 1), 'metre': ('elev', 'm', 1), 'meter': ('elev', 'm', 1), 'm': ('elev', 'm', 1),
    'miles': ('dist', 'us', MI), 'mile': ('dist', 'us', MI), 'km': ('dist', 'm', 1), 'kilometres': ('dist', 'm', 1), 'kilometers': ('dist', 'm', 1),
    'inches': ('rain', 'us', IN), 'inch': ('rain', 'us', IN), 'mm': ('rain', 'm', 1),
    'acres': ('area', 'us', AC), 'acre': ('area', 'us', AC), 'hectares': ('area', 'm', 1), 'hectare': ('area', 'm', 1), 'ha': ('area', 'm', 1),
    'square miles': ('sqarea', 'us', SQMI), 'sq km': ('sqarea', 'm', 1), 'km²': ('sqarea', 'm', 1), 'square kilometres': ('sqarea', 'm', 1), 'square kilometers': ('sqarea', 'm', 1),
    '°F': ('temp', 'us', None), '°C': ('temp', 'm', None), 'C': ('temp', 'm', None),
}
# the word each side uses when it is the converted one
OUT = {('elev', 'us'): 'feet', ('elev', 'm'): 'm', ('dist', 'us'): 'miles', ('dist', 'm'): 'km', ('rain', 'us'): 'inches', ('rain', 'm'): 'mm',
       ('area', 'us'): 'acres', ('area', 'm'): 'hectares', ('sqarea', 'us'): 'square miles', ('sqarea', 'm'): 'km²', ('temp', 'us'): '°F', ('temp', 'm'): '°C'}
ADJ = {('elev', 'us'): 'foot', ('elev', 'm'): 'meter'}   # "the 200 foot contour"
SPELL = {'metres': 'meters', 'metre': 'meter', 'kilometres': 'kilometers', 'square kilometres': 'square kilometers'}   # American spelling

NUM = r'(?:minus\s|[−-])?\d[\d,]*(?:\.\d+)?(?:\s(?:million|thousand))?'
UNIT = r'(?:°F|°C|square miles|square kilomet(?:re|er)s|sq km|km²|feet|foot|ft|metres?|meters?|m|miles?|km|kilomet(?:re|er)s|inches|inch|mm|acres?|hectares?|ha|C)'
JOIN = r'(?:\s?(?:to|and|-|–)\s?)'
FIG = re.compile(rf'(?<![\w.])(?P<a>{NUM})(?:(?P<j>{JOIN})(?P<b>{NUM}))?(?P<sp>\s?)(?P<u>{UNIT})(?![\w/²]|\.[A-Z])')
# a figure followed by the same figure in the other unit: "18°F (−8°C)", "113.67 acres (about 46 ha)", "163.09 acres, about 66 ha"
PAIR = re.compile(r'(?P<x>__F(?P<i>\d+)__)(?P<mid>\s\((?:about\s)?|,\s(?:about\s)?)(?P<y>__F(?P<k>\d+)__)(?P<end>\)?)')
HINT = re.compile(r'\d\s?(?:°[FC]|C\b|feet|foot|ft\b|metres?|meters?|m\b|miles?|km|kilomet|inch|mm\b|acres?|hectares?|ha\b|square|sq km)')   # a quick look before parsing a file
DELTA = re.compile(r'(swing|gap|difference|range between|drop)', re.I)


def _val(s):
    neg = s.startswith(('minus', '−', '-'))
    s = re.sub(r'^(minus\s|[−-])', '', s)
    mult = 1e6 if s.endswith('million') else 1e3 if s.endswith('thousand') else 1
    s = s.replace(' million', '').replace(' thousand', '')
    return (-1 if neg else 1) * float(s.replace(',', '')) * mult, mult


def _sig(s):
    d = re.sub(r'^(minus\s|[−-])', '', s).replace(' million', '').replace(' thousand', '').replace(',', '')
    if '.' in d: return len(d.replace('.', '').lstrip('0'))
    return len(d.lstrip('0').rstrip('0')) or 1


def _fmt(v, sig, mult, minus_word):
    """A converted figure: as many significant digits as the source gave, at least two and at most three, and no
    decimals at 10 or more. Under a million drops the "million"."""
    from math import floor, log10
    sig = min(3, max(2, sig))
    if mult > 1 and abs(v) < mult: mult = 1
    x = v / mult
    if x == 0: return '0'
    p = sig - 1 - floor(log10(abs(x)))
    if abs(x) >= 10: p = min(p, 0)
    r = round(x, p)
    dec = max(0, p)
    out = f'{abs(r):,.{dec}f}' if dec else f'{round(abs(r)):,}'
    out += {1e6: ' million', 1e3: ' thousand'}.get(mult, '')
    return (('minus ' if minus_word else '−') + out) if r < 0 else out


def _temp(s, to_us, delta, minus_word):
    v, _ = _val(s)
    dec = 1 if '.' in s else 0
    r = v * 9 / 5 + (0 if delta else 32) if to_us else (v - (0 if delta else 32)) * 5 / 9
    r = round(r, dec)
    out = f'{abs(r):.{dec}f}' if dec else f'{round(abs(r))}'
    return (('minus ' if minus_word else '−') + out) if r < 0 else out


def _side(m, text, to):
    """The figure written in the system `to` ('us' or 'm')."""
    u = m.group('u'); kind, sys_, f = UNITS[u]
    a, b, j = m.group('a'), m.group('b'), m.group('j') or ''
    adj = u == 'foot' or (u in ('meter', 'metre') and kind == 'elev')
    if sys_ == to:   # already in that system: the source's own words, in American spelling, °C for a bare C
        w = '°C' if u == 'C' else SPELL.get(u, u)
        sp = '' if w.startswith('°') else (m.group('sp') or ' ')
        return a + (j + b if b else '') + sp + w
    if kind == 'temp':
        delta = bool(DELTA.search(text[max(0, m.start() - 70):m.start()]))
        conv = lambda s: _temp(s, to == 'us', delta, s.startswith('minus'))
        return conv(a) + (j + conv(b) if b else '') + OUT[(kind, to)]
    k = f if to == 'm' else 1 / UNITS[OUT[(kind, 'us')]][2]
    conv = lambda s, extra=0: _fmt(_val(s)[0] * k, _sig(s) + extra, _val(s)[1], s.startswith('minus'))
    if b and conv(a) == conv(b):   # a range must not collapse: "3,300 to 3,400 m" is not "11,000 to 11,000 feet"
        c = lambda s: _fmt(_val(s)[0] * k, 3 + 1, _val(s)[1], s.startswith('minus'))
        return c(a) + j + c(b) + ' ' + OUT[(kind, to)]
    word = ADJ[(kind, to)] if adj and (kind, to) in ADJ else OUT[(kind, to)]
    if word in ('miles', 'inches', 'acres', 'feet', 'hectares') and not b and conv(a) in ('1', '1.0'):
        word = {'miles': 'mile', 'inches': 'inch', 'acres': 'acre', 'feet': 'foot', 'hectares': 'hectare'}[word]
    return conv(a) + (j + conv(b) if b else '') + ' ' + word


def mark(text):
    """The text with every figure that has a unit replaced by a mark holding both wordings."""
    if not isinstance(text, str) or not re.search(r'\d', text): return text
    figs = []

    def hold(m):
        u = m.group('u')
        if u == 'C' and not re.search(r'\d$', m.group('a') + (m.group('b') or '')): return m.group(0)
        kind = UNITS[u][0]
        figs.append((m, kind)); return f'__F{len(figs) - 1}__'

    held = FIG.sub(hold, text)
    if not figs: return text

    def both(i):
        m, kind = figs[i]
        return _side(m, text, 'us'), _side(m, text, 'm'), ('area' if kind == 'sqarea' else kind)

    def pair(p):   # the source gives both units: each side keeps the source's own number
        (mx, kx), (my, ky) = figs[int(p.group('i'))], figs[int(p.group('k'))]
        if kx != ky or UNITS[mx.group('u')][1] == UNITS[my.group('u')][1]: return p.group(0)
        us, m_ = (mx, my) if UNITS[mx.group('u')][1] == 'us' else (my, mx)
        kind = 'area' if kx == 'sqarea' else kx
        about = 'about ' if 'about' in p.group('mid') else ''   # "163 acres, about 66 ha": the about belongs to the second figure
        a_us, a_m = (about, '') if us is my else ('', about)
        return f'⟦{kind}|{a_us}{_side(us, text, "us")}|{a_m}{_side(m_, text, "m")}⟧'
    held = PAIR.sub(pair, held)

    def put(m):
        us, me, kind = both(int(m.group(1)))
        return f'⟦{kind}|{us}|{me}⟧'
    return re.sub(r'__F(\d+)__', put, held)


def mark_all(x, skip=('sources',)):
    if isinstance(x, str): return mark(x)
    if isinstance(x, list): return [mark_all(v, skip) for v in x]
    if isinstance(x, dict): return {k: (v if k in skip else mark_all(v, skip)) for k, v in x.items()}
    return x


def side(text, to):
    """One side of every mark, as the site and the app show it."""
    return re.sub(r'⟦(\w+)\|([^|⟧]*)\|([^⟧]*)⟧', lambda m: m.group(2) if to == 'us' else m.group(3), text)
