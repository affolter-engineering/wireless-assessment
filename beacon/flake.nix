{
  description = "Sniff 802.11 beacon frames and write a deduplicated AP report";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      beaconSniff = pkgs.writeShellApplication {
        name = "beacon-sniff";
        runtimeInputs = with pkgs; [
          aircrack-ng
          coreutils
          gawk
          iproute2
          iw
          util-linux
          wireshark-cli
        ];

        text = ''
          set -euo pipefail

          usage() {
            printf '%s\n' "Usage: beacon-sniff <interface>" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "  interface: wireless interface (monitor mode enabled automatically)" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Environment variables:" >&2
            printf '%s\n' "  BEACON_TIMEOUT=0    stop after n seconds (default: 0 = run indefinitely)" >&2
            printf '%s\n' "  BEACON_CHANNEL=<n>  lock to one channel instead of hopping" >&2
            printf '%s\n' "  BEACON_UNIQUE=1     0 = show every frame live, 1 = one line per AP (default)" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Output: ./beacon-reports/beacons-<ts>.txt" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Example: beacon-sniff wlp198s0f3u1i3" >&2
            printf '%s\n' "Example: BEACON_TIMEOUT=60 beacon-sniff wlan1" >&2
            printf '%s\n' "Example: BEACON_CHANNEL=6 BEACON_UNIQUE=0 beacon-sniff wlan1" >&2
            exit 2
          }

          if [ "$#" -ne 1 ]; then usage; fi

          if [ "$(id -u)" -ne 0 ]; then
            printf '%s\n' "This tool must be run as root." >&2
            exit 1
          fi

          INTERFACE="$1"
          BEACON_TIMEOUT="''${BEACON_TIMEOUT:-0}"
          BEACON_CHANNEL="''${BEACON_CHANNEL:-}"
          BEACON_UNIQUE="''${BEACON_UNIQUE:-1}"

          if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
            printf '%s\n' "Interface does not exist: $INTERFACE" >&2
            exit 1
          fi

          if [ "$BEACON_TIMEOUT" != "0" ]; then
            case "$BEACON_TIMEOUT" in
              ""|*[!0-9]*)
                printf '%s\n' "BEACON_TIMEOUT must be a positive integer." >&2
                exit 2
                ;;
            esac
          fi

          OUT_DIR="$PWD/beacon-reports"
          TS="$(date -u +'%Y%m%dT%H%M%SZ')"
          WORK_DIR="$(mktemp -d)"
          RAW_FILE="$WORK_DIR/beacons.tsv"
          REPORT_FILE="$OUT_DIR/beacons-$TS.txt"
          HOP_PID=""
          MON_IFACE=""
          REPORT_DONE=""

          mkdir -p "$OUT_DIR"
          touch "$RAW_FILE"

          generate_report() {
            [ -n "$REPORT_DONE" ] && return
            REPORT_DONE=1

            if [ ! -s "$RAW_FILE" ]; then
              printf '%s\n' "No beacons captured." >&2
              return
            fi

            AP_COUNT=$(gawk -F'\t' 'NF>=2 && $2!="" {print $2}' "$RAW_FILE" \
              | sort -u | wc -l | tr -d ' ')
            FRAME_COUNT=$(wc -l < "$RAW_FILE" | tr -d ' ')
            S="--------------------------------------------------------------------------------"

            {
              printf '%s\n'   "Beacon Scan Report"
              printf '%-12s %s\n'         "Generated:" "$TS"
              printf '%-12s %s (%s)\n'    "Interface:" "$INTERFACE" "$MON_IFACE"
              if [ "$BEACON_TIMEOUT" != "0" ]; then
                printf '%-12s %s seconds\n' "Duration:"  "$BEACON_TIMEOUT"
              fi
              printf '%-12s %s\n' "APs found:" "$AP_COUNT"
              printf '%-12s %s\n' "Frames:"    "$FRAME_COUNT"
              printf '\n'
              printf '%s\n' "$S"
              printf '%-18s  %-4s  %-32s  %-8s  %s\n' \
                     "BSSID" "CH" "SSID" "SIGNAL" "BEACONS"
              printf '%s\n' "$S"
            } > "$REPORT_FILE"

            # Aggregate per BSSID, keep strongest signal, sort descending
            gawk -F'\t' '
              NF < 2 || $2 == "" { next }
              {
                b    = $2
                ssid = ($3 == "" ? "<hidden>" : $3); gsub(/^ +| +$/, "", ssid)
                ch   = ($4 == "" ? "?" : $4);        gsub(/^ +| +$/, "", ch)
                sig  = ($5 == "" ? "0" : $5);        gsub(/^ +| +$/, "", sig)
                count[b]++
                if (!(b in best) || sig+0 > best[b]+0) {
                  best[b] = sig; best_ch[b] = ch; best_ssid[b] = ssid
                }
              }
              END {
                for (b in best)
                  printf "%s\t%s\t%s\t%d\t%d\n", b, best_ch[b], best_ssid[b], best[b]+0, count[b]
              }
            ' "$RAW_FILE" \
            | sort -t$'\t' -k4 -rn \
            | gawk -F'\t' '{
                printf "%-18s  %-4s  %-32s  %-8s  %d\n", $1, $2, $3, $4 " dBm", $5
              }' \
            >> "$REPORT_FILE"

            printf '\n%s\n' "--- Scan complete ---"
            cat "$REPORT_FILE"
            printf '\nReport: %s\n' "$REPORT_FILE"
          }

          cleanup() {
            if [ -n "$HOP_PID" ]; then kill "$HOP_PID" 2>/dev/null || true; fi
            generate_report
            rm -rf "$WORK_DIR"
            if [ -n "$MON_IFACE" ]; then
              airmon-ng stop "$MON_IFACE" > /dev/null 2>&1 || true
            fi
          }
          trap cleanup EXIT INT TERM

          printf '%s\n' "Enabling monitor mode on $INTERFACE..."
          airmon-ng check kill > /dev/null 2>&1 || true
          airmon-ng start "$INTERFACE" > /dev/null 2>&1 || true
          MON_IFACE="''${INTERFACE}mon"
          if ! ip link show "$MON_IFACE" >/dev/null 2>&1; then
            MON_IFACE="$INTERFACE"
          fi
          printf '%s\n' "Monitor interface: $MON_IFACE"

          if [ -n "$BEACON_CHANNEL" ]; then
            iw dev "$MON_IFACE" set channel "$BEACON_CHANNEL" 2>/dev/null || true
            printf '%s\n' "Locked to channel $BEACON_CHANNEL."
          else
            (while true; do
              for ch in 1 6 11 2 7 3 8 4 9 5 10 13 \
                        36 40 44 48 52 56 60 64 \
                        100 104 108 112 149 153 157 161; do
                iw dev "$MON_IFACE" set channel "$ch" 2>/dev/null || true
                sleep 0.3
              done
            done) &
            HOP_PID=$!
            printf '%s\n' "Hopping 2.4 + 5 GHz channels (300 ms dwell). Set BEACON_CHANNEL=<n> to lock."
          fi

          printf '\n'
          printf '%-20s  %-18s  %-4s  %-32s  %s\n' "TIME" "BSSID" "CH" "SSID" "SIGNAL"
          printf '%s\n' "--------------------------------------------------------------------------------"

          TSHARK_ARGS="-i $MON_IFACE -Y wlan.fc.type_subtype==8"
          if [ "$BEACON_TIMEOUT" != "0" ]; then
            TSHARK_ARGS="$TSHARK_ARGS -a duration:$BEACON_TIMEOUT"
          fi

          # shellcheck disable=SC2086
          tshark $TSHARK_ARGS \
            -T fields \
            -e frame.time_epoch \
            -e wlan.bssid \
            -e wlan.ssid \
            -e wlan.ds.current_channel \
            -e radiotap.dbm_antsignal \
            -E separator=$'\t' \
            -E occurrence=f \
            -l 2>/dev/null \
          | tee "$RAW_FILE" \
          | gawk -F'\t' -v unique="$BEACON_UNIQUE" '
              {
                epoch = $1
                bssid = ($2 == "" ? "?" : $2)
                ssid  = ($3 == "" ? "<hidden>" : $3)
                ch    = ($4 == "" ? "?" : $4)
                sig   = ($5 == "" ? "?" : $5)
                ts    = strftime("%Y-%m-%d %H:%M:%S", int(epoch))

                if (unique == "1" && seen[bssid]++) next

                printf "%-20s  %-18s  %-4s  %-32s  %s dBm\n", ts, bssid, ch, ssid, sig
                fflush()
              }
            ' || true
        '';
      };

    in
    {
      packages.${system} = {
        beacon-sniff = beaconSniff;
        default = beaconSniff;
      };

      apps.${system}.default = {
        type = "app";
        program = "${beaconSniff}/bin/beacon-sniff";
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          aircrack-ng
          gawk
          iproute2
          iw
          wireshark-cli
        ];
      };
    };
}
