{
  description = "Bookfin Flutter and Android development tools";

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
        includeEmulator = true;
        includeSystemImages = true;
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
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          flutter
          pkgs.jdk21
          pkgs.git
          pkgs.ffmpeg
          pkgs.jq
          pkgs.nixfmt
          android.androidsdk
        ];
        JAVA_HOME = "${pkgs.jdk21}";
        ANDROID_HOME = sdk;
        ANDROID_SDK_ROOT = sdk;
        FLUTTER_ROOT = "${flutter}";
        FLUTTER_SUPPRESS_ANALYTICS = "true";
        DART_SUPPRESS_ANALYTICS = "true";
        BOOKFIN_NIX_SHELL = "1";
        shellHook = ''
          export PUB_CACHE="$PWD/.cache/pub"
          export GRADLE_USER_HOME="$PWD/.cache/gradle"
          export PATH="${sdk}/cmdline-tools/latest/bin:${sdk}/platform-tools:${sdk}/emulator:$PATH"
        '';
      };
    };
}
