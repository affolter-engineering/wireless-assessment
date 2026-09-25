{
  description = "Beacon spam a Wi-Fi network from a monitor-mode interface for authorized testing";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      mdk3 = pkgs.stdenv.mkDerivation {
        pname = "mdk3";
        version = "6.0";
        src = pkgs.fetchFromGitHub {
          owner = "aircrack-ng";
          repo = "mdk3";
          rev = "master";
          hash = "sha256-gh8tq3CxYb+qpeqxvKnD3d+qD6uPsBeXSkr42gn7Puc=";
        };
        nativeBuildInputs = with pkgs; [ gcc makeWrapper pkg-config ];
        buildInputs = with pkgs; [ libnl libpcap ];
        NIX_CFLAGS_COMPILE = "-include stdlib.h -fcommon";
        buildPhase = ''
          make
        '';
        installPhase = ''
          mkdir -p $out/bin
          install -m 0755 src/mdk3 $out/bin/mdk3
        '';
      };
    in
    {
      packages.${system}.beacon-spam = pkgs.writeShellApplication {
        name = "beacon-spam";
        runtimeInputs = with pkgs; [
          mdk3
          aircrack-ng
          coreutils
          iproute2
          util-linux
        ];

        text = ''
          set -euo pipefail

          INTERFACE="''${1:-wlan0}"
          SSID="''${2:-TestBeaconSpam}"
          CHANNEL="''${3:-6}"
          COUNT="''${4:-1000}"

          if [ "$(id -u)" -ne 0 ]; then
            printf '%s\n' "This tool must be run as root because it manipulates wireless interfaces." >&2
            exit 1
          fi

          printf '%s\n' "=== Beacon Spam ==="
          printf '%s\n' "Interface: $INTERFACE"
          printf '%s\n' "SSID: $SSID"
          printf '%s\n' "Channel: $CHANNEL"
          printf '%s\n' "Frame count: $COUNT"
          printf '\n'
          printf '%s\n' "Beacon spam can disrupt wireless networks !!!!!!!!"
          printf '\n'

          mdk3 "$INTERFACE" b -n "$SSID" -c "$CHANNEL" -s "$COUNT"
        '';
      };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.beacon-spam}/bin/beacon-spam";
      };
    };
}
