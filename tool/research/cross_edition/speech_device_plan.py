# Tool code for the boo-snng speech prototype, not part of Bookfin.
# Writes plan.json for the Android harness (speech_probe/lib/main.dart):
# windows of public LibriVox chapters at times that the reference map
# covers, for each model, window length, thread count and audio source,
# with the reference word of each window's place. Usage:
#   speech_device_plan.py <work dir> <out plan.json> <local port> <proxy port>
import bisect, json, random, sys

WORK, OUT, LOCAL, PROXY = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
random.seed(20261111)
durations = json.load(open(f'{WORK}/out/durations.json'))


def places(key, count):
    """Random (file, ms in file, edition ms, reference word) in sections
    with a reference map."""
    book = json.load(open(f'{WORK}/books/{key}.json'))
    manifest = json.load(open(f'{WORK}/audio/{key}/manifest.json'))
    starts, start = {}, 0
    for s in manifest['sections']:
        path = f"{WORK}/audio/{key}/{s['file']}" if s['file'] else None
        starts[s['n']] = start
        start += durations.get(path) or s['playtime'] * 1000
    total = start
    out = []
    while len(out) < count:
        s = random.choice([s for s in manifest['sections'] if s['file']])
        try:
            truth = json.load(open(f"{WORK}/truth/{key}/{s['n']:03d}.json"))
        except FileNotFoundError:
            continue
        ms = [p[0] for p in truth['points']]
        if ms[-1] - ms[0] < 60000: continue
        t = random.randint(ms[0] + 20000, ms[-1] - 20000)
        k = bisect.bisect_right(ms, t) - 1
        if k + 1 >= len(ms) or ms[k + 1] - ms[k] > 3000: continue
        word = truth['points'][k][1]
        edition = starts[s['n']] + t
        estimate = bisect.bisect_left(book['offsets'], edition / total * book['characters'])
        out.append({'book': key, 'file': f"audio/{key}/{s['file']}", 'ms': t, 'truth': word,
                    'around': min(estimate, len(book['words']) - 1)})
    return out


def job(place, model='tiny.en-q5_1', length=15000, ctx=0, threads=4, source=None, label=''):
    start = max(0, place['ms'] - length // 2) if length >= 15000 else max(0, place['ms'] - length)
    return {'label': label, 'model': model, 'threads': threads, 'ctx': ctx, 'lengthMs': length,
            'source': source or place['file'], 'startMs': start, 'atOffsetMs': place['ms'] - start,
            'book': place['book'], 'around': place['around'], 'radii': [8, 24, 72, -1], 'truth': place['truth']}


def reduced(length):
    return min(1500, -(-length * 11 // 200) + 32)


pool = places('alice', 20) + places('time-machine', 20)
jobs = []
# Models at 15 s with the full 30 s context, 4 threads.
for model in ['tiny.en-q5_1', 'tiny.en-q8_0', 'tiny.en', 'base.en-q5_1', 'base.en-q8_0']:
    jobs += [job(p, model=model, label='model') for p in pool[:12]]
# Window lengths for the anchor map: the last L s before the place.
for length in [5000, 8000, 15000]:
    jobs += [job(p, length=length, ctx=reduced(length), label='length-reduced') for p in pool[12:24]]
    if length < 15000:
        jobs += [job(p, length=length, label='length-full') for p in pool[12:24]]
# Two threads.
jobs += [job(p, threads=2, label='threads') for p in pool[:12]]
# The same windows streamed by byte ranges from a server on the host.
jobs += [job(p, source=f"http://127.0.0.1:{LOCAL}/{p['file'][len('audio/'):]}", label='stream-local') for p in pool[24:36]]
# Windows of the user's server recordings, through speech_server.py's
# proxy: an MP3 and an M4B whose index (moov) sits at the file's end. They
# have no reference map; they measure fetch and decode time.
items = {f['letter']: f for f in json.load(open(f'{WORK}/server/private.json'))}
for letter in ['B', 'C']:
    book = json.load(open(f'{WORK}/server/books/{letter}.json'))
    duration = items[letter]['durationMs']
    for _ in range(6):
        t = random.randint(60000, duration - 60000)
        around = min(bisect.bisect_left(book['offsets'], t / duration * book['characters']), len(book['words']) - 1)
        jobs.append(job({'book': letter, 'file': None, 'ms': t, 'truth': None, 'around': around},
                        source=f'http://127.0.0.1:{PROXY}/{letter}', label='stream-server'))
json.dump({'jobs': jobs}, open(OUT, 'w'))
print(len(jobs), 'jobs')
