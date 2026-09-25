{
  description = "Passive Wi-Fi probe request sniffer with channel hopping";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      probeSniffer = pkgs.writeShellApplication {
        name = "probe-sniff";
        runtimeInputs = with pkgs; [
          aircrack-ng
          coreutils
          gawk
          iproute2
          iw
          wireshark-cli
        ];

        text = ''
          set -euo pipefail

          usage() {
            printf '%s\n' "Usage: probe-sniff <interface> [output-file]" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "  interface   : wireless interface (must support monitor mode)" >&2
            printf '%s\n' "  output-file : also write results to a CSV file" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Environment variables:" >&2
            printf '%s\n' "  PROBE_CHANNEL=<n>  lock to one channel instead of hopping (default: hop)" >&2
            printf '%s\n' "  PROBE_TIMEOUT=<n>  stop after n seconds (default: 0 = run indefinitely)" >&2
            printf '%s\n' "  PROBE_UNIQUE=0     set to 1 to show each (client, SSID) pair only once" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Output columns: TIME  CLIENT-MAC  SSID  SIGNAL" >&2
            printf '%s\n' "Empty SSID means a broadcast/wildcard probe (client scanning for any AP)." >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Example: probe-sniff wlan1" >&2
            printf '%s\n' "Example: PROBE_UNIQUE=1 probe-sniff wlan1 /tmp/probes.csv" >&2
            printf '%s\n' "Example: PROBE_CHANNEL=6 PROBE_TIMEOUT=60 probe-sniff wlan1" >&2
            exit 2
          }

          if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
            usage
          fi

          INTERFACE="$1"
          OUTPUT_FILE="''${2:-}"
          PROBE_CHANNEL="''${PROBE_CHANNEL:-}"
          PROBE_TIMEOUT="''${PROBE_TIMEOUT:-0}"
          PROBE_UNIQUE="''${PROBE_UNIQUE:-0}"

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

          if [ "$PROBE_TIMEOUT" != "0" ]; then
            case "$PROBE_TIMEOUT" in
              ""|*[!0-9]*)
                printf '%s\n' "PROBE_TIMEOUT must be a positive integer." >&2
                exit 2
                ;;
            esac
          fi

          # Enable monitor mode
          airmon-ng check kill > /dev/null 2>&1 || true
          airmon-ng start "$INTERFACE" > /dev/null 2>&1 || true
          MON_IFACE="''${INTERFACE}mon"
          if ! ip link show "$MON_IFACE" >/dev/null 2>&1; then
            MON_IFACE="$INTERFACE"
          fi

          HOP_PID=""
          cleanup() {
            if [ -n "$HOP_PID" ]; then kill "$HOP_PID" 2>/dev/null || true; fi
            airmon-ng stop "$MON_IFACE" > /dev/null 2>&1 || true
          }
          trap cleanup EXIT INT TERM

          if [ -n "$PROBE_CHANNEL" ]; then
            iw dev "$MON_IFACE" set channel "$PROBE_CHANNEL" 2>/dev/null || true
            printf '%s\n' "Locked to channel $PROBE_CHANNEL."
          else
            # Hop across 2.4 GHz and common 5 GHz channels, 300 ms dwell each
            (while true; do
              for ch in 1 6 11 2 7 3 8 4 9 5 10 13 \
                        36 40 44 48 52 56 60 64 \
                        100 104 108 112 149 153 157 161; do
                iw dev "$MON_IFACE" set channel "$ch" 2>/dev/null || true
                sleep 0.3
              done
            done) &
            HOP_PID=$!
            printf '%s\n' "Hopping 2.4 GHz + 5 GHz channels (300 ms dwell). Set PROBE_CHANNEL=<n> to lock."
          fi

          if [ -n "$OUTPUT_FILE" ]; then
            printf '%s\n' "timestamp,mac,ssid,signal_dbm" > "$OUTPUT_FILE"
            printf '%s\n' "Writing CSV to $OUTPUT_FILE"
          fi

          printf '%s\n' ""
          printf '%-20s  %-18s  %-32s  %s\n' "TIME" "CLIENT MAC" "SSID" "SIGNAL"
          printf '%s\n' "--------------------------------------------------------------------------------"

          TSHARK_ARGS="-i $MON_IFACE -Y wlan.fc.type_subtype==4"
          if [ "$PROBE_TIMEOUT" != "0" ]; then
            TSHARK_ARGS="$TSHARK_ARGS -a duration:$PROBE_TIMEOUT"
          fi

          # shellcheck disable=SC2086
          tshark $TSHARK_ARGS \
            -T fields \
            -e frame.time_epoch \
            -e wlan.sa \
            -e wlan.ssid \
            -e radiotap.dbm_antsignal \
            -E separator=$'\t' \
            -E occurrence=f \
            -l 2>/dev/null \
          | awk -F'\t' -v outfile="$OUTPUT_FILE" -v unique="$PROBE_UNIQUE" '
            {
              epoch = $1
              mac   = ($2 == "" ? "?" : $2)
              ssid  = ($3 == "" ? "<broadcast>" : $3)
              sig   = ($4 == "" ? "?" : $4)
              ts    = strftime("%Y-%m-%d %H:%M:%S", int(epoch))
              key   = mac SUBSEP ssid

              if (unique == "1" && seen[key]++) next

              printf "%-20s  %-18s  %-32s  %s dBm\n", ts, mac, ssid, sig
              fflush()

              if (outfile != "") {
                csv_ssid = ssid
                gsub(/,/, ";", csv_ssid)
                print ts "," mac "," csv_ssid "," sig >> outfile
                fflush(outfile)
              }
            }
          '
        '';
      };

    in
    {
      packages.${system} = {
        probe-sniff = probeSniffer;
        default = probeSniffer;
      };

      apps.${system}.default = {
        type = "app";
        program = "${probeSniffer}/bin/probe-sniff";
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
