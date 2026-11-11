# Tool code for the boo-z3is design measurement, not part of Bookfin.
# Design B probe: transcribe a short audio window, find its words in the
# ebook chapter, and compare with design A's proportional estimate. Usage:
#   align_probe.py <ffmpeg> <whisper-cli> <models dir> <windows dir>
#     <audio dir> <corpus books dir> <corpus results.json> <rows.json>
import json, os, re, subprocess, sys, time, zipfile, posixpath, urllib.parse, resource
from html.parser import HTMLParser
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import epub_map
FFMPEG, WHISPER, MODELS, OUT, AUDIO, BOOKS, RESULTS, ROWS = sys.argv[1:9]
SPACE = re.compile(r'\s')

class Words(HTMLParser):
    """Each word of the body with the visible characters before it."""
    def __init__(self, base):
        super().__init__(convert_charrefs=True)
        self.base, self.visible, self.body, self.words = base, 0, False, []
    def handle_starttag(self, tag, attrs):
        if tag.split(':')[-1] == 'body': self.body = True
    def handle_data(self, data):
        if not self.body: return
        for m in re.finditer(r'\S+', data):
            before = len(SPACE.sub('', data[:m.start()]))
            word = re.sub(r"[^a-z0-9']", '', m.group().lower().replace('’', "'"))
            if word: self.words.append((word, self.base + self.visible + before))
        self.visible += len(SPACE.sub('', data))

def book_words(path):
    z = zipfile.ZipFile(path)
    import xml.etree.ElementTree as ET
    container = ET.fromstring(z.read('META-INF/container.xml'))
    opf_path = next(e.get('full-path') for e in container.iter() if e.tag.endswith('rootfile'))
    base = posixpath.dirname(opf_path)
    opf = ET.fromstring(z.read(opf_path))
    manifest = {e.get('id'): posixpath.normpath(posixpath.join(base, urllib.parse.unquote(e.get('href')))) for e in opf.iter() if e.tag.endswith('}item')}
    spine = [manifest[e.get('idref')] for e in opf.iter() if e.tag.endswith('itemref')]
    words, total = [], 0
    for p in spine:
        w = Words(total); w.feed(z.read(p).decode('utf-8', 'replace')); w.close()
        words += w.words; total += w.visible
    return words

def lcs(a, b):
    prev = [0] * (len(b) + 1)
    for x in a:
        cur = [0]
        for j, y in enumerate(b):
            cur.append(prev[j] + 1 if x == y else max(prev[j + 1], cur[j]))
        prev = cur
    return prev[-1]

CASES = [
    # mp3, ebook id, chapter entry title, next entry title, seconds, per page
    ('pp03.mp3', 'se-pride-and-prejudice', 'III', 'IV'),
    ('md05.mp3', 'se-moby-dick', 'III: The Spouter-Inn', 'IV: The Counterpane'),
    ('je04.mp3', 'se-jane-eyre', 'IV', 'V'),
]
results = json.load(open(RESULTS))['books']
rows = []
for mp3, book, title, next_title in CASES:
    path = f'{BOOKS}/{book}.epub'
    entries = epub_map.read(path)['entries']
    start = next(e['start'] for e in entries if e['title'] == title)
    end = next(e['start'] for e in entries if e['title'] == next_title and e['start'] > start)
    s = results[book]['settings']['412x671@20']; per_page = s['visibleCharacters'] / s['pages']
    words = [(w, at) for w, at in book_words(path) if start <= at < end]
    seconds = float(subprocess.run([FFMPEG[:-len('ffmpeg')] + 'ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f'{AUDIO}/{mp3}'], capture_output=True, text=True).stdout)
    for share in (0.2, 0.4, 0.6, 0.8):
        at = share * seconds
        wav = f'{OUT}/{mp3}-{share}.wav'
        subprocess.run([FFMPEG, '-v', 'error', '-y', '-ss', str(at), '-t', '15', '-i', f'{AUDIO}/{mp3}', '-ar', '16000', '-ac', '1', wav], check=True)
        estimate = start + share * (end - start)
        for model in ('tiny.en', 'base.en'):
            before = resource.getrusage(resource.RUSAGE_CHILDREN)
            t0 = time.time()
            out = subprocess.run([WHISPER, '-m', f'{MODELS}/ggml-{model}.bin', '-f', wav, '-t', '4', '-nt', '-np'], capture_output=True, text=True)
            wall = time.time() - t0
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            cpu = (after.ru_utime - before.ru_utime) + (after.ru_stime - before.ru_stime)
            heard = [re.sub(r"[^a-z0-9']", '', w.lower().replace('’', "'")) for w in out.stdout.split()]
            heard = [w for w in heard if w][1:13]  # skip a partial first word
            best, second, found = -1, -1, None
            text = [w for w, _ in words]
            for p in range(0, max(1, len(text) - 1)):
                score = lcs(heard, text[p:p + len(heard) + 4])
                if score > best:
                    if found is None or abs(p - found) > 30: second = best
                    best, found = score, p
                elif score > second and abs(p - found) > 30:
                    second = score
            found_at = words[found][1] if found is not None else None
            rows.append({'case': mp3, 'share': share, 'model': model, 'wall': round(wall, 2), 'cpu': round(cpu, 2),
                         'heard': ' '.join(heard), 'matched': best, 'of': len(heard), 'runner_up': second,
                         'a_error_pages': round((estimate - found_at) / per_page, 2) if found_at is not None else None,
                         'a_error_seconds': round((estimate - found_at) / ((end - start) / seconds), 1) if found_at is not None else None,
                         'chapter_pages': round((end - start) / per_page, 1), 'chapter_seconds': round(seconds)})
            print(json.dumps(rows[-1]))
json.dump(rows, open(ROWS, 'w'))
