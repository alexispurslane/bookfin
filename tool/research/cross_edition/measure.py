# Tool code for the boo-z3is design measurement, not part of Bookfin.
# Matches LibriVox sections to EPUB contents entries and measures where
# proportional placement lands. Usage:
#   measure.py <corpus books dir> <librivox dir> <corpus results.json> <rows.json>
import json, math, os, pathlib, re, statistics, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import epub_map

BOOKS = pathlib.Path(sys.argv[1])
LIBRIVOX = pathlib.Path(sys.argv[2])
RESULTS = json.loads(pathlib.Path(sys.argv[3]).read_text())['books']
ROWS = pathlib.Path(sys.argv[4])
PAIRS = {
  'moby-dick': ['se-moby-dick', 'pg-2701-moby-dick'],
  'pride-and-prejudice': ['se-pride-and-prejudice'],
  'frankenstein': ['se-frankenstein', 'pg-84-frankenstein'],
  'alice': ['se-alices-adventures-in-wonderland', 'pg-11-alice'],
  'christmas-carol': ['pg-46-christmas-carol'],
  'sherlock-holmes': ['se-the-adventures-of-sherlock-holmes'],
  'tale-of-two-cities': ['se-a-tale-of-two-cities'],
  'emma': ['se-emma'],
  'jane-eyre': ['se-jane-eyre', 'pg-1260-jane-eyre'],
  'wuthering-heights': ['se-wuthering-heights'],
  'huckleberry-finn': ['se-the-adventures-of-huckleberry-finn', 'pg-76-huckleberry-finn'],
  'time-machine': ['se-the-time-machine'],
  'dracula': ['se-dracula', 'pg-345-dracula'],
  'heart-of-darkness': ['se-heart-of-darkness'],
  'treasure-island': ['se-treasure-island'],
  'great-gatsby': ['se-the-great-gatsby'],
  'wind-in-the-willows': ['se-the-wind-in-the-willows', 'pg-289-wind-in-the-willows'],
  'jungle-book': ['se-the-jungle-book', 'pg-236-jungle-book'],
  'walden': ['se-walden', 'pg-205-walden'],
  'war-of-the-worlds': ['se-the-war-of-the-worlds'],
  'dorian-gray': ['pg-174-dorian-gray'],
  'peter-pan': ['pg-16-peter-pan'],
  'wizard-of-oz': ['pg-55-wizard-of-oz'],
  'looking-glass': ['pg-12-through-the-looking-glass'],
  'metamorphosis': ['pg-5200-metamorphosis'],
  'crime-and-punishment': ['se-crime-and-punishment'],
  'mrs-dalloway': ['se-mrs-dalloway'],
  'origin-of-species': ['se-the-origin-of-species', 'pg-1228-origin-of-species'],
  'bleak-house': ['se-bleak-house'],
}
LABELS = {'chapter', 'chapters', 'chap', 'ch', 'letter', 'letters', 'stave', 'staves', 'book',
          'part', 'parts', 'volume', 'vol', 'section', 'sections', 'adventure', 'canto', 'no', 'number'}
STOP = {'the', 'a', 'an', 'of', 'and', 'in', 'to', 'on', 'at', 'for', 'with', 'from', 'by', 'or',
        'is', 'it', 'his', 'her', 'their', 'its', 'as', 'into', 'that', 'which', 'what', 'who'}
UNITS = 'zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen'.split()
TENS = {'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90}
ORD = {'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5, 'sixth': 6, 'seventh': 7, 'eighth': 8,
       'ninth': 9, 'tenth': 10, 'eleventh': 11, 'twelfth': 12}
ROMAN = re.compile(r'^(?=[mdclxvi]+$)m{0,4}(cm|cd|d?c{0,3})(xc|xl|l?x{0,3})(ix|iv|v?i{0,3})$')

def roman(s):
    values = {'i': 1, 'v': 5, 'x': 10, 'l': 50, 'c': 100, 'd': 500, 'm': 1000}
    total = 0
    for i, ch in enumerate(s):
        v = values[ch]
        total += -v if i + 1 < len(s) and values[s[i + 1]] > v else v
    return total

def parse(title):
    """The numbers and the content words of a title."""
    t = title.lower().replace('’', "'")
    t = re.sub(r'(\d)\s*[-–—]\s*(\d)', r'\1~\2', t)
    t = re.sub(r'\b(\d+)\s+to\s+(\d+)\b', r'\1~\2', t)
    t = re.sub(r'\b(\d+)\s*(?:&|and)\s*(\d+)\b', r'\1~\2', t)
    tokens = re.findall(r"[a-z0-9~']+", t)
    numbers, words, after_label = [], set(), False
    labels, label = [], None
    i = 0
    while i < len(tokens):
        tok = tokens[i].strip("'")
        if tok in LABELS:
            after_label = True; label = tok; i += 1; continue
        count = len(numbers)
        if re.fullmatch(r'\d+~\d+', tok):
            a, b = map(int, tok.split('~')); numbers.append((a, b)); after_label = False; i += 1; continue
        if tok.isdigit():
            numbers.append((int(tok), int(tok))); after_label = False; i += 1; continue
        if ROMAN.match(tok) and tok and (after_label or i == 0) and not (tok == 'i' and not after_label and len(tokens) > 1 and i + 1 < len(tokens) and tokens[i + 1] not in ('',)) :
            n = roman(tok); numbers.append((n, n)); after_label = False; i += 1; continue
        if after_label and (tok in UNITS or tok in TENS or tok in ORD):
            n = ORD.get(tok) or (UNITS.index(tok) if tok in UNITS else TENS[tok])
            if tok in TENS and i + 1 < len(tokens) and tokens[i + 1] in UNITS:
                n += UNITS.index(tokens[i + 1]); i += 1
            numbers.append((n, n)); after_label = False; i += 1; continue
        after_label = False
        if tok not in STOP and len(tok) > 1: words.add(tok)
        i += 1
    return numbers, words

_parse = parse
CHAPTER = {'chapter', 'chapters', 'chap', 'ch', 'stave', 'staves', 'letter', 'letters', 'adventure'}
def parse(title):
    # The chapter's number: the one after a chapter label when the title has
    # one, so that "Chapter 1, Part 2" is chapter 1; else the last number,
    # so that "Volume 2, Chapter 3" is 3 and "Book 1 Ch 4" is 4.
    t = title.lower()
    numbers, words = _parse(title)
    m = re.search(r'\b(chapters?|chap|ch|staves?|letters?|adventure)\b\.?\s*([0-9~]+|[ivxlcdm]+\b)', re.sub(r'(\d)\s*(?:[-–—&]|and|to)\s*(\d)', r'\1~\2', t))
    if m and numbers:
        token = m.group(2)
        if '~' in token: a, b = map(int, token.split('~')); primary = (a, b)
        elif token.isdigit(): primary = (int(token), int(token))
        else: primary = (roman(token), roman(token)) if ROMAN.match(token) else numbers[-1]
        return [primary], words
    return ([numbers[-1]] if numbers else []), words

def score(a, t):
    (an, aw), (tn, tw) = a, t
    s = 0.0
    if an and tn:
        lo, hi = an[-1]
        if tn[-1][0] == lo: s += 2
        elif lo <= tn[-1][0] <= hi: s += 1
        else: s -= 1
    if aw and tw:
        j = len(aw & tw) / len(aw | tw)
        if j >= 0.5: s += 2
        elif j >= 0.34: s += 1
    return s

def chain(audio, text, starts, total_t, total_c):
    """The monotone matching of audio sections to text entries with the most
    total score; only pairs that score 2 or more count."""
    pa = [parse(s['title']) for s in audio]
    pt = [parse(e['title']) for e in text]
    n, m = len(audio), len(text)
    best = [[0.0] * (m + 1) for _ in range(n + 1)]
    move = [[None] * (m + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            options = [(best[i + 1][j], 'a'), (best[i][j + 1], 't')]
            s = score(pa[i], pt[j])
            if s >= 2:
                drift = abs(starts[i] / total_t - text[j]['start'] / total_c)
                options.append((best[i + 1][j + 1] + s - 1.5 * drift, 'm'))
            best[i][j], move[i][j] = max(options, key=lambda o: o[0])
    pairs, i, j = [], 0, 0
    while i < n and j < m:
        step = move[i][j]
        if step == 'm': pairs.append((i, j)); i += 1; j += 1
        elif step == 'a': i += 1
        else: j += 1
    return pairs, pa

def percentile(values, q):
    if not values: return None
    v = sorted(values); k = (len(v) - 1) * q
    f = math.floor(k); c = math.ceil(k)
    return v[f] + (v[c] - v[f]) * (k - f)

rows = []
for work, ids in PAIRS.items():
    versions = json.loads((LIBRIVOX / f'{work}.json').read_text()) if (LIBRIVOX / f'{work}.json').exists() else []
    for book_id in ids:
        path = BOOKS / f'{book_id}.epub'
        if not path.exists(): continue
        m = epub_map.read(path)
        entries = [e for e in m['entries']]
        setting = RESULTS.get(book_id, {}).get('settings', {}).get('412x671@20')
        per_page = setting['visibleCharacters'] / setting['pages'] if setting else 583.0
        for v in versions:
            if (v.get('language') or 'English') != 'English': continue
            sections = [s for s in v['sections'] if s['seconds'] > 0]
            if len(sections) < 2: continue
            starts, at = [], 0
            for s in sections: starts.append(at); at += s['seconds']
            total_t = at
            readers = {r for s in sections for r in s['readers']}
            solo = len(readers) == 1
            pairs, parsed = chain(sections, entries, starts, total_t, m['characters'])
            titled_pairs = list(pairs)
            # Validation: drop the title anchor whose spans read at the most
            # implausible rate, until every span reads at 0.5 to 2 times the
            # median rate of the spans.
            dropped = 0
            def badness(pairs_):
                pts = [(starts[i], entries[j]['start']) for i, j in pairs_]
                spans = [((c1 - c0) / (t1 - t0)) if t1 > t0 else 0 for (t0, c0), (t1, c1) in zip(pts, pts[1:])]
                good = sorted(r for r in spans if r > 0)
                if not good: return 0
                med = good[len(good) // 2]
                return sum(0 if r > 0 and 0.5 <= r / med <= 2.0 else (abs(math.log(r / med)) if r > 0 else 9) for r in spans)
            while len(titled_pairs) >= 3 and badness(titled_pairs) > 0:
                best_k = min(range(len(titled_pairs)), key=lambda k: badness(titled_pairs[:k] + titled_pairs[k + 1:]))
                titled_pairs.pop(best_k); dropped += 1
            # Ordinal fill: where a gap between title anchors holds as many
            # audio sections as text entries at the anchors' depth, pair them
            # in order. The head and tail gaps count entries at the depth of
            # the nearest anchor, up to the first entry of another depth.
            filled = []
            bounds = [(-1, -1)] + titled_pairs + [(len(sections), len(entries))]
            for (i0, j0), (i1, j1) in zip(bounds, bounds[1:]):
                gap_a = list(range(i0 + 1, i1))
                if not gap_a: continue
                if i0 >= 0 and i1 < len(sections):
                    depth = entries[j0]['depth']
                    gap_t = [j for j in range(j0 + 1, j1) if entries[j]['depth'] == depth]
                elif i0 >= 0:
                    depth, gap_t = entries[j0]['depth'], []
                    for j in range(j0 + 1, len(entries)):
                        if entries[j]['depth'] != depth: break
                        gap_t.append(j)
                elif i1 < len(sections):
                    depth, gap_t = entries[j1]['depth'], []
                    for j in range(j1 - 1, -1, -1):
                        if entries[j]['depth'] != depth: break
                        gap_t.insert(0, j)
                else:
                    gap_t = []
                if len(gap_a) == len(gap_t):
                    filled += list(zip(gap_a, gap_t))
            all_pairs = sorted(titled_pairs + filled)
            anchors = [(starts[i], entries[j]['start'], i, j) for i, j in all_pairs]
            titled_set = set(titled_pairs)
            ranges = sum(1 for nums, _ in parsed if nums and nums[-1][0] != nums[-1][1])
            numbered = sum(1 for nums, _ in parsed if nums)
            titled = sum(1 for nums, words in parsed if words)
            depths = [entries[j]['depth'] for _, j in titled_pairs]
            chapter_depth = max(set(depths), key=depths.count) if depths else None
            chapter_entries = sum(1 for e in entries if e['depth'] == chapter_depth) if depths else 0
            covered = total_t - (starts[all_pairs[0][0]] if all_pairs else total_t)
            whole, ends, loo, loo_s, loo_same, loo_rel, loo_span = [], [], [], [], [], [], []
            C = m['characters']
            first, last = (anchors[0], anchors[-1]) if anchors else (None, None)
            for k, (t, c, i, j) in enumerate(anchors):
                if (i, j) not in titled_set: continue
                whole.append(abs(t / total_t * C - c) / per_page)
                if 0 < k < len(anchors) - 1:
                    (t0, c0, _, _), (t1, c1, _, _) = first, last
                    if t1 > t0 and c1 > c0:
                        ends.append(abs(c0 + (t - t0) / (t1 - t0) * (c1 - c0) - c) / per_page)
                    (t0, c0, i0, _), (t1, c1, i1, _) = anchors[k - 1], anchors[k + 1]
                    if t1 > t0 and c1 > c0:
                        pred = c0 + (t - t0) / (t1 - t0) * (c1 - c0)
                        rate = (c1 - c0) / (t1 - t0)
                        loo.append(abs(pred - c) / per_page)
                        loo_rel.append(abs(pred - c) / (c1 - c0))
                        loo_span.append((c1 - c0) / per_page)
                        loo_s.append(abs(pred - c) / rate)
                        same = set(sections[i0]['readers']) == set(sections[i]['readers'])
                        if same: loo_same.append(abs(pred - c) / per_page)
            # Characters per second of each anchored section, against the median.
            rates = []
            for k in range(len(anchors) - 1):
                (t0, c0, _, _), (t1, c1, _, _) = anchors[k], anchors[k + 1]
                if t1 > t0 and c1 >= c0: rates.append((c1 - c0) / (t1 - t0))
            med_rate = statistics.median(rates) if rates else None
            outliers = sum(1 for r in rates if med_rate and not (0.6 <= r / med_rate <= 1.6))
            rows.append({
                'work': work, 'ebook': book_id, 'librivox': v['id'], 'solo': solo,
                'sections': len(sections), 'entries': len(entries),
                'leaf_entries': sum(1 for k, e in enumerate(entries) if not (k + 1 < len(entries) and entries[k + 1]['depth'] > e['depth'])),
                'numbered': numbered, 'titled': titled, 'ranges': ranges,
                'anchors': len(anchors), 'title_anchors': len(titled_pairs), 'dropped': dropped, 'unmatched_sections': len(sections) - len(anchors), 'ends': ends, 'total_seconds': total_t, 'characters': C,
                'anchored_time_share': covered / total_t,
                'per_page': per_page, 'rate': med_rate, 'rate_outliers': outliers, 'rate_spans': len(rates),
                'whole': whole, 'loo_rel': loo_rel, 'loo_span': loo_span, 'chapter_entries': chapter_entries, 'loo': loo, 'loo_s': loo_s, 'loo_same': loo_same,
                'first_section': sections[0]['title'], 'first_entry_matched': entries[anchors[0][3]]['title'] if anchors else None,
            })

ROWS.write_text(json.dumps(rows))
print('pairs', len(rows), 'solo', sum(r['solo'] for r in rows))
