"""Compares runs of test/reader/epub/corpus_prepare_test.dart.

Tool code. It is not part of Bookfin.

Usage, from the repository root:

    python3 -I tool/reader/compare_corpus_prepare.py \
        --before before-1 before-2 --after after-1 after-2

Each name is a run in .cache/epub-corpus/prepare/<name>.json. The first
run of each side gives the hashes; every run of a side must have the same
hashes. The script prints each section whose prepared section differs
between the sides, and then the prepare times: for each section, the
median over the runs of a side. Alternate the runs of the two sides, so
that the load of the shared machine affects both in the same way.
"""

import argparse
import json
import pathlib
import statistics
import sys

SLOW = [
    ("pg-10681-rogets-thesaurus", "1"),
    ("se-dialogues", "30"),
    ("se-poetry", "2"),
    ("se-van-dyke-poetry", "2"),
]


def load(name):
    path = pathlib.Path(".cache/epub-corpus/prepare") / f"{name}.json"
    return json.loads(path.read_text())


def differences(first, second):
    """The places where two runs prepared something else."""
    found = []
    for book in sorted(set(first) | set(second)):
        if book not in first or book not in second:
            found.append(f"{book}: only in one run")
            continue
        a, b = first[book], second[book]
        if a["mainTextSize"] != b["mainTextSize"]:
            found.append(f"{book}: main text size {a['mainTextSize']} / {b['mainTextSize']}")
        if a["shownMainTextSize"] != b["shownMainTextSize"]:
            found.append(f"{book}: shown main text size differs")
        for settings in sorted(set(a["sections"]) | set(b["sections"])):
            sa = a["sections"].get(settings, {})
            sb = b["sections"].get(settings, {})
            for section in sorted(set(sa) | set(sb), key=int):
                if sa.get(section) != sb.get(section):
                    found.append(
                        f"{book} {settings} section {section}: "
                        f"{sa.get(section, 'missing')[:80]} / "
                        f"{sb.get(section, 'missing')[:80]}"
                    )
    return found


def times(runs):
    """For each (book, section), the median time over runs."""
    keys = set()
    for run in runs:
        for book, found in run.items():
            for section in found["prepareMs"]:
                keys.add((book, section))
    result = {}
    for key in keys:
        values = [
            run[key[0]]["prepareMs"][key[1]]
            for run in runs
            if key[0] in run and key[1] in run[key[0]]["prepareMs"]
        ]
        values = [value for value in values if value is not None]
        if values:
            result[key] = statistics.median(values)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--before", nargs="+", required=True)
    parser.add_argument("--after", nargs="+", required=True)
    args = parser.parse_args()
    before = [load(name) for name in args.before]
    after = [load(name) for name in args.after]

    same = True
    for side, runs in (("before", before), ("after", after)):
        for index, run in enumerate(runs[1:], 1):
            for line in differences(runs[0], run):
                same = False
                print(f"{side} run {index} differs from run 0: {line}")
    found = differences(before[0], after[0])
    for line in found:
        print(f"differs: {line}")
    print(f"{len(found)} differences between before and after")
    if found:
        same = False

    tb, ta = times(before), times(after)
    common = sorted(set(tb) & set(ta))
    print()
    print("section                              before ms   after ms   after/before")
    for key in SLOW:
        if key in tb and key in ta:
            print(
                f"{key[0] + ' ' + key[1]:36} {tb[key]:9.1f} {ta[key]:10.1f} "
                f"{ta[key] / tb[key]:10.2f}"
            )
    big = [key for key in common if tb[key] >= 10]
    print()
    print(f"sections: {len(common)}, of them {len(big)} with a prepare of 10 ms or more before")
    print(
        f"median section before {statistics.median(tb[k] for k in common):.2f} ms, "
        f"after {statistics.median(ta[k] for k in common):.2f} ms"
    )
    print(
        f"median ratio after/before, all sections: "
        f"{statistics.median(ta[k] / tb[k] for k in common if tb[k] > 0):.2f}"
    )
    if big:
        print(
            f"median ratio after/before, sections of 10 ms or more: "
            f"{statistics.median(ta[k] / tb[k] for k in big):.2f}"
        )
    books = sorted({key[0] for key in common})
    book_before = {b: sum(tb[k] for k in common if k[0] == b) for b in books}
    book_after = {b: sum(ta[k] for k in common if k[0] == b) for b in books}
    print(
        f"median book (all sections) before {statistics.median(book_before.values()):.1f} ms, "
        f"after {statistics.median(book_after.values()):.1f} ms, "
        f"median ratio {statistics.median(book_after[b] / book_before[b] for b in books):.2f}"
    )
    print(
        f"corpus total before {sum(book_before.values()):.0f} ms, "
        f"after {sum(book_after.values()):.0f} ms"
    )
    return 0 if same else 1


if __name__ == "__main__":
    sys.exit(main())
