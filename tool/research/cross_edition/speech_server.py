# Tool code for the boo-snng speech prototype, not part of Bookfin.
# Two jobs on the user's Jellyfin server, with GET requests only. The
# server address and the API key come from the environment
# (BOOKFIN_SERVER_HOST, BOOKFIN_SERVER_KEY). The key goes only in the
# Authorization header. Nothing prints a title, an author or an item id:
# recordings get letters, and the private map stays in the work folder.
#
#   speech_server.py find <work dir>
#     Finds recordings of corpus works and writes <work>/server/private.json.
#   speech_server.py proxy <work dir> <port> <log.jsonl>
#     Serves each found recording at http://127.0.0.1:<port>/<letter>,
#     passing byte ranges through to the server, and logs each request's
#     range, bytes and times. Players read it without the key.
import json, os, re, sys, time, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.environ['BOOKFIN_SERVER_HOST'].strip().rstrip('/')
if not HOST.startswith('http'): HOST = 'https://' + HOST
AUTH = {'Authorization': f'MediaBrowser Token="{os.environ["BOOKFIN_SERVER_KEY"].strip()}"'}

# Corpus works: (key, EPUB of the corpus, title words, author word).
WORKS = [
    ('pride-and-prejudice', 'se-pride-and-prejudice', 'pride prejudice', 'austen'),
    ('emma', 'se-emma', 'emma', 'austen'),
    ('moby-dick', 'se-moby-dick', 'moby dick', 'melville'),
    ('jane-eyre', 'se-jane-eyre', 'jane eyre', 'bront'),
    ('wuthering-heights', 'se-wuthering-heights', 'wuthering heights', 'bront'),
    ('frankenstein', 'se-frankenstein', 'frankenstein', 'shelley'),
    ('dracula', 'se-dracula', 'dracula', 'stoker'),
    ('time-machine', 'se-the-time-machine', 'time machine', 'wells'),
    ('war-of-the-worlds', 'se-the-war-of-the-worlds', 'war worlds', 'wells'),
    ('alice', 'se-alices-adventures-in-wonderland', 'alice wonderland', 'carroll'),
    ('sherlock-holmes', 'se-the-adventures-of-sherlock-holmes', 'adventures sherlock holmes', 'doyle'),
    ('tale-of-two-cities', 'se-a-tale-of-two-cities', 'tale two cities', 'dickens'),
    ('bleak-house', 'se-bleak-house', 'bleak house', 'dickens'),
    ('huckleberry-finn', 'se-the-adventures-of-huckleberry-finn', 'huckleberry finn', 'twain'),
    ('treasure-island', 'se-treasure-island', 'treasure island', 'stevenson'),
    ('great-gatsby', 'se-the-great-gatsby', 'great gatsby', 'fitzgerald'),
    ('wind-in-the-willows', 'se-the-wind-in-the-willows', 'wind willows', 'grahame'),
    ('jungle-book', 'se-the-jungle-book', 'jungle book', 'kipling'),
    ('walden', 'se-walden', 'walden', 'thoreau'),
    ('crime-and-punishment', 'se-crime-and-punishment', 'crime punishment', 'dostoevsk'),
    ('anna-karenina', 'se-anna-karenina', 'anna karenina', 'tolstoy'),
    ('mrs-dalloway', 'se-mrs-dalloway', 'mrs dalloway', 'woolf'),
    ('heart-of-darkness', 'se-heart-of-darkness', 'heart darkness', 'conrad'),
    ('origin-of-species', 'se-the-origin-of-species', 'origin species', 'darwin'),
    ('meditations', 'se-meditations', 'meditations', 'aurelius'),
    ('art-of-war', 'se-the-art-of-war', 'art war', 'sun'),
    ('the-prince', 'se-the-prince', 'prince', 'machiavelli'),
    ('odyssey', 'se-the-odyssey', 'odyssey', 'homer'),
    ('ulysses', 'se-ulysses', 'ulysses', 'joyce'),
    ('wealth-of-nations', 'se-the-wealth-of-nations', 'wealth nations', 'smith'),
]


def get(path, **query):
    url = f'{HOST}{path}?{urllib.parse.urlencode(query)}'
    with urllib.request.urlopen(urllib.request.Request(url, headers=AUTH), timeout=60) as response:
        return json.load(response)


def find(work):
    found = []
    for key, epub, words, author in WORKS:
        try:
            items = get('/Items', Recursive='true', IncludeItemTypes='AudioBook', SearchTerm=words.split()[0],
                        Fields='Chapters,MediaSources,People', Limit=200).get('Items', [])
        except Exception as error:
            # The message of a failed request can hold the address.
            print('request failed', getattr(error, 'code', type(error).__name__)); continue
        for item in items:
            name = re.sub(r'[^a-z ]', ' ', item.get('Name', '').lower())
            people = ' '.join([item.get('AlbumArtist') or ''] + (item.get('Artists') or []) +
                              [p.get('Name', '') for p in item.get('People') or []]).lower()
            if all(w in name.split() for w in words.split()) and author in people:
                source = (item.get('MediaSources') or [{}])[0]
                found.append({'id': item['Id'], 'work': key, 'epub': epub,
                              'container': source.get('Container'), 'size': source.get('Size'),
                              'bitrate': source.get('Bitrate'),
                              'durationMs': (item.get('RunTimeTicks') or 0) // 10000,
                              'chapters': [{'name': c.get('Name', ''), 'startMs': c.get('StartPositionTicks', 0) // 10000}
                                           for c in item.get('Chapters') or []]})
    for i, f in enumerate(found):
        f['letter'] = chr(ord('A') + i)
    os.makedirs(f'{work}/server', exist_ok=True)
    with open(f'{work}/server/private.json', 'w') as out:
        json.dump(found, out)
    for f in found:
        names = [c['name'].lower() for c in f['chapters']]
        print(f['letter'], f['container'], f'{f["durationMs"] / 3600000:.1f} h', f'{(f["size"] or 0) / 1e6:.0f} MB',
              f'{(f["bitrate"] or 0) / 1000:.0f} kb/s', len(names), 'chapters',
              'opening credits' if names and 'credit' in names[0] else '',
              'end credits' if names and 'credit' in names[-1] else '')


class Proxy(BaseHTTPRequestHandler):
    def do_GET(self):
        letter = self.path.strip('/').split('?')[0]
        item = ITEMS.get(letter)
        if item is None:
            self.send_error(404); return
        headers = dict(AUTH)
        if 'Range' in self.headers: headers['Range'] = self.headers['Range']
        started = time.time()
        request = urllib.request.Request(f'{HOST}/Items/{item["id"]}/Download', headers=headers)
        sent = 0
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                first = time.time()
                self.send_response(response.status)
                for name in ('Content-Type', 'Content-Length', 'Content-Range', 'Accept-Ranges'):
                    if response.headers.get(name): self.send_header(name, response.headers[name])
                self.end_headers()
                while True:
                    chunk = response.read(65536)
                    if not chunk: break
                    try:
                        self.wfile.write(chunk)
                    except (BrokenPipeError, ConnectionResetError):
                        break
                    sent += len(chunk)
        except urllib.error.HTTPError as error:
            self.send_error(error.code); first = time.time()
        with open(LOG, 'a') as log:
            log.write(json.dumps({'at': started, 'letter': letter, 'range': self.headers.get('Range'),
                                  'firstByteMs': round((first - started) * 1000), 'totalMs': round((time.time() - started) * 1000),
                                  'sent': sent}) + '\n')

    def log_message(self, *args):
        pass


if __name__ == '__main__':
    if sys.argv[1] == 'find':
        find(sys.argv[2])
    else:
        ITEMS = {f['letter']: f for f in json.load(open(f'{sys.argv[2]}/server/private.json'))}
        LOG = sys.argv[4]
        ThreadingHTTPServer(('127.0.0.1', int(sys.argv[3])), Proxy).serve_forever()
