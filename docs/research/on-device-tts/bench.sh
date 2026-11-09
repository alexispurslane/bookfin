#!/bin/bash
# bench.sh NAME THREADS TEXTFILE OUTWAV -> one line: name threads elapsed audio rtf peakMB
S=$(cat /tmp/bookfin-tts-scripts/sherpa-path.txt)/bin/sherpa-onnx-offline-tts
D=/tmp/bookfin-tts-data/models
case $1 in
 kokoro) M=$D/kokoro-multi-lang-v1_0; A=(--kokoro-model=$M/model.onnx --kokoro-voices=$M/voices.bin --kokoro-tokens=$M/tokens.txt --kokoro-data-dir=$M/espeak-ng-data --kokoro-lexicon=$M/lexicon-us-en.txt --sid=3);;
 kokoro-int8) M=$D/kokoro-int8-multi-lang-v1_0; A=(--kokoro-model=$M/model.int8.onnx --kokoro-voices=$M/voices.bin --kokoro-tokens=$M/tokens.txt --kokoro-data-dir=$M/espeak-ng-data --kokoro-lexicon=$M/lexicon-us-en.txt --sid=3);;
 kitten-nano) M=$D/kitten-nano-en-v0_8-fp32; A=(--kitten-model=$M/model.fp32.onnx --kitten-voices=$M/voices.bin --kitten-tokens=$M/tokens.txt --kitten-data-dir=$M/espeak-ng-data --sid=0);;
 kitten-mini) M=$D/kitten-mini-en-v0_8; A=(--kitten-model=$M/model.onnx --kitten-voices=$M/voices.bin --kitten-tokens=$M/tokens.txt --kitten-data-dir=$M/espeak-ng-data --sid=0);;
 supertonic5|supertonic8) M=$D/sherpa-onnx-supertonic-3-tts-int8-2026-05-11; st=${1#supertonic}; A=(--supertonic-duration-predictor=$M/duration_predictor.int8.onnx --supertonic-text-encoder=$M/text_encoder.int8.onnx --supertonic-vector-estimator=$M/vector_estimator.int8.onnx --supertonic-vocoder=$M/vocoder.int8.onnx --supertonic-tts-json=$M/tts.json --supertonic-unicode-indexer=$M/unicode_indexer.bin --supertonic-voice-style=$M/voice.bin --lang=en --sid=0 --num-steps=$st);;
 pocket|pocket-int8) if [ $1 = pocket ]; then M=$D/sherpa-onnx-pocket-tts-2026-01-26; s=""; else M=$D/sherpa-onnx-pocket-tts-int8-2026-01-26; s=".int8"; fi; A=(--pocket-lm-main=$M/lm_main$s.onnx --pocket-lm-flow=$M/lm_flow$s.onnx --pocket-decoder=$M/decoder$s.onnx --pocket-encoder=$M/encoder.onnx --pocket-text-conditioner=$M/text_conditioner.onnx --pocket-vocab-json=$M/vocab.json --pocket-token-scores-json=$M/token_scores.json --reference-audio=$M/test_wavs/bria.wav);;
 piper) M=$D/vits-piper-en_US-libritts_r-medium; A=(--vits-model=$M/en_US-libritts_r-medium.onnx --vits-tokens=$M/tokens.txt --vits-data-dir=$M/espeak-ng-data --sid=0);;
esac
out=$( { /usr/bin/time -l "$S" "${A[@]}" --num-threads=$2 --output-filename="$4" "$(cat $3)" ; } 2>&1 )
el=$(echo "$out" | sed -n 's/^Elapsed seconds: \([0-9.]*\).*/\1/p')
au=$(echo "$out" | sed -n 's/^Audio duration: \([0-9.]*\).*/\1/p')
pk=$(echo "$out" | awk '/peak memory footprint/{printf "%d", $1/1048576}')
rt=$(echo "$out" | awk '/ real /{print $1}')
echo "$1 t=$2 gen=${el}s audio=${au}s rtf=$(echo "scale=3; $el/$au" | bc) wall=${rt}s peakMB=$pk"
