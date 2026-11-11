{ pkgs }:
let
  koreader = pkgs.fetchurl {
    url = "https://github.com/koreader/koreader/releases/download/v2026.07.1/koreader-android-arm64-v2026.07.1.apk";
    sha256 = "89cecbe06eacd2ff7d91e37152d6beeb52809f2ca38060b6515ed8b00d152412";
  };
  epubjs = pkgs.fetchurl {
    url = "https://registry.npmjs.org/epubjs/-/epubjs-0.3.93.tgz";
    sha256 = "180b33059ca15e2b4f129eb7fef6cae0bf6005c02af5194d13e5cb48378d538f";
  };
  jszip = pkgs.fetchurl {
    url = "https://registry.npmjs.org/jszip/-/jszip-3.10.1.tgz";
    sha256 = "5117f4a2a645aeb307bf3b829c575ad58135cc97e75291e594532ab5b5b21b23";
  };
  gradle = pkgs.fetchurl {
    url = "https://services.gradle.org/distributions/gradle-9.3.1-bin.zip";
    sha256 = "b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06";
  };
in
pkgs.runCommand "bookfin-epub-benchmark-sources" {
  nativeBuildInputs = [ pkgs.unzip pkgs.p7zip ];
} ''
  mkdir -p "$out/native" "$out/web" "$out/ko" epubjs jszip apk
  unzip -q ${koreader} 'lib/*' 'assets/module/*' -d apk
  unzip -q ${gradle} -d "$out"
  cp apk/lib/arm64-v8a/libluajit.so apk/lib/arm64-v8a/libkoreader-monolibtic.so "$out/native/"
  7z x -y apk/assets/module/koreader.7z -o"$out/ko" >/dev/null
  tar xf ${epubjs} -C epubjs
  tar xf ${jszip} -C jszip
  cp epubjs/package/dist/epub.min.js "$out/web/"
  cp epubjs/package/license "$out/web/epubjs-license" || cp epubjs/package/LICENSE "$out/web/epubjs-license"
  cp jszip/package/dist/jszip.min.js "$out/web/"
  cp jszip/package/LICENSE.markdown "$out/web/jszip-license"
''
