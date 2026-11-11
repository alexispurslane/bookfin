BOOKS = ("prose", "long", "illustrated")
ENGINES = ("bookfin", "webview", "koreader")


def schedule(rounds=12):
    if type(rounds) is not int or rounds < 3 or rounds % 3:
        raise ValueError("rounds must be a positive multiple of three")
    jobs = []
    for round_index in range(rounds):
        for book_order in range(3):
            book = BOOKS[(book_order + round_index) % 3]
            for engine_order in range(3):
                engine = ENGINES[(engine_order + round_index + BOOKS.index(book)) % 3]
                jobs.append({
                    "run_id": f"round-{round_index:02d}-{book}-{engine}",
                    "round": round_index, "book": book, "engine": engine,
                    "engine_order": engine_order, "book_order": book_order,
                })
    return jobs


if __name__ == "__main__":
    import json

    print(json.dumps(schedule(), indent=2))
