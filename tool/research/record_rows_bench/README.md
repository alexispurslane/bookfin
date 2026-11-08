# record_rows_bench

This app measures the cost of reading the personal-record rows of a large account with sqflite on Android (ticket tf-0nvi). Its application ID is `dev.bookfin.bench.record_rows_bench`, so it never touches the data of the Bookfin app.

It writes a record file with the schema of `lib/playback/database.dart`. Then it reads the rows of the account in three ways and prints one `BENCH` line for each to the log:

1. `main`: the read of `RecordDatabase.rows` on the UI isolate, as Bookfin does it now.
2. `codec`: only the decode of a reply of the same size by `StandardMethodCodec`, on the UI isolate.
3. `worker`: the same read in a background isolate through `BackgroundIsolateBinaryMessenger`, on the connection that the UI isolate holds (`singleInstance: true`), without a transaction.
4. `workerOwn`: the same read in a background isolate on a read-only connection of its own (`singleInstance: false`), in a transaction, then closed.

For each way, `ms` is the wall time of the read, and `stallMs` is the longest time that the UI isolate could not run a 1 ms timer during the read.

Run it as an integration test in profile mode through the dev shell of the repository. Replace `emulator-5556` with the device ID that T3 returns.

```
nix develop --command bash -c 'cd tool/research/record_rows_bench && flutter drive --profile -d emulator-5556 --driver=test_driver/integration_test.dart --target=integration_test/bench_test.dart' | grep BENCH
```

You can also build the app with `flutter build apk --release`, install it, start it with the T3 device tools, and read the `BENCH` lines with `adb logcat`.
