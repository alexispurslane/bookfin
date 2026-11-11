# Tool code for the boo-snng speech prototype, not part of Bookfin.
# Downloads LibriVox section recordings for the speech measurement and
# writes a manifest of every section of each recording (title, playtime
# and the file, when downloaded). Usage:
#   fetch_speech_audio.py <out dir> <key>:<project id>:<all|n,n,...> ...
# Example: fetch_speech_audio.py audio time-machine:5630:all moby-dick:21919:20,50
import json, pathlib, sys, time, urllib.parse, urllib.request

out = pathlib.Path(sys.argv[1])
for spec in sys.argv[2:]:
    key, project, wanted = spec.split(':')
    folder = out / key
    folder.mkdir(parents=True, exist_ok=True)
    query = urllib.parse.urlencode({'id': project, 'extended': 1, 'format': 'json'})
    request = urllib.request.Request(f'https://librivox.org/api/feed/audiobooks/?{query}',
                                     headers={'User-Agent': 'curl/8.7.1'})
    with urllib.request.urlopen(request, timeout=60) as response:
        book = json.load(response)['books'][0]
    sections = sorted(book['sections'], key=lambda s: int(s['section_number']))
    numbers = {int(s['section_number']) for s in sections} if wanted == 'all' else {int(n) for n in wanted.split(',')}
    manifest = []
    for s in sections:
        n = int(s['section_number'])
        entry = {'n': n, 'title': s['title'], 'playtime': int(s['playtime'] or 0), 'file': None}
        if n in numbers:
            target = folder / f'{n:03d}.mp3'
            if not target.exists():
                partial = target.with_suffix('.part')
                url = s['listen_url'].replace('http://', 'https://')
                with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'curl/8.7.1'}), timeout=300) as response:
                    partial.write_bytes(response.read())
                partial.rename(target)
                time.sleep(0.5)
            entry['file'] = target.name
        manifest.append(entry)
    (folder / 'manifest.json').write_text(json.dumps({'project': int(project), 'title': book['title'], 'sections': manifest}, indent=1))
    print(key, project, len(manifest), 'sections,', sum(1 for e in manifest if e['file']), 'downloaded')
