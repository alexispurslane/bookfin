# Tool code for the boo-z3is design measurement, not part of Bookfin. Reads an EPUB's contents
# (nav or NCX, flattened with depth) and counts visible characters, white
# space left out, as lib/reader/book_map.dart does.
import posixpath, re, zipfile, urllib.parse
from html.parser import HTMLParser
import xml.etree.ElementTree as ET

SPACE = re.compile(r'\s')

class _Counter(HTMLParser):
    def __init__(self, ids):
        super().__init__(convert_charrefs=True)
        self.ids, self.before, self.visible, self.body = ids, {}, 0, False
        self.skip = 0
    def handle_starttag(self, tag, attrs):
        tag = tag.split(':')[-1]
        if tag == 'body': self.body = True
        if tag in ('script', 'style'): self.skip += 1
        for name, value in attrs:
            if name == 'id' and value in self.ids and value not in self.before:
                self.before[value] = self.visible
    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag.split(':')[-1] in ('script', 'style'): self.skip -= 1
    def handle_endtag(self, tag):
        if tag.split(':')[-1] in ('script', 'style'): self.skip -= 1
    def handle_data(self, data):
        if self.body and self.skip <= 0:
            self.visible += len(SPACE.sub('', data))

def _local(tag): return tag.split('}')[-1]

def read(path):
    z = zipfile.ZipFile(path)
    container = ET.fromstring(z.read('META-INF/container.xml'))
    opf_path = next(e.get('full-path') for e in container.iter() if _local(e.tag) == 'rootfile')
    base = posixpath.dirname(opf_path)
    opf = ET.fromstring(z.read(opf_path))
    manifest, nav, ncx = {}, None, None
    for e in opf.iter():
        if _local(e.tag) == 'item':
            href = posixpath.normpath(posixpath.join(base, urllib.parse.unquote(e.get('href'))))
            manifest[e.get('id')] = href
            if 'nav' in (e.get('properties') or '').split(): nav = href
            if e.get('media-type') == 'application/x-dtbncx+xml': ncx = href
    spine = [manifest[e.get('idref')] for e in opf.iter() if _local(e.tag) == 'itemref']
    entries = []  # (title, section path, fragment, depth)
    def resolve(doc, href):
        target = urllib.parse.urljoin('https://b/' + doc, href)
        parsed = urllib.parse.urlparse(target)
        return posixpath.normpath(urllib.parse.unquote(parsed.path.lstrip('/'))), urllib.parse.unquote(parsed.fragment) or None
    if nav:
        root = ET.fromstring(z.read(nav))
        toc = None
        for e in root.iter():
            if _local(e.tag) == 'nav' and any(v == 'toc' for k, v in e.attrib.items() if k.endswith('type')):
                toc = e; break
        def walk(ol, depth):
            for li in ol:
                if _local(li.tag) != 'li': continue
                a = next((c for c in li if _local(c.tag) in ('a', 'span')), None)
                if a is not None and a.get('href'):
                    title = ' '.join(''.join(a.itertext()).split())
                    path, frag = resolve(nav, a.get('href'))
                    entries.append((title, path, frag, depth))
                for c in li:
                    if _local(c.tag) == 'ol': walk(c, depth + 1)
        if toc is not None:
            for c in toc:
                if _local(c.tag) == 'ol': walk(c, 0)
    if not entries and ncx:
        root = ET.fromstring(z.read(ncx))
        def walkn(node, depth):
            for p in node:
                if _local(p.tag) != 'navPoint': continue
                label = next((e for e in p.iter() if _local(e.tag) == 'text'), None)
                content = next((e for e in p if _local(e.tag) == 'content'), None)
                if content is not None:
                    path, frag = resolve(ncx, content.get('src'))
                    entries.append((' '.join(''.join(label.itertext()).split()) if label is not None else '', path, frag, depth))
                walkn(p, depth + 1)
        navmap = next(e for e in root.iter() if _local(e.tag) == 'navMap')
        walkn(navmap, 0)
    wanted = {}
    for _, path, frag, _ in entries:
        if frag: wanted.setdefault(path, set()).add(frag)
    starts, total = {}, 0
    offsets = {}
    for path in spine:
        try: text = z.read(path).decode('utf-8', 'replace')
        except KeyError: continue
        c = _Counter(wanted.get(path, set()))
        c.feed(text); c.close()
        starts[path] = total
        for ident, before in c.before.items(): offsets[(path, ident)] = total + before
        total += c.visible
    out = []
    for title, path, frag, depth in entries:
        if path not in starts: continue
        at = offsets.get((path, frag), starts[path]) if frag else starts[path]
        out.append({'title': title, 'start': at, 'depth': depth})
    out.sort(key=lambda e: e['start'])  # stable: entries at one place keep order
    return {'entries': out, 'characters': total}

if __name__ == '__main__':
    import sys, json
    m = read(sys.argv[1])
    print(m['characters'], len(m['entries']))
    for e in m['entries'][:int(sys.argv[2]) if len(sys.argv) > 2 else 15]:
        print('  ' * e['depth'], e['start'], e['title'])
