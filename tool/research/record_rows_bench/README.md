# record_rows_bench

This app measures the cost of reading the personal-record rows of a large account with sqflite on Android (ticket tf-0nvi). Its application ID is `dev.bookfin.bench.record_rows_bench`, so it never touches the data of the Bookfin app.

It writes a record file with the schema of `lib/playback/database.dart`. Then it reads the rows of the account in six ways and prints one `BENCH` line for each to the log:

1. `main`: the read of `RecordDatabase.rows` on the UI isolate, as Bookfin does it now.
2. `codec`: only the decode of a reply of the same size by `StandardMethodCodec`, on the UI isolate.
3. `worker`: the same read in a background isolate through `BackgroundIsolateBinaryMessenger`, on the connection that the UI isolate holds (`singleInstance: true`), without a transaction.
4. `workerOwn`: the same read in a background isolate on a read-only connection of its own (`singleInstance: false`), then closed. Its four queries call `transaction`, but sqflite sends no `BEGIN` on a read-only connection, so each query reads its own snapshot. Bookfin's reader reads in one statement instead.

5. `recordMain`: `RecordDatabase.rows` of Bookfin itself (through the link `lib/bookfin`, which points to the `lib` directory of the repository) on the UI isolate, in a WAL file that `RecordDatabase` wrote.
6. `recordWorker`: what the store does for a large account. `RecordDatabase.actionCount` runs on the UI isolate, then `RecordDatabase.reader` reads in a background isolate.

After the runs of each size, two `check` lines report what a read through `RecordDatabase.reader` sees. `walVisible` says that a commit of the UI isolate's connection that is still in the write-ahead log is in the read. The second line starts a read, commits one action on the UI isolate's connection during it, and reports that the read holds one snapshot and that a later read holds every action.

For each way, `ms` is the wall time of the read, and `stallMs` is the longest time that the UI isolate could not run a 1 ms timer during the read.

Run it as an integration test in profile mode through the dev shell of the repository. Replace `emulator-5556` with the device ID that T3 returns.

```
nix develop --command bash -c 'cd tool/research/record_rows_bench && flutter drive --profile -d emulator-5556 --driver=test_driver/integration_test.dart --target=integration_test/bench_test.dart' | grep BENCH
```

You can also build the app with `flutter build apk --release`, install it, start it with the T3 device tools, and read the `BENCH` lines with `adb logcat`.
