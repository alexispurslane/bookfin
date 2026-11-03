{ pkgs }:
let
  pdfiumArchive = pkgs.fetchurl {
    url = "https://github.com/bblanchon/pdfium-binaries/releases/download/chromium/8125/pdfium-mac-arm64.tgz";
    sha256 = "178k1q3pmc3cy9kkcsiic0bfm7518fy3iw54lc4xqgf8ba9vsfa9";
  };
  pdfium = pkgs.runCommand "bookfin-pdfium-8125-macos-arm64" { } ''
    mkdir -p "$out"
    tar xf ${pdfiumArchive} -C "$out"
  '';
  libmobiSource = pkgs.fetchzip {
    url = "https://github.com/bfabiszewski/libmobi/archive/refs/tags/v0.12.tar.gz";
    sha256 = "0cwya9n0rd97ai0fcqjwq7b3sjzigf3ywp7bnkbbw541f3knpds9";
  };
  mobi = pkgs.stdenv.mkDerivation {
    pname = "bookfin-libmobi-converter";
    version = "0.12";
    src = ../native/mobi;
    nativeBuildInputs = [ pkgs.cmake ];
    cmakeFlags = [ "-DBOOKFIN_LIBMOBI_SOURCE=${libmobiSource}" ];
    buildPhase = "cmake --build . --target bookfin_mobi --parallel 2";
    postInstall = ''
      mkdir -p "$out/share/licenses/libmobi"
      cp ${libmobiSource}/COPYING "$out/share/licenses/libmobi/"
    '';
  };
in
{
  inherit pdfium libmobiSource mobi;
}
