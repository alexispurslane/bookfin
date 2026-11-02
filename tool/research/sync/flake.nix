{
  description = "Disposable loopback Jellyfin research, not a shared service";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/fe13242281a67641c0102cdb1087f0ebe586c7df";
  outputs =
    { nixpkgs, ... }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs { inherit system; };
      serverArchive = pkgs.fetchurl {
        url = "https://repo.jellyfin.org/files/server/macos/stable/v12.4/arm64/jellyfin_12.4-arm64.tar.xz";
        hash = "sha256-wQfU4Nhei6EpJMkRTSqK1D6dg1QKZ5I9vveIuTMR/i0=";
      };
      enhancedArchive = pkgs.fetchurl {
        url = "https://github.com/n00bcodr/Jellyfin-Enhanced/releases/download/12.14.0.0/Jellyfin.Plugin.JellyfinEnhanced_12.0.0.zip";
        hash = "sha256-y+2w+YoYJ/udlDNyqphiYLsiROlWcsFuWyelJPoyHUM=";
      };
      server =
        pkgs.runCommand "bookfin-research-jellyfin-12.4"
          {
            nativeBuildInputs = [
              pkgs.gnutar
              pkgs.xz
            ];
          }
          ''
            mkdir -p "$out"
            tar -xJf ${serverArchive} -C "$out" --strip-components=1
          '';
      enhanced =
        pkgs.runCommand "bookfin-research-enhanced-12.14.0.0"
          {
            nativeBuildInputs = [ pkgs.unzip ];
          }
          ''
            mkdir -p "$out"
            unzip -q ${enhancedArchive} -d "$out"
          '';
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.python3
          pkgs.ffmpeg-headless
          pkgs.curl
          pkgs.jq
          pkgs.nixfmt
        ];
        BOOKFIN_SYNC_SHELL = "1";
        BOOKFIN_SYNC_SERVER = server;
        BOOKFIN_SYNC_ENHANCED = enhanced;
        DOTNET_PROCESSOR_COUNT = "2";
        DOTNET_CLI_TELEMETRY_OPTOUT = "1";
      };
    };
}
