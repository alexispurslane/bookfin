# Tool code for the boo-snng speech prototype, not part of Bookfin.
# Turns an EPUB into the word list that the speech search reads: each word
# normalized, with the visible characters before it (white space left out,
# as lib/reader/book_map.dart counts) and the number of its sentence, plus
# the contents entries with their starts. Usage:
#   speech_book.py <book.epub> <out.json>
import json, os, posixpath, re, sys, urllib.parse, zipfile
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import epub_map

SPACE = re.compile(r'\s')
BLOCKS = {'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote', 'tr', 'section', 'br', 'hr'}
ABBREVIATIONS = {'mr', 'mrs', 'dr', 'st', 'messrs', 'mme', 'mlle', 'ms', 'no', 'vol', 'chap', 'esq', 'rev', 'col', 'capt', 'gen', 'lt', 'sr', 'jr', 'co'}
UNITS = 'zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen'.split()
TENS = 'zero ten twenty thirty forty fifty sixty seventy eighty ninety'.split()


def number_words(n):
    """The cardinal words of n below a million, without "and"."""
    if n < 20: return [UNITS[n]]
    if n < 100: return [TENS[n // 10]] + ([UNITS[n % 10]] if n % 10 else [])
    if n < 1000: return [UNITS[n // 100], 'hundred'] + (number_words(n % 100) if n % 100 else [])
    return number_words(n // 1000) + ['thousand'] + (number_words(n % 1000) if n % 1000 else [])


def normalize(token):
    """The search words of one token of text. The Dart probe's
    normalizeWords applies the same rules."""
    t = token.lower()
    for dash in '—–…':
        t = t.replace(dash, ' ')
    out = []
    for part in t.split():
        word = re.sub(r'[^a-z0-9]', '', part)
        if not word: continue
        if word.isdigit() and len(word) <= 6: out += number_words(int(word))
        else: out.append(word)
    return out


class Words(HTMLParser):
    def __init__(self, base, sentence):
        super().__init__(convert_charrefs=True)
        self.base, self.visible, self.body, self.skip = base, 0, False, 0
        self.words, self.sentence, self.open = [], sentence, False
    def end_sentence(self):
        if self.open: self.sentence += 1; self.open = False
    def handle_starttag(self, tag, attrs):
        tag = tag.split(':')[-1]
        if tag == 'body': self.body = True
        if tag in ('script', 'style'): self.skip += 1
        if tag in BLOCKS: self.end_sentence()
    def handle_startendtag(self, tag, attrs):
        tag = tag.split(':')[-1]
        if tag in BLOCKS: self.end_sentence()
    def handle_endtag(self, tag):
        tag = tag.split(':')[-1]
        if tag in ('script', 'style'): self.skip -= 1
        if tag in BLOCKS: self.end_sentence()
    def handle_data(self, data):
        if not self.body or self.skip > 0: return
        for m in re.finditer(r'\S+', data):
            before = len(SPACE.sub('', data[:m.start()]))
            raw = m.group().replace('’', "'").replace('‘', "'")
            for word in normalize(raw):
                self.words.append((word, self.base + self.visible + before, self.sentence))
                self.open = True
            bare = re.sub(r"[\"')\]”]+$", '', raw)
            if bare.endswith(('.', '!', '?')) and re.sub(r'[^a-z]', '', bare.lower()) not in ABBREVIATIONS:
                self.end_sentence()
        self.visible += len(SPACE.sub('', data))


def read(path):
    z = zipfile.ZipFile(path)
    container = ET.fromstring(z.read('META-INF/container.xml'))
    opf_path = next(e.get('full-path') for e in container.iter() if e.tag.endswith('rootfile'))
    base = posixpath.dirname(opf_path)
    opf = ET.fromstring(z.read(opf_path))
    manifest = {e.get('id'): posixpath.normpath(posixpath.join(base, urllib.parse.unquote(e.get('href'))))
                for e in opf.iter() if e.tag.endswith('}item')}
    spine = [manifest[e.get('idref')] for e in opf.iter() if e.tag.endswith('itemref')]
    words, total, sentence = [], 0, 0
    for p in spine:
        try: text = z.read(p).decode('utf-8', 'replace')
        except KeyError: continue
        w = Words(total, sentence); w.feed(text); w.close(); w.end_sentence()
        words += w.words; total += w.visible; sentence = w.sentence
    return words, total


if __name__ == '__main__':
    words, total = read(sys.argv[1])
    outline = epub_map.read(sys.argv[1])
    assert outline['characters'] == total, (outline['characters'], total)
    json.dump({'words': [w for w, _, _ in words], 'offsets': [o for _, o, _ in words],
               'sentences': [s for _, _, s in words], 'characters': total,
               'entries': outline['entries']}, open(sys.argv[2], 'w'))
    print(sys.argv[1], len(words), 'words', total, 'characters', words[-1][2] + 1, 'sentences')
