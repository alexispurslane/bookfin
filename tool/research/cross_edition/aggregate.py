# Tool code for the boo-z3is design measurement, not part of Bookfin.
# Summarizes the rows that measure.py wrote. Usage: aggregate.py <rows.json>
import json, math, statistics, collections, sys
rows = json.load(open(sys.argv[1]))
def pct(v, q):
    v = sorted(v)
    if not v: return float('nan')
    k = (len(v) - 1) * q; f, c = math.floor(k), math.ceil(k)
    return v[f] + (v[c] - v[f]) * (k - f)
print('pairs', len(rows), 'recordings', len({r['librivox'] for r in rows}), 'works', len({r['work'] for r in rows}), 'ebook editions', len({r['ebook'] for r in rows}))
print('solo pairs', sum(r['solo'] for r in rows))
# Title matching
share_title = [r['title_anchors'] / r['sections'] for r in rows]
share_all = [r['anchors'] / r['sections'] for r in rows]
print('title-anchored share of sections: p10 %.2f p25 %.2f p50 %.2f' % (pct(share_title, .1), pct(share_title, .25), pct(share_title, .5)))
print('pairs with >=90%% sections title-anchored: %d of %d' % (sum(x >= .9 for x in share_title), len(rows)))
print('pairs with >=90%% sections anchored after ordinal fill: %d' % sum(x >= .9 for x in share_all))
print('pairs with <50%% anchored after fill: %d' % sum(x < .5 for x in share_all))
print('pairs with no anchor: %d' % sum(r['anchors'] == 0 for r in rows))
print('pairs needing validation drops: %d' % sum(r['dropped'] > 0 for r in rows))
# Counts
eq = sum(r['sections'] == r['chapter_entries'] for r in rows if r['chapter_entries'])
fewer = sum(r['sections'] < r['chapter_entries'] for r in rows if r['chapter_entries'])
more = sum(r['sections'] > r['chapter_entries'] for r in rows if r['chapter_entries'])
print('section count vs chapter-level entries: equal %d fewer %d more %d' % (eq, fewer, more))
print('recordings with merged sections (ranges):', len({r['librivox'] for r in rows if r['ranges'] > 0}))
# Front matter before the first anchor
front = [1 - r['anchored_time_share'] for r in rows if r['anchors']]
print('audio time before first anchor share: p50 %.3f p90 %.3f' % (pct(front, .5), pct(front, .9)))
rates = [r['rate'] for r in rows if r['rate']]
print('rate chars/s: p10 %.1f p50 %.1f p90 %.1f' % (pct(rates, .1), pct(rates, .5), pct(rates, .9)))
per_page = [r['per_page'] for r in rows]
print('chars per page p50 %.0f' % pct(per_page, .5))
for label, filt in (('all', lambda r: True), ('solo', lambda r: r['solo']), ('group', lambda r: not r['solo'])):
    sel = [r for r in rows if filt(r) and r['title_anchors'] >= 5]
    W = [x for r in sel for x in r['whole']]
    E = [x for r in sel for x in r['ends']]
    L = [x for r in sel for x in r['loo']]
    LS = [x for r in sel for x in r['loo_s']]
    LR = [x for r in sel for x in r['loo_rel']]
    SP = [x for r in sel for x in r['loo_span']]
    print(f"{label:5} pairs {len(sel):3} anchors {len(W):5} | whole-book p50 {pct(W,.5):5.1f} p90 {pct(W,.9):5.1f} pages | ends-only p50 {pct(E,.5):5.1f} p90 {pct(E,.9):5.1f} | chapter p50 {pct(L,.5):4.2f} p90 {pct(L,.9):4.2f} pages, {pct(LS,.5):4.0f} s / {pct(LS,.9):4.0f} s | rel p50 {pct(LR,.5):.3f} p90 {pct(LR,.9):.3f} | span p50 {pct(SP,.5):.1f} pages")
