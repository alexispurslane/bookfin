# Tool code for the boo-snng speech prototype, not part of Bookfin.
# Simulates the anchor map on the reference maps of speech_truth.py: while
# a person listens straight through, an anchor (audio time, book word) is
# kept every N minutes. A place between two anchors is placed by straight
# interpolation in both directions. Compares each placement with the
# reference map. Anchors here are exact; the window measurement gives the
# error of a real anchor, which adds a few words. Usage:
#   speech_anchor_map.py <work dir> <out.json> <key> ...
import bisect, json, statistics, sys

WORK, OUT = sys.argv[1], sys.argv[2]
PAGE = 582
SPACINGS_MIN = [1, 2, 5, 10, 20]


def stretches(key):
    """Runs of continuous listening: (edition ms, book word) points. A
    whole downloaded book is one run; each section of a partial book is
    one."""
    manifest = json.load(open(f'{WORK}/audio/{key}/manifest.json'))
    durations = json.load(open(f'{WORK}/out/durations.json'))
    runs, run, start, previous = [], [], 0, True
    for s in manifest['sections']:
        path = f"{WORK}/audio/{key}/{s['file']}" if s['file'] else None
        duration = durations.get(path) if path else None
        duration = duration or s['playtime'] * 1000
        try:
            truth = json.load(open(f"{WORK}/truth/{key}/{s['n']:03d}.json"))
        except FileNotFoundError:
            truth = None
        if truth is None:
            if run: runs.append(run); run = []
        else:
            run += [(start + ms, p) for ms, p in truth['points']]
        start += duration
    if run: runs.append(run)
    return runs


def percentile(values, q):
    values = sorted(values)
    return values[min(len(values) - 1, int(q * len(values)))] if values else None


POOLED = {m: ([], [], []) for m in SPACINGS_MIN}


def summary(a2t_pages, a2t_sentence, t2a_seconds):
    return {
        'places': len(a2t_pages),
        'audioToTextPagesMedian': statistics.median(a2t_pages) if a2t_pages else None,
        'audioToTextPagesP90': percentile(a2t_pages, 0.9),
        'audioToTextPagesP99': percentile(a2t_pages, 0.99),
        'sameSentence': sum(a2t_sentence) / len(a2t_sentence) if a2t_sentence else None,
        'textToAudioSecondsMedian': statistics.median(t2a_seconds) if t2a_seconds else None,
        'textToAudioSecondsP90': percentile(t2a_seconds, 0.9),
        'textToAudioSecondsP99': percentile(t2a_seconds, 0.99),
    }


def simulate(key, book):
    offsets, sentences = book['offsets'], book['sentences']
    rows = {}
    for minutes in SPACINGS_MIN:
        spacing = minutes * 60000
        a2t_pages, a2t_sentence, t2a_seconds = [], [], []
        for run in stretches(key):
            times = [t for t, _ in run]
            anchors = []
            t = times[0]
            while t <= times[-1]:
                k = bisect.bisect_left(times, t)
                if k < len(run) and abs(run[k][0] - t) < 3000:
                    anchors.append(run[k])
                t += spacing
            if len(anchors) < 2: continue
            at = [a[0] for a in anchors]
            words = [a[1] for a in anchors]
            # Every fifth reference point between the first and last anchor.
            for ms, word in run[::5]:
                if ms < at[0] or ms > at[-1]: continue
                k = min(bisect.bisect_right(at, ms) - 1, len(at) - 2)
                (t0, w0), (t1, w1) = anchors[k], anchors[k + 1]
                guess = round(w0 + (ms - t0) / (t1 - t0) * (w1 - w0)) if t1 > t0 else w0
                guess = max(0, min(len(offsets) - 1, guess))
                a2t_pages.append(abs(offsets[guess] - offsets[word]) / PAGE)
                a2t_sentence.append(sentences[guess] == sentences[word])
                # The other direction: the time of this word from the anchors.
                j = min(bisect.bisect_right(words, word) - 1, len(words) - 2)
                (t0, w0), (t1, w1) = anchors[max(0, j)], anchors[max(0, j) + 1]
                when = t0 + (word - w0) / (w1 - w0) * (t1 - t0) if w1 != w0 else t0
                t2a_seconds.append(abs(when - ms) / 1000)
        rows[minutes] = summary(a2t_pages, a2t_sentence, t2a_seconds)
        if len(stretches(key)) == 1:
            # Pool only whole books: their one run spans every spacing.
            for pool, values in zip(POOLED[minutes], (a2t_pages, a2t_sentence, t2a_seconds)):
                pool += values
    return rows


result = {}
for key in sys.argv[3:]:
    book = json.load(open(f'{WORK}/books/{key}.json'))
    result[key] = simulate(key, book)
result['whole books'] = {m: summary(*POOLED[m]) for m in SPACINGS_MIN}
for key in result:
    for minutes, row in result[key].items():
        if not row['places']: continue
        print(key, f'{minutes:>2} min', row['places'], 'places',
              f"pages median {row['audioToTextPagesMedian']:.2f} p90 {row['audioToTextPagesP90']:.2f}",
              f"same sentence {row['sameSentence']:.0%}",
              f"seconds median {row['textToAudioSecondsMedian']:.1f} p90 {row['textToAudioSecondsP90']:.1f}",
              f"p99 pages {row['audioToTextPagesP99']:.2f} seconds {row['textToAudioSecondsP99']:.1f}")
json.dump(result, open(OUT, 'w'), indent=1)
