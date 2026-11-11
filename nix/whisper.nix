{ pkgs }:
# whisper.cpp for Bookfin's speech search (boo-vh77, native/speech) and for
# the speech prototype of boo-snng (tool/research/cross_edition/speech_probe).
let
  # The commit of the ggerganov/whisper.cpp model repository on Hugging Face.
  revision = "5359861c739e955e79d9a303bcbc70fb988958b1";
  model =
    name: sha256:
    pkgs.fetchurl {
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/${revision}/ggml-${name}.bin";
      inherit sha256;
    };
  # whisper.cpp 1.9.5 of the pinned nixpkgs. The source carries its own
  # ggml, so the Android, host and probe builds use the same code.
  source = pkgs.whisper-cpp.src;
  # The model that the app bundles: tiny.en at 5 bits, 32 MB
  # (docs/plans/cross-edition-places.md, "Decision on speech search").
  # tool/reader/speech_package.py pins its SHA-256 too.
  bundledModel = model "tiny.en-q5_1" "0avwdkk937kh9xnmsfvbi1bl3pdxdia1pwj7gmmrpw6fy5k5fz67";
in
{
  inherit source bundledModel;
  # bookfin_speech for the machine of the dev shell, so that tests run
  # whisper and the window decoder. The macOS app does not bundle it yet
  # (t2-0kl0).
  hostLibrary = pkgs.stdenv.mkDerivation {
    pname = "bookfin-speech-host";
    version = "1.9.5";
    src = ../native/speech;
    nativeBuildInputs = [ pkgs.cmake ];
    cmakeFlags = [
      "-DWHISPER_SOURCE=${source}"
      "-DCMAKE_BUILD_TYPE=Release"
    ];
    buildPhase = "cmake --build . --target bookfin_speech --parallel 4";
    installPhase = ''
      mkdir -p "$out/lib"
      cp libbookfin_speech${pkgs.stdenv.hostPlatform.extensions.sharedLibrary} "$out/lib/"
    '';
  };
  # whisper-cli with Metal, for the reference transcripts on the Mac.
  host = pkgs.whisper-cpp;
  models = pkgs.linkFarm "whisper-models" [
    {
      name = "ggml-tiny.en.bin";
      path = model "tiny.en" "07qbja4m5isssw42prv227gbyrf3nsjms6h8rlyrkpbgd3w4q7lj";
    }
    {
      name = "ggml-tiny.en-q5_1.bin";
      path = bundledModel;
    }
    {
      name = "ggml-tiny.en-q8_0.bin";
      path = model "tiny.en-q8_0" "156xny5h2v8cxkf0iji0n33i5kz7rhgmw2dvwz3a8ld11a3b7hjv";
    }
    {
      name = "ggml-base.en.bin";
      path = model "base.en" "00nhqqvgwyl9zgyy7vk9i3n017q2wlncp5p7ymsk0cpkdp47jdx0";
    }
    {
      name = "ggml-base.en-q5_1.bin";
      path = model "base.en-q5_1" "0byx5w75s6fg1ph69w4y5xycfnh006fgvyl15fx4fhkw1pfp1bsb";
    }
    {
      name = "ggml-base.en-q8_0.bin";
      path = model "base.en-q8_0" "0zn8z0s9l321x12sszbascvqv9n4vgi3mpqrgvykrqbmh1va1m54";
    }
  ];
}
