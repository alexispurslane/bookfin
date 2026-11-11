# Tool code for the boo-snng speech prototype, not part of Bookfin.
# Summarizes the JSON lines of host_eval.dart and of the Android harness
# into the tables of docs/plans/cross-edition-places.md, "Speech search
# prototype". Usage:
#   speech_report.py <kind> <rows.jsonl> ...
# Kinds: audio-to-text, text-to-audio, intro, windows, server, device.
import collections, json, statistics, sys

PAGE = 582


def rows(paths):
    for path in paths:
        for line in open(path):
            row = json.loads(line)
            if 'event' not in row: yield row


def q(values, p):
    values = sorted(v for v in values if v is not None)
    if not values: return None
    return values[min(len(values) - 1, int(p * len(values)))]


def med(values):
    values = [v for v in values if v is not None]
    return statistics.median(values) if values else None


def fmt(v, digits=2):
    return '-' if v is None else (f'{v:.{digits}f}' if isinstance(v, float) else str(v))


def timing(windows, label):
    print(f'{label}: {len(windows)} windows',
          '| decode ms', fmt(med([w['decodeMs'] for w in windows]), 0), fmt(q([w['decodeMs'] for w in windows], .9), 0),
          '| transcribe ms', fmt(med([w['transcribeMs'] for w in windows]), 0), fmt(q([w['transcribeMs'] for w in windows], .9), 0),
          '| CPU ms', fmt(med([w['transcribeCpuMs'] for w in windows]), 0), fmt(q([w['transcribeCpuMs'] for w in windows], .9), 0))


def audio_to_text(data):
    for source in ('share', 'chapter', 'whole'):
        cases = [r[source] for r in data if source in r]
        with_truth = [c for c in cases if c.get('truth') is not None]
        landed = [c for c in with_truth if c.get('landing') is not None]
        wrong = [c for c in landed if abs(c['errorPages']) > 1]
        print(f'{source}: {len(with_truth)} places, landed {len(landed)} ({len(landed) / max(1, len(with_truth)):.0%}),',
              f"same sentence {sum(c['sameSentence'] for c in landed)} ({sum(c['sameSentence'] for c in landed) / max(1, len(with_truth)):.0%} of places),",
              f'wrong place (over 1 page) {len(wrong)},',
              'error words median', fmt(med([abs(c['errorWords']) for c in landed]), 1), 'p90', fmt(q([abs(c['errorWords']) for c in landed], .9), 1),
              '| estimate error pages median', fmt(med([abs(c['estimateError']) for c in with_truth if c.get('estimateError') is not None])),
              'p90', fmt(q([abs(c['estimateError']) for c in with_truth if c.get('estimateError') is not None], .9)),
              '| radius', dict(collections.Counter(c.get('radiusPages') for c in landed)),
              '| search us median', fmt(med([c.get('searchUs') for c in cases]), 0), 'p90', fmt(q([c.get('searchUs') for c in cases], .9), 0))
    timing([r['window'] for r in data if r.get('window')], 'windows')
    by_book = collections.defaultdict(list)
    for r in data: by_book[r['book']].append(r.get('share', {}))
    for book, cases in by_book.items():
        landed = [c for c in cases if c.get('landing') is not None and c.get('truth') is not None]
        print(' ', book, len(cases), 'places, landed', len(landed), 'same sentence', sum(c['sameSentence'] for c in landed),
              'est. error p90 pages', fmt(q([abs(c['estimateError']) for c in cases if c.get('estimateError') is not None], .9), 1))


def text_to_audio(data, key=None):
    for source in ('share', 'chapter'):
        cases = [r[source] for r in data if source in r]
        if not cases: continue
        conv = [c for c in cases if c['converged']]
        err = [abs(c['errorMs']) / 1000 for c in conv]
        # Inside the sentence: from 0.5 s before its first word to its end.
        inside = [r for r in data if source in r and r[source]['converged'] and r.get('sentenceEndMs')
                  and r['truthMs'] - 500 <= r[source]['landingMs'] <= r['sentenceEndMs']]
        total = [sum(w['decodeMs'] + w['transcribeMs'] for w in c['windows']) + sum(s['searchUs'] for s in c['steps']) / 1000 for c in cases]
        cpu = [sum(w['transcribeCpuMs'] for w in c['windows']) for c in cases]
        print(f'{source}: {len(cases)} places, converged {len(conv)} ({len(conv) / len(cases):.0%}),',
              'rounds', dict(sorted(collections.Counter(c['rounds'] for c in cases).items())),
              '| error s median', fmt(med(err)), 'p90', fmt(q(err, .9)), 'max', fmt(max(err) if err else None),
              f'| within 1 s {sum(e <= 1 for e in err)}, inside the sentence {len(inside)}',
              '| estimate error s median', fmt(med([abs(c['estimateErrorMs']) / 1000 for c in cases]), 0),
              'p90', fmt(q([abs(c['estimateErrorMs']) / 1000 for c in cases], .9), 0),
              '| jump ms median', fmt(med(total), 0), 'p90', fmt(q(total, .9), 0),
              '| CPU ms median', fmt(med(cpu), 0), 'p90', fmt(q(cpu, .9), 0))
        failed = [c for c in cases if not c['converged']]
        for c in failed[:5]:
            print('   not converged: estimate error s', round(c['estimateErrorMs'] / 1000), 'steps', [(s['matched'], s['runnerUp'], s['confident']) for s in c['steps']])


def intro(data):
    confident = [r for r in data if r.get('confident')]
    print(len(data), 'windows 5 s into a section;', len(confident), 'confident')
    for r in data:
        print(' ', r['book'], r['section'], 'confident' if r.get('confident') else 'refused',
              'matched', r.get('matched'), 'of', r.get('heard'), 'runner-up', r.get('runnerUp'),
              'landing - first spoken word', r.get('errorWords'), 'first spoken at s', fmt((r.get('firstSpokenMs') or 0) / 1000, 1))


def windows(data):
    groups = collections.defaultdict(list)
    for r in data: groups[(r['model'], r['lengthMs'], r['ctx'] > 0)].append(r)
    for (model, length, reduced), cases in sorted(groups.items()):
        line = [f'{model} {length / 1000:.0f} s', 'reduced context' if reduced else 'full context', f'{len(cases)} windows']
        for scope in ('near', 'whole'):
            landed = [c[scope] for c in cases if c[scope].get('landing') is not None]
            right = [c for c in landed if abs(c['errorWords']) <= 5]
            wrong = [c for c in landed if abs(c['errorPages']) > 1]
            line.append(f'{scope}: landed {len(landed) / len(cases):.0%}, within 5 words {len(right) / len(cases):.0%}, wrong {len(wrong)}')
        line.append(f"words median {fmt(med([c['window']['words'] for c in cases]), 0)}")
        line.append(f"CPU ms median {fmt(med([c['window']['transcribeCpuMs'] for c in cases]), 0)} p90 {fmt(q([c['window']['transcribeCpuMs'] for c in cases], .9), 0)}")
        line.append(f"wall ms median {fmt(med([c['window']['transcribeMs'] for c in cases]), 0)}")
        print(' | '.join(line))


def server(data):
    for kind in ('sample', 'credits'):
        cases = [r for r in data if r['kind'] == kind]
        if not cases: continue
        refs = [r for r in cases if r['share'].get('truth') is not None]
        landed = [r['share'] for r in refs if r['share'].get('landing') is not None]
        print(f'{kind}: {len(cases)} places, reference found {len(refs)}, method landed {sum(r["share"].get("landing") is not None for r in cases)},',
              f'landed with reference {len(landed)}, same sentence {sum(c["sameSentence"] for c in landed)},',
              f'wrong (over 1 page) {sum(abs(c["errorPages"]) > 1 for c in landed)},',
              'error words median', fmt(med([abs(c['errorWords']) for c in landed]), 1), 'p90', fmt(q([abs(c['errorWords']) for c in landed], .9), 1),
              '| estimate error pages median', fmt(med([abs(r['share']['estimateError']) for r in refs])), 'p90', fmt(q([abs(r['share']['estimateError']) for r in refs], .9)),
              '| radius', dict(collections.Counter(c.get('radiusPages') for c in landed)))
        timing([r['share']['window'] for r in cases], f'  {kind} 15 s windows (fetch, decode and transcribe)')
    by_book = collections.defaultdict(list)
    for r in data: by_book[r['book']].append(r)
    for book, cases in sorted(by_book.items()):
        refs = [r for r in cases if r['share'].get('truth') is not None]
        landed = [r['share'] for r in refs if r['share'].get('landing') is not None]
        credits = [r for r in cases if r['kind'] == 'credits']
        print(' ', book, cases[0]['container'], len(cases), 'places, references', len(refs), 'landed', len(landed),
              'same sentence', sum(c['sameSentence'] for c in landed), 'wrong', sum(abs(c['errorPages']) > 1 for c in landed),
              'est. error p90 pages', fmt(q([abs(r['share']['estimateError']) for r in refs], .9), 1),
              'credits refused', sum(r['share'].get('landing') is None for r in credits), 'of', len(credits),
              'decode ms median', fmt(med([r['share']['window']['decodeMs'] for r in cases]), 0))
    t2a = [dict(r['textToAudio'], book=r['book']) for r in data if 'textToAudio' in r]
    if t2a:
        conv = [c for c in t2a if c['converged']]
        err = [abs(c['errorMs']) / 1000 for c in conv]
        total = [sum(w['decodeMs'] + w['transcribeMs'] for w in c['windows']) for c in t2a]
        print(f'text to audio: {len(t2a)} places, converged {len(conv)},', 'rounds', dict(sorted(collections.Counter(c['rounds'] for c in t2a).items())),
              '| error s median', fmt(med(err)), 'p90', fmt(q(err, .9)), 'max', fmt(max(err) if err else None),
              '| estimate error s median', fmt(med([abs(c['estimateErrorMs']) / 1000 for c in t2a]), 0), 'p90', fmt(q([abs(c['estimateErrorMs']) / 1000 for c in t2a], .9), 0),
              '| jump ms median', fmt(med(total), 0), 'p90', fmt(q(total, .9), 0))


def device(data):
    groups = collections.defaultdict(list)
    for r in data:
        if 'error' in r: print('error', r['label'], r['error'][:200]); continue
        groups[(r['label'], r['model'], r['lengthMs'], r['ctx'], r['threads'], r['source'].startswith('http'))].append(r)
    for (label, model, length, ctx, threads, http), cases in groups.items():
        landed = [c for c in cases if c.get('landing') is not None]
        right = [c for c in landed if c['truth'] is not None and abs(c['landing'] - c['truth']) <= 5]
        print(f'{label} {model} {length / 1000:.0f} s ctx {ctx} threads {threads} {"stream" if http else "file"}: {len(cases)} windows,',
              f'landed {len(landed)}, within 5 words {len(right)}',
              '| decode ms', fmt(med([c['decode']['wallMs'] for c in cases]), 0), fmt(q([c['decode']['wallMs'] for c in cases], .9), 0),
              '| transcribe ms', fmt(med([c['transcribeMs'] for c in cases]), 0), fmt(q([c['transcribeMs'] for c in cases], .9), 0),
              '| CPU ms', fmt(med([c['transcribeCpuMs'] for c in cases]), 0), fmt(q([c['transcribeCpuMs'] for c in cases], .9), 0),
              '| search us', fmt(med([c['search']['searchUs'] for c in cases]), 0), fmt(q([c['search']['searchUs'] for c in cases], .9), 0),
              '| model load ms', [c['modelLoadMs'] for c in cases if 'modelLoadMs' in c])


{'audio-to-text': audio_to_text, 'text-to-audio': text_to_audio, 'intro': intro, 'windows': windows,
 'server': server, 'device': device}[sys.argv[1]](list(rows(sys.argv[2:])))
