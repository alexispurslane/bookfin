{
  description = "Isolated Bookfin reader-format experiments (not app dependencies)";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/fe13242281a67641c0102cdb1087f0ebe586c7df";
  outputs =
    { nixpkgs, ... }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };
      android = pkgs.androidenv.composeAndroidPackages {
        cmdLineToolsVersion = "19.0";
        platformVersions = [
          "35"
          "36"
        ];
        buildToolsVersions = [ "36.0.0" ];
        includeNDK = true;
        ndkVersions = [ "28.2.13676358" ];
        cmakeVersions = [ "3.22.1" ];
      };
      flutter = pkgs.flutter.override {
        supportedTargetFlutterPlatforms = [
          "universal"
          "android"
          "web"
        ];
      };
      libmobi = pkgs.stdenv.mkDerivation {
        pname = "libmobi";
        version = "0.12";
        src = pkgs.fetchzip {
          url = "https://github.com/bfabiszewski/libmobi/archive/refs/tags/v0.12.tar.gz";
          sha256 = "0cwya9n0rd97ai0fcqjwq7b3sjzigf3ywp7bnkbbw541f3knpds9";
        };
        nativeBuildInputs = [ pkgs.cmake ];
        buildInputs = [ pkgs.zlib ];
        cmakeFlags = [
          "-DUSE_LIBXML2=OFF"
          "-DUSE_ENCRYPTION=OFF"
        ];
        buildPhase = "cmake --build . --target mobitool mobimeta -j2";
        installPhase = ''
          mkdir -p "$out/bin" "$out/lib" "$out/share/licenses/libmobi"
          cp tools/mobitool tools/mobimeta "$out/bin/"
          cp -P src/libmobi*.dylib "$out/lib/"
          cp ../COPYING "$out/share/licenses/libmobi/"
          install_name_tool -change @rpath/libmobi.0.dylib "$out/lib/libmobi.0.dylib" "$out/bin/mobitool"
          install_name_tool -change @rpath/libmobi.0.dylib "$out/lib/libmobi.0.dylib" "$out/bin/mobimeta"
        '';
      };
      pdfiumHost = pkgs.fetchurl {
        url = "https://github.com/bblanchon/pdfium-binaries/releases/download/chromium/8125/pdfium-mac-arm64.tgz";
        sha256 = "178k1q3pmc3cy9kkcsiic0bfm7518fy3iw54lc4xqgf8ba9vsfa9";
      };
      pdfiumAndroid = pkgs.fetchurl {
        url = "https://github.com/bblanchon/pdfium-binaries/releases/download/chromium/8125/pdfium-android-arm64.tgz";
        sha256 = "1d4py14y696i8mvbklaipn6hk9r4g6qdkgg1mv53g6a2cdqyb584";
      };
      gplText = pkgs.fetchurl {
        url = "https://www.gnu.org/licenses/gpl-3.0.txt";
        sha256 = "3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986";
      };
      nativeTools = import ../../../nix/darwin-native-tools.nix { inherit pkgs; };
    in
    {
      devShells.${system} = {
        android = pkgs.mkShell {
          packages = [
            flutter
            pkgs.jdk21
            android.androidsdk
            pkgs.unzip
            pkgs.ripgrep
          ];
          JAVA_HOME = pkgs.jdk21;
          ANDROID_HOME = "${android.androidsdk}/libexec/android-sdk";
          ANDROID_SDK_ROOT = "${android.androidsdk}/libexec/android-sdk";
          FLUTTER_ROOT = flutter;
          FLUTTER_SUPPRESS_ANALYTICS = "true";
          DART_SUPPRESS_ANALYTICS = "true";
          BOOKFIN_NIX_SHELL = "1";
          shellHook = ''
            export PUB_CACHE="$PWD/.cache/pub"
            export GRADLE_USER_HOME="$PWD/.cache/gradle"
          '';
        };
        default = pkgs.mkShell {
          packages = [
            libmobi
            pkgs.cmake
            pkgs.ninja
            pkgs.pkg-config
            pkgs.curl
            pkgs.jq
            pkgs.dart
            nativeTools
            pkgs.poppler-utils
            pkgs.llvmPackages.llvm
            pkgs.unzip
            pkgs.ripgrep
            (pkgs.python3.withPackages (python: [
              python.reportlab
              python.pillow
              python.markdown
              python.bleach
              python.lxml
            ]))
          ];
          LIBMOBI_SOURCE = libmobi.src;
          LIBMOBI_PREFIX = libmobi;
          PDFIUM_HOST_ARCHIVE = pdfiumHost;
          PDFIUM_ANDROID_ARCHIVE = pdfiumAndroid;
          ALICE_KF8 = ./fixtures/pg11-kf8.mobi;
          GPL3_TEXT = gplText;
          EPUBX_ARCHIVE = pkgs.fetchurl {
            url = "https://pub.dev/api/archives/epubx-4.0.0.tar.gz";
            sha256 = "0ab9354efa177c4be52c46f857bc15bf83f83a92667fb673465c8f89fca26db3";
          };
          shellHook = ''
            export PUB_CACHE="$PWD/.cache/pub"
          '';
        };
      };
    };
}
