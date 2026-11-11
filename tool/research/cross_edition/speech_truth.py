# Tool code for the boo-snng speech prototype, not part of Bookfin.
# Makes the reference map of each recording: where each spoken word lies
# in the book. It transcribes whole sections with whisper.cpp base.en (on
# the Mac's GPU, with token times), and aligns the words with the book by
# word sequences of four that occur once in the book, kept in increasing
# order. The probe under test never reads these transcripts. Usage:
#   speech_truth.py <ffmpeg> <whisper-cli> <models dir> <audio dir> <books dir> <truth dir> <key>[:n,n,...] ...
# Without a list of section numbers, it transcribes every downloaded section.
import bisect, json, os, pathlib, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from speech_book import normalize

FFMPEG, WHISPER, MODELS, AUDIO, BOOKS, TRUTH = sys.argv[1:7]


def heard_words(transcript):
    """Each normalized spoken word with the start of its first token, in ms."""
    words = []
    pending, start = '', None
    def flush():
        if pending:
            for w in normalize(pending.replace('’', "'")):
                words.append((w, start))
    for segment in transcript['transcription']:
        for token in segment['tokens']:
            text = token['text']
            if text.startswith('[_') or text.startswith('<|'):
                continue
            if text.startswith(' ') or pending == '':
                flush(); pending, start = text, token['offsets']['from']
            else:
                pending += text
    flush()
    return words


def align(heard, book):
    """Pairs (heard index, book word) that a unique word sequence of four
    gives, in increasing order of both, with runs between them filled."""
    grams = {}
    for p in range(len(book) - 3):
        g = tuple(book[p:p + 4])
        grams[g] = -1 if g in grams else p
    seeds = []
    for i in range(len(heard) - 3):
        p = grams.get(tuple(heard[i:i + 4]), -1)
        if p >= 0: seeds.append((i, p))
    # The longest chain that increases in both, by patience sorting on p.
    tails, values, prev = [], [], []
    for k, (_, p) in enumerate(seeds):
        j = bisect.bisect_left(values, p)
        prev.append(tails[j - 1] if j else -1)
        if j == len(tails): tails.append(k); values.append(p)
        else: tails[j] = k; values[j] = p
    chain, k = [], tails[-1] if tails else -1
    while k >= 0: chain.append(seeds[k]); k = prev[k]
    chain.reverse()
    # Keep seeds whose word distance agrees with their neighbors', so a
    # stray repeat does not bend the map.
    kept = [c for n, c in enumerate(chain)
            if any(abs((c[1] - c[0]) - (d[1] - d[0])) <= 20 for d in chain[max(0, n - 3):n] + chain[n + 1:n + 4])]
    # Keep the longest run whose word distance moves by at most 200 words
    # from seed to seed: a section reads one stretch of the book.
    runs, run = [], []
    for c in kept:
        if run and abs((c[1] - c[0]) - (run[-1][1] - run[-1][0])) > 200:
            runs.append(run); run = []
        run.append(c)
    if run: runs.append(run)
    kept = max(runs, key=len) if runs else []
    pairs = []
    for (i1, p1), (i2, p2) in zip(kept, kept[1:] + [kept[-1]]):
        pairs.append((i1, p1))
        if i2 - i1 == p2 - p1 and 1 < i2 - i1 <= 40:
            pairs += [(i1 + d, p1 + d) for d in range(1, i2 - i1) if heard[i1 + d] == book[p1 + d]]
    return sorted(set(pairs))


for spec in sys.argv[7:]:
    key, _, numbers = spec.partition(':')
    numbers = {int(n) for n in numbers.split(',')} if numbers else None
    book = json.load(open(f'{BOOKS}/{key}.json'))['words']
    manifest = json.load(open(f'{AUDIO}/{key}/manifest.json'))
    out = pathlib.Path(TRUTH) / key
    out.mkdir(parents=True, exist_ok=True)
    for section in manifest['sections']:
        if not section['file'] or (numbers and section['n'] not in numbers): continue
        target = out / f"{section['n']:03d}.json"
        if target.exists():
            # Align a kept transcript again, without transcribing.
            kept = json.load(open(target))
            if 'ms' in kept and os.environ.get('REALIGN'):
                heard = list(zip(kept['words'], kept['ms']))
                kept['points'] = [[heard[i][1], p] for i, p in align(kept['words'], book)]
                target.write_text(json.dumps(kept))
                print(key, section['n'], 'realigned', len(kept['points']), 'points',
                      f"book words {kept['points'][0][1]}..{kept['points'][-1][1]}", flush=True)
            continue
        with tempfile.TemporaryDirectory() as tmp:
            wav = f'{tmp}/a.wav'
            subprocess.run([FFMPEG, '-v', 'error', '-y', '-i', f"{AUDIO}/{key}/{section['file']}", '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', wav], check=True)
            duration = os.path.getsize(wav) / 32000
            subprocess.run([WHISPER, '-m', f'{MODELS}/ggml-base.en.bin', '-f', wav, '-ojf', '-of', f'{tmp}/t', '-t', '4', '-np'],
                           check=True, capture_output=True)
            transcript = json.load(open(f'{tmp}/t.json'))
        heard = heard_words(transcript)
        pairs = align([w for w, _ in heard], book)
        points = [[heard[i][1], p] for i, p in pairs]
        target.write_text(json.dumps({'duration_ms': round(duration * 1000), 'heard': len(heard),
                                      'words': [w for w, _ in heard], 'ms': [m for _, m in heard], 'points': points}))
        print(key, section['n'], f'{duration / 60:.1f} min', len(heard), 'words', len(points), 'points',
              f'book words {points[0][1] if points else None}..{points[-1][1] if points else None}', flush=True)
