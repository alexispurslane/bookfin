# The shell that builds and runs the macOS desktop app.
#
# Xcode builds a macOS app, and Nix cannot supply Xcode. So this shell uses
# the Xcode that `xcode-select -p` names, and it leaves out the default
# shell's Nix compiler environment and its xcrun and codesign wrappers,
# which point SDKROOT and DEVELOPER_DIR at the Nix Apple SDK. The Flutter
# SDK, CMake, and the pinned reader sources still come from Nix.
{
  pkgs,
  readerNative,
}:
let
  flutter = pkgs.flutter.override {
    supportedTargetFlutterPlatforms = [
      "universal"
      "macos"
    ];
  };
in
pkgs.mkShellNoCC {
  packages = [
    flutter
    pkgs.git
    pkgs.cmake
    pkgs.python3
    pkgs.jq
    # flutter_secure_storage_macos 3.1.3 has no Swift package, only a pod.
    pkgs.cocoapods
    # Flutter copies its framework with `rsync --chmod`. macOS ships
    # openrsync as /usr/bin/rsync, which ignores --chmod, so the read-only
    # Nix store copy stays read-only and the thinning step fails.
    pkgs.rsync
  ];
  FLUTTER_ROOT = "${flutter}";
  FLUTTER_SUPPRESS_ANALYTICS = "true";
  DART_SUPPRESS_ANALYTICS = "true";
  PDFIUM_LIBRARY = readerNative.pdfiumLibrary;
  BOOKFIN_LIBMOBI_SOURCE = readerNative.libmobiSource;
  BOOKFIN_NIX_SHELL = "1";
  BOOKFIN_MACOS_SHELL = "1";
  shellHook = ''
    export PUB_CACHE="$PWD/.cache/pub"
    unset SDKROOT DEVELOPER_DIR
  '';
}
