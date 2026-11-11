import unittest

from tables import DRAWN, PREPARED, book_table, mean_table


def summary():
    def cell(engine, book, operation, median, p90, count, mean=0):
        return {"engine": engine, "book": book, "operation": operation, "median_ms": median,
                "p90_ms": p90, "count": count, "mean_ms": mean}
    return {"intervals": {
        "drawn_page": {
            "cells": [cell("koreader", "long", "font_change", 116.04, 124.0, 36)],
            "equal_book_means": [{"engine": "koreader", "operation": "font_change", "mean_ms": 73.45}]},
        "prepared_page": {
            "cells": [cell("bookfin", "prose", "page_turn", 0.84, 1.26, 36),
                      cell("webview", "prose", "page_turn", 25.04, 31.0, 35)],
            "equal_book_means": [{"engine": "bookfin", "operation": "page_turn", "mean_ms": 1.25},
                                 {"engine": "webview", "operation": "page_turn", "mean_ms": 30.04999}]},
        "koreader_before_draw": {
            "cells": [cell("koreader", "prose", "page_turn", 0.12, 0.2, 36)],
            "equal_book_means": [{"engine": "koreader", "operation": "page_turn", "mean_ms": 0.1249}]}}}


class TablesTest(unittest.TestCase):
    def test_mean_table_rounds_only_the_final_equal_book_mean(self):
        rows = mean_table(summary(), PREPARED).splitlines()
        turn = next(row for row in rows if row.startswith("| Page turn"))
        self.assertEqual(turn, "| Page turn | 1.3 | 30.0 | n/a | 0.1 |")

    def test_book_table_reports_median_p90_and_count_and_marks_missing_cells(self):
        rows = book_table(summary(), PREPARED).splitlines()
        webview = next(row for row in rows if row.startswith("| WebView | Page turn"))
        self.assertEqual(webview, "| WebView | Page turn | 25.0 / 31.0 (35) | n/a | n/a |")
        before = next(row for row in rows if row.startswith("| KOReader before drawing | Page turn"))
        self.assertEqual(before, "| KOReader before drawing | Page turn | 0.1 / 0.2 (36) | n/a | n/a |")

    def test_headline_tables_use_each_engine_drawn_page(self):
        means = mean_table(summary(), DRAWN).splitlines()
        self.assertEqual(means[0], "| Action | Bookfin | WebView | KOReader |")
        self.assertEqual(next(row for row in means if row.startswith("| Size change")),
                         "| Size change | n/a | n/a | 73.5 |")
        books = book_table(summary(), DRAWN).splitlines()
        self.assertEqual(next(row for row in books if row.startswith("| KOReader | Size change")),
                         "| KOReader | Size change | n/a | 116.0 / 124.0 (36) | n/a |")


if __name__ == "__main__":
    unittest.main()
