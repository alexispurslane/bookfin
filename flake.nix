{
  description = "Bookfin Flutter and Android development tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/fe13242281a67641c0102cdb1087f0ebe586c7df";

  outputs =
    { nixpkgs, ... }:
    let
      # Android build tools and the NDK ship for x86_64 Linux, not aarch64 Linux.
      # x86_64-linux also covers WSL2 on Windows.
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      # The shells of one system: the default shell, and on macOS the shell
      # that builds the macOS desktop app.
      shells =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              android_sdk.accept_license = true;
            };
          };
          inherit (pkgs.stdenv.hostPlatform) isDarwin;
          flutter = pkgs.flutter.override {
            supportedTargetFlutterPlatforms = [
              "universal"
              "android"
              "web"
            ];
          };
          android = pkgs.androidenv.composeAndroidPackages {
            cmdLineToolsVersion = "19.0";
            platformVersions = [ "36" ];
            buildToolsVersions = [ "36.0.0" ];
            # The emulator and its arm64 image run on the Mac. Linux is a build host.
            includeEmulator = isDarwin;
            includeSystemImages = isDarwin;
            systemImageTypes = [ "google_apis" ];
            abiVersions = [ "arm64-v8a" ];
            includeNDK = true;
            ndkVersions = [ "28.2.13676358" ];
            cmakeVersions = [ "3.22.1" ];
          };
          dependencyPlatforms =
            (pkgs.androidenv.composeAndroidPackages {
              platformVersions = [
                "34"
                "35"
              ];
            }).platforms;
          sdk = pkgs.runCommand "bookfin-android-sdk" { } ''
            mkdir -p "$out/cmdline-tools" "$out/platforms"
            for entry in ${android.androidsdk}/libexec/android-sdk/*; do
              name=$(basename "$entry")
              if [ "$name" != cmdline-tools ] && [ "$name" != platforms ]; then
                ln -s "$entry" "$out/$name"
              fi
            done
            for platform in ${android.androidsdk}/libexec/android-sdk/platforms/*; do
              ln -s "$platform" "$out/platforms/$(basename "$platform")"
            done
            for package in ${builtins.toString dependencyPlatforms}; do
              for platform in "$package"/libexec/android-sdk/platforms/*; do
                ln -s "$platform" "$out/platforms/$(basename "$platform")"
              done
            done
            ln -s ${android.androidsdk}/libexec/android-sdk/cmdline-tools/19.0 "$out/cmdline-tools/19.0"
            ln -s 19.0 "$out/cmdline-tools/latest"
          '';
          # The compiler tools that Dart build hooks use for host code.
          # On Linux, native_toolchain_c looks up clang and llvm-ar.
          nativeTools =
            if isDarwin then
              [ (import ./nix/darwin-native-tools.nix { inherit pkgs; }) ]
            else
              [
                pkgs.clang
                pkgs.llvm
              ];
          readerNative = import ./nix/reader-native.nix { inherit pkgs; };
          ocr = import ./nix/ocr.nix { inherit pkgs; };
          # Gradle downloads an aapt2 built for a generic Linux. It needs the
          # /lib64 loader, which NixOS lacks, so use the patched SDK aapt2.
          linuxOnly = pkgs.lib.optionalAttrs (!isDarwin) {
            GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${sdk}/build-tools/36.0.0/aapt2";
          };
        in
        {
          default = pkgs.mkShell (
            {
              packages = [
                flutter
                pkgs.jdk21
                pkgs.git
                pkgs.ffmpeg
                pkgs.jq
                pkgs.nixfmt
                pkgs.nodejs_22
                pkgs.curl
                pkgs.python3
                pkgs.cmake
                pkgs.ninja
                android.androidsdk
              ]
              ++ nativeTools
              ++ [ ocr.hostEngine ];
              JAVA_HOME = "${pkgs.jdk21}";
              ANDROID_HOME = sdk;
              ANDROID_SDK_ROOT = sdk;
              FLUTTER_ROOT = "${flutter}";
              FLUTTER_SUPPRESS_ANALYTICS = "true";
              DART_SUPPRESS_ANALYTICS = "true";
              PDFIUM_LIBRARY = readerNative.pdfiumLibrary;
              BOOKFIN_LIBMOBI_SOURCE = readerNative.libmobiSource;
              BOOKFIN_MOBI_LIBRARY = readerNative.mobiLibrary;
              BOOKFIN_PDFIUM_ANDROID = readerNative.pdfiumAndroid;
              BOOKFIN_GPL3_TEXT = readerNative.gplText;
              BOOKFIN_OCR_MODEL = ocr.model;
              BOOKFIN_OCR_ANDROID_AAR = ocr.aar;
              BOOKFIN_OCR_ANDROID_SOURCE = ocr.source;
              BOOKFIN_OCR_ANDROID_NATIVE = ocr.androidNative;
              BOOKFIN_OCR_MODEL_LICENSE = ocr.modelLicense;
              BOOKFIN_NIX_SHELL = "1";
              shellHook = ''
                # Every checkout, agent worktrees included, shares one
                # dependency cache. A cache per checkout took 3.6 GB each.
                export PUB_CACHE="''${XDG_CACHE_HOME:-$HOME/.cache}/bookfin/pub"
                export GRADLE_USER_HOME="''${XDG_CACHE_HOME:-$HOME/.cache}/bookfin/gradle"
                export PATH="${sdk}/cmdline-tools/latest/bin:${sdk}/platform-tools:${sdk}/emulator:$PATH"
              '';
            }
            // linuxOnly
          );
        }
        // pkgs.lib.optionalAttrs isDarwin {
          # nix develop .#macos
          macos = import ./nix/macos-desktop.nix { inherit pkgs readerNative; };
        };
    in
    {
      devShells = nixpkgs.lib.genAttrs systems shells;
    };
}
