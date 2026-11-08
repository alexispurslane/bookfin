# record_hop_bench

This program measures when a hop to another isolate costs the UI isolate less than the work of the record store itself (ticket t3-kc92). The limits `_hopItems` and `_hopText` in `lib/playback/store.dart` come from its results.

The record store imports Flutter, so `dart compile exe` cannot build it. `generate.py` copies the code that a record-store hop runs into `gen/`, unchanged, and replaces only the imports that need Flutter. `bench.dart` then times three kinds of work, inline and through `Isolate.run`, as `compute` runs it:

1. `rows`: the restore of an account from its rows: decode, journal replay and both views.
2. `views`: the views of a cached account from the current versions of its records.
3. `text`: the restore of a saved text in the format before the journal.

Each number is the median of 201 runs, in microseconds of time on the calling isolate. For a hop, that time is the synchronous start of `Isolate.run`, which copies the input, plus the time from the worker's end to the caller's resumption.

Run it from the root of the repository through the dev shell:

```
nix develop --command bash -c 'cd tool/research/record_hop_bench && python3 generate.py && dart compile exe bench.dart -o /tmp/record_hop_bench && /tmp/record_hop_bench'
```

Results on an M-series Mac, November 7, 2026, three runs that agreed within 2 µs:

```
A saved text without records, by length in characters:
chars  text-inline text-hop
    2            9        9
   13            9        9
   43           10        9
   70           11        9

items  chars  rows-inline rows-hop  views-inline views-hop  text-inline text-hop
    0    111            9        9             6         8           12        9
    1    216           27       10            12         9           35       11
    2    480           50       12            21        11           65       13
    4   1010           88       15            30        12          125       17
    8   2070          159       19            50        16          249       24
   16   4209          326       25            85        22          483       33
```

A hop pays from the first action or record, and from a text of about 32 characters.
