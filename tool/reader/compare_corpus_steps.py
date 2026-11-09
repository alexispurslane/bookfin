"""Compares two runs of test/reader/epub/corpus_steps_test.dart.

Tool code for the on-demand corpus runs. It is not part of Bookfin.

From the repository root, after two runs named before and after:

    python3 -I tool/reader/compare_corpus_steps.py before after

It prints the longest step and the longest unit of work of each book and
page settings in both runs, and then each section whose pages differ, with
the first page that differs. With --lines, it compares the line hashes,
which leave out the paragraph pieces that draw the lines.
"""

import json
import sys
from pathlib import Path


def load(name):
    path = Path('.cache/epub-corpus/steps') / f'{name}.json'
    return json.loads(path.read_text())


def main():
    arguments = [each for each in sys.argv[1:] if each != '--lines']
    key = 'lines' if '--lines' in sys.argv else 'pages'
    if len(arguments) != 2:
        sys.exit('usage: compare_corpus_steps.py [--lines] <before> <after>')
    before, after = load(arguments[0]), load(arguments[1])
    books = [book for book in before if book in after]
    print('book\tsettings\tstep before\tstep after\tunit before\t'
          'unit after\twhere after')
    for book in books:
        for settings, old in before[book].items():
            new = after[book].get(settings)
            if new is None:
                continue
            print(f"{book}\t{settings}\t{old['longestStepMs']:.1f}\t"
                  f"{new['longestStepMs']:.1f}\t{old['longestUnitMs']:.1f}\t"
                  f"{new['longestUnitMs']:.1f}\t{new.get('unitWhere', '')}")
    changed = 0
    total = 0
    for book in books:
        for settings, old in before[book].items():
            new = after[book].get(settings)
            if new is None:
                continue
            for section, pages in old[key].items():
                total += 1
                other = new[key].get(section)
                if other == pages:
                    continue
                changed += 1
                first = next(
                    (index for index, (a, b) in enumerate(zip(pages, other))
                     if a != b),
                    min(len(pages), len(other)))
                print(f'differs: {book} {settings} section {section}, '
                      f'page {first} of {len(pages)} before and '
                      f'{len(other)} after')
    print(f'{changed} of {total} section layouts differ')


if __name__ == '__main__':
    main()
