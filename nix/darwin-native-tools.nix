{ pkgs }:
let
  codesign = pkgs.darwin.sigtool.overrideAttrs (previous: {
    patches = previous.patches ++ [ ./sigtool-no-timestamp.patch ];
  });
  xcrun = pkgs.writeShellScriptBin "xcrun" ''
    export DEVELOPER_DIR="${pkgs.apple-sdk}"
    export SDKROOT="${pkgs.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    for argument in "$@"; do
      if [[ "$argument" == --show-sdk-path ]]; then
        if sdk_path=$(${pkgs.xcbuild}/bin/xcrun "$@" 2>&1); then
          printf '%s\n' "$sdk_path"
          exit 0
        fi
        printf 'xcrun: error: SDK cannot be located: %s\n' "$sdk_path" >&2
        exit 1
      fi
    done
    exec ${pkgs.xcbuild}/bin/xcrun "$@"
  '';
in
pkgs.symlinkJoin {
  name = "bookfin-darwin-native-tools";
  paths = [
    xcrun
    codesign
  ];
}
