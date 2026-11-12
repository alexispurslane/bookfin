BOOKS = ("prose", "long", "illustrated")
ENGINES = ("bookfin", "webview", "koreader")


def workload():
    steps = []

    def add(operation, case, measured=False):
        steps.append({"operation": operation, "case": case, "measured": measured})

    add("fresh_open", "target18", True)
    add("paginate", "target18")
    for repeat in range(3):
        add("prepare_reopen", "after_crossing18")
        add("cached_reopen", "target18", True)
    for repeat in range(3):
        add("page_turn", f"turn{repeat+1}", True)
    for repeat in range(3):
        add("prepare_crossing", "before_crossing18")
        add("chapter_crossing", "after_crossing18", True)
    for repeat in range(3):
        add("prepare_target", "target18")
        add("font_change", "target20", True)
    return steps


# A Bookfin process whose book Bookfin prepared at download, as the app does
# when a download completes (boo-sy2d). It runs only the fresh open, which
# must be the first open of a new process, as the cold fresh open is.
PREPARED_AT_DOWNLOAD = "prepared_at_download"


def schedule(rounds=12):
    """The balanced schedule. Each round and book has the three engines'
    standard processes, with the ids and order of the earlier runs, and one
    Bookfin process prepared at download. That process takes each of the
    four places in a book's group three times in twelve rounds."""
    if type(rounds) is not int or rounds < 3 or rounds % 3:
        raise ValueError("rounds must be a positive multiple of three")
    jobs = []
    for round_index in range(rounds):
        for book_order in range(3):
            book = BOOKS[(book_order + round_index) % 3]
            group = []
            for engine_order in range(3):
                engine = ENGINES[(engine_order + round_index + BOOKS.index(book)) % 3]
                group.append({
                    "run_id": f"round-{round_index:02d}-{book}-{engine}",
                    "round": round_index, "book": book, "engine": engine,
                    "engine_order": engine_order, "book_order": book_order,
                    "steps": workload(),
                })
            place = (round_index + BOOKS.index(book)) % 4
            group.insert(place, {
                "run_id": f"round-{round_index:02d}-{book}-bookfin-prepared",
                "round": round_index, "book": book, "engine": "bookfin",
                "variant": PREPARED_AT_DOWNLOAD, "place": place, "book_order": book_order,
                "steps": workload()[:1],
            })
            jobs.extend(group)
    return jobs


if __name__ == "__main__":
    import json

    print(json.dumps(schedule(), indent=2))
