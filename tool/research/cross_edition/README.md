# Cross-edition place measurement

Tool code for the design of boo-z3is (`docs/plans/cross-edition-places.md`). It is not part of Bookfin. It measures two things:

- How well audiobook chapter lists match ebook contents, and how far proportional placement inside matched chapters lands from the true place (design A).
- Whether a short on-device transcription of an audio window finds its words in the ebook, and what it costs on the CPU (design B).

The audio data is public: LibriVox section lists (title, length, readers) and three LibriVox chapter recordings. The ebooks are the public-domain EPUB corpus of `tool/reader/epub_corpus.json`. Nothing reads the Jellyfin server.

## Run the chapter measurement

1. Fetch the EPUB corpus with `tool/reader/fetch_epub_corpus.py`. The books go to `.cache/epub-corpus/books`.
2. Get `results.json` of a corpus run (`.cache/epub-corpus/results.json`). The measurement reads the pages and the visible characters of each book at 412 × 671 px with 20 px text from it.
3. Fetch the LibriVox section lists:

   ```sh
   python3 -I tool/research/cross_edition/fetch_librivox.py .cache/cross-edition/librivox
   ```

4. Match and measure:

   ```sh
   python3 -I tool/research/cross_edition/measure.py .cache/epub-corpus/books .cache/cross-edition/librivox .cache/epub-corpus/results.json .cache/cross-edition/rows.json
   python3 -I tool/research/cross_edition/aggregate.py .cache/cross-edition/rows.json
   ```

## Run the speech probe

1. Build whisper.cpp and ffmpeg from nixpkgs: `nix build nixpkgs#whisper-cpp nixpkgs#ffmpeg-headless`.
2. Download `ggml-tiny.en.bin` and `ggml-base.en.bin` from the `ggerganov/whisper.cpp` repository on Hugging Face into a models folder.
3. Download three LibriVox chapters into an audio folder. The LibriVox API gives each section's `listen_url`.
   - `pp03.mp3`: chapter 3 of recording 1480 (Pride and Prejudice).
   - `md05.mp3`: chapter 3 of recording 21919 (Moby Dick).
   - `je04.mp3`: chapter 4 of recording 2192 (Jane Eyre).
4. Run the probe. It transcribes 15 s at 20, 40, 60 and 80 percent of each chapter with both models:

   ```sh
   python3 -I tool/research/cross_edition/align_probe.py <ffmpeg> <whisper-cli> <models> <windows> <audio> .cache/epub-corpus/books .cache/epub-corpus/results.json .cache/cross-edition/align_rows.json
   ```

The probe uses the Mac's GPU unless whisper-cli gets `-ng`. The CPU timings of the design doc came from separate `whisper-cli -ng -t 4` and `-t 2` runs.

## Run the speech search prototype (boo-snng)

The prototype of `docs/plans/cross-edition-places.md`, "Speech search prototype". It places a listening place in the ebook, and a reading place in the audiobook, with whisper.cpp and a word search. Run every command in the speech shell, `nix develop .#speech`. That shell sets `BOOKFIN_WHISPER_SOURCE` (whisper.cpp 1.9.5), `BOOKFIN_WHISPER_HOST` (whisper-cli with Metal) and `BOOKFIN_WHISPER_MODELS` (tiny.en and base.en at 16, 8 and 5 bits), all pinned in `nix/whisper.nix`. `W` below is a work folder outside the repository, for example `~/.cache/bookfin/boo-snng`.

1. Fetch the recordings. Whole books for the listening tests, and some sections of long books:

   ```sh
   python3 -I tool/research/cross_edition/fetch_speech_audio.py $W/audio time-machine:5630:all heart-of-darkness:64:all alice:900:all pride-and-prejudice:1480:all moby-dick:21919:all jane-eyre:2192:all
   ```

2. Make the word list of each book. Copy each corpus EPUB from `.cache/epub-corpus/books` first. For example, `speech_book.py $W/corpus/se-the-time-machine.epub $W/books/time-machine.json`.
3. Make the reference maps with base.en on the Mac's GPU. This takes about 1 min per 45 min of audio:

   ```sh
   python3 -I tool/research/cross_edition/speech_truth.py $(which ffmpeg) $BOOKFIN_WHISPER_HOST/bin/whisper-cli $BOOKFIN_WHISPER_MODELS $W/audio $W/books $W/truth alice time-machine heart-of-darkness pride-and-prejudice:9,21,33,45,55 moby-dick:20,48,76,103,124 jane-eyre:6,13,21,28,34
   ```

4. Build the probe library for the Mac. It is the same CPU-only build as on Android:

   ```sh
   cmake -S tool/research/cross_edition/speech_probe/native -B $W/build-host -G Ninja -DCMAKE_BUILD_TYPE=Release && ninja -C $W/build-host speech_probe
   ```

5. Run the experiments from `tool/research/cross_edition/speech_probe` after `flutter pub get`. Each one appends JSON lines:

   ```sh
   dart run bin/host_eval.dart $W audio-to-text $W/out/a2t.jsonl count=40
   dart run bin/host_eval.dart $W text-to-audio $W/out/t2a.jsonl count=25
   dart run bin/host_eval.dart $W intro $W/out/intro.jsonl
   dart run bin/host_eval.dart $W windows $W/out/windows.jsonl count=25 reduced=true
   ```

6. Summarize them with `speech_report.py <experiment> <rows.jsonl>`, and simulate the anchor map with `speech_anchor_map.py $W $W/out/anchor_map.json <book> ...`.

The server experiment reads recordings of the user's Jellyfin server. `speech_server.py find` writes a private map of letters to items into `$W/server`. `speech_server.py proxy` then serves them on 127.0.0.1 with byte ranges, so ffmpeg and the emulator read only the windows. Both read the address and the key from `BOOKFIN_SERVER_HOST` and `BOOKFIN_SERVER_KEY`. Delete `$W/server` after the run.

The Android harness is the Flutter app in `speech_probe`. Build it with `flutter build apk --release` in the speech shell. Push the models, the books and the audio to `/storage/emulated/0/Android/data/dev.bookfin.speech_probe/files/`, write `plan.json` there with `speech_device_plan.py`, and open the app. It appends to `results.jsonl` in the same folder. `speech_range_server.py` serves the audio folder for the streaming jobs, through `adb reverse`.
