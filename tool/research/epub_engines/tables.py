"""Markdown tables of the engine intervals in a collected summary.json."""
from decimal import ROUND_HALF_UP, Decimal
import json

BOOKS = ("prose", "long", "illustrated")
ACTIONS = (("fresh_open", "Fresh open"), ("cached_reopen", "Cached reopen"),
           ("page_turn", "Page turn"), ("chapter_crossing", "Chapter turn (visited)"),
           ("font_change", "Size change"))
# Each column is an engine's interval: (label, interval name, engine).
DRAWN = (("Bookfin", "drawn_page", "bookfin"), ("WebView", "drawn_page", "webview"),
         ("KOReader", "drawn_page", "koreader"))
PREPARED = (("Bookfin", "prepared_page", "bookfin"), ("WebView", "prepared_page", "webview"),
            ("KOReader", "prepared_page", "koreader"),
            ("KOReader before drawing", "koreader_before_draw", "koreader"))


def _ms(value):
    """Milliseconds to one decimal place, with halves rounded away from zero."""
    if value is None:
        return "n/a"
    return str(Decimal(repr(value)).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP))


def mean_table(summary, columns):
    rows = ["| Action | " + " | ".join(label for label, _, _ in columns) + " |",
            "| --- |" + " ---: |" * len(columns)]
    for operation, action in ACTIONS:
        values = []
        for _, interval, engine in columns:
            means = summary["intervals"][interval]["equal_book_means"]
            values.append(_ms(next((mean["mean_ms"] for mean in means
                                    if mean["engine"] == engine and mean["operation"] == operation), None)))
        rows.append(f"| {action} | " + " | ".join(values) + " |")
    return "\n".join(rows)


def book_table(summary, columns):
    rows = ["| Interval | Action | " + " | ".join(BOOKS) + " |", "| --- | --- |" + " ---: |" * len(BOOKS)]
    for label, interval, engine in columns:
        cells = summary["intervals"][interval]["cells"]
        for operation, action in ACTIONS:
            values = []
            for book in BOOKS:
                cell = next((cell for cell in cells if (cell["engine"], cell["book"], cell["operation"])
                             == (engine, book, operation)), None)
                values.append("n/a" if cell is None else
                              f'{_ms(cell["median_ms"])} / {_ms(cell["p90_ms"])} ({cell["count"]})')
            rows.append(f"| {label} | {action} | " + " | ".join(values) + " |")
    return "\n".join(rows)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("summary")
    parser.add_argument("intervals", nargs="+", choices=("drawn", "prepared"))
    arguments = parser.parse_args()
    with open(arguments.summary) as source:
        loaded = json.load(source)
    tables = {"drawn": DRAWN, "prepared": PREPARED}
    for name in arguments.intervals:
        print(f"## {name}\n\n" + mean_table(loaded, tables[name]) + "\n\n"
              + book_table(loaded, tables[name]) + "\n")
