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
