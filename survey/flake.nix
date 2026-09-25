{
  description = "Survey the airspace with airodump-ng from a monitor-mode interface";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system}.airdump-survey = pkgs.writeShellApplication {
        name = "airdump-survey";
        runtimeInputs = with pkgs; [
          aircrack-ng
          coreutils
          iproute2
          util-linux
        ];

        text = ''
          set -euo pipefail

          INTERFACE="''${1:-wlan0}"
          CHANNEL="''${2:-}"
          BSSID="''${3:-}"
          OUT_DIR="''${PWD}/airodump-captures"
          TIMESTAMP="$(date -u +'%Y%m%dT%H%M%SZ')"

          mkdir -p "$OUT_DIR"

          if [ -n "$CHANNEL" ] && [ -n "$BSSID" ]; then
            printf '%s\n' "Surveying channel $CHANNEL for BSSID $BSSID"
            airodump-ng -c "$CHANNEL" --bssid "$BSSID" -w "$OUT_DIR/$TIMESTAMP-$INTERFACE" "$INTERFACE"
          elif [ -n "$CHANNEL" ]; then
            printf '%s\n' "Surveying channel $CHANNEL on interface $INTERFACE"
            airodump-ng -c "$CHANNEL" -w "$OUT_DIR/$TIMESTAMP-$INTERFACE" "$INTERFACE"
          else
            printf '%s\n' "Surveying airspace on interface $INTERFACE"
            airodump-ng -w "$OUT_DIR/$TIMESTAMP-$INTERFACE" "$INTERFACE"
          fi
        '';
      };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.airdump-survey}/bin/airdump-survey";
      };
    };
}
