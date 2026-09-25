{
  description = "Enumerate APs and their associated clients, write a timestamped text report";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      apClients = pkgs.writeShellApplication {
        name = "ap-clients";
        runtimeInputs = with pkgs; [
          aircrack-ng
          coreutils
          gawk
          iproute2
          iw
          util-linux
        ];

        text = ''
          set -euo pipefail

          usage() {
            printf '%s\n' "Usage: ap-clients <interface>" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "  interface: wireless interface (monitor mode enabled automatically)" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Environment variables:" >&2
            printf '%s\n' "  SCAN_TIMEOUT=60    capture duration in seconds (default: 60)" >&2
            printf '%s\n' "  SCAN_CHANNEL=<n>   lock to one channel instead of hopping" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Output: ./ap-client-reports/ap-clients-<ts>.txt" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Example: ap-clients wlp198s0f3u1i3" >&2
            printf '%s\n' "Example: SCAN_TIMEOUT=120 ap-clients wlan1" >&2
            printf '%s\n' "Example: SCAN_CHANNEL=6 ap-clients wlan1" >&2
            exit 2
          }

          if [ "$#" -ne 1 ]; then usage; fi

          if [ "$(id -u)" -ne 0 ]; then
            printf '%s\n' "This tool must be run as root." >&2
            exit 1
          fi

          INTERFACE="$1"
          SCAN_TIMEOUT="''${SCAN_TIMEOUT:-60}"
          SCAN_CHANNEL="''${SCAN_CHANNEL:-}"

          if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
            printf '%s\n' "Interface does not exist: $INTERFACE" >&2
            exit 1
          fi

          OUT_DIR="$PWD/ap-client-reports"
          TS="$(date -u +'%Y%m%dT%H%M%SZ')"
          WORK_DIR="$(mktemp -d)"
          CSV_FILE="$WORK_DIR/scan-01.csv"
          REPORT_FILE="$OUT_DIR/ap-clients-$TS.txt"
          AIRODUMP_PID=""
          MON_IFACE=""

          mkdir -p "$OUT_DIR"

          generate_report() {
            if [ ! -f "$CSV_FILE" ]; then
              printf '%s\n' "No data captured." >&2
              return
            fi

            gawk -F', *' \
              -v ts="$TS" \
              -v iface="$INTERFACE" \
              -v mon="$MON_IFACE" \
              -v timeout="$SCAN_TIMEOUT" \
            '
              BEGIN { section = -1; ap_n = 0; cl_n = 0 }

              /^BSSID/         { section = 0; next }
              /^Station MAC/   { section = 1; next }
              /^[[:space:]]*$/ { next }

              section == 0 {
                b   = $1;  gsub(/^ +| +$/, "", b)
                ch  = $4;  gsub(/^ +| +$/, "", ch)
                pri = $6;  gsub(/^ +| +$/, "", pri)
                cip = $7;  gsub(/^ +| +$/, "", cip)
                aut = $8;  gsub(/^ +| +$/, "", aut)
                pwr = $9;  gsub(/^ +| +$/, "", pwr)
                ess = $14; gsub(/^ +| +$/, "", ess)
                if (ess == "") ess = "<hidden>"
                sec = pri
                if (cip != "") sec = sec "/" cip
                if (aut != "") sec = sec "/" aut
                ap_order[ap_n++] = b
                ap_ch[b]  = ch
                ap_ess[b] = ess
                ap_pwr[b] = pwr
                ap_sec[b] = sec
              }

              section == 1 {
                sta = $1; gsub(/^ +| +$/, "", sta)
                pwr = $4; gsub(/^ +| +$/, "", pwr)
                pkt = $5; gsub(/^ +| +$/, "", pkt)
                asc = $6; gsub(/^ +| +$/, "", asc)
                prb = ""
                for (i = 7; i <= NF; i++) {
                  p = $i; gsub(/^ +| +$/, "", p)
                  if (p != "") prb = (prb == "" ? p : prb ", " p)
                }
                cl_order[cl_n++] = sta
                cl_pwr[sta] = pwr
                cl_pkt[sta] = pkt
                cl_asc[sta] = asc
                cl_prb[sta] = prb
                if (asc != "(not associated)" && asc != "") {
                  ap_cl_n[asc]++
                  ap_cl[asc] = ap_cl[asc] sta "\n"
                }
              }

              END {
                S = "--------------------------------------------------------------------------------"
                printf "AP & Client Report\n"
                printf "Generated  : %s\n", ts
                printf "Interface  : %s (%s)\n", iface, mon
                printf "Duration   : %s seconds\n", timeout
                printf "APs seen   : %d\n", ap_n
                printf "Clients    : %d\n\n", cl_n

                # --- Access Points ---
                for (i = 0; i < ap_n; i++) {
                  b   = ap_order[i]
                  ncl = (b in ap_cl_n) ? ap_cl_n[b] : 0
                  printf "%s\n", S
                  printf "AP    : %-18s  CH %-3s  %s dBm  %s\n", \
                         b, ap_ch[b], ap_pwr[b], ap_sec[b]
                  printf "ESSID : %s\n", ap_ess[b]
                  if (ncl == 0) {
                    printf "       (no associated clients observed)\n"
                  } else {
                    n = split(ap_cl[b], clients, "\n")
                    for (j = 1; j <= n; j++) {
                      c = clients[j]
                      if (c == "") continue
                      printf "  +-- %s  %s dBm  %s pkts", c, cl_pwr[c], cl_pkt[c]
                      if (cl_prb[c] != "") printf "  probes: %s", cl_prb[c]
                      printf "\n"
                    }
                  }
                }
                printf "%s\n\n", S

                # --- Unassociated Clients ---
                printf "Unassociated Clients\n"
                printf "%s\n", S
                ua = 0
                for (i = 0; i < cl_n; i++) {
                  c = cl_order[i]
                  if (cl_asc[c] == "(not associated)" || cl_asc[c] == "") {
                    printf "  %s  %s dBm  %s pkts", c, cl_pwr[c], cl_pkt[c]
                    if (cl_prb[c] != "") printf "  probes: %s", cl_prb[c]
                    printf "\n"
                    ua++
                  }
                }
                if (ua == 0) printf "  (none)\n"
                printf "%s\n", S
              }
            ' "$CSV_FILE" | tee "$REPORT_FILE"

            printf '\nReport: %s\n' "$REPORT_FILE"
          }

          cleanup() {
            if [ -n "$AIRODUMP_PID" ]; then kill "$AIRODUMP_PID" 2>/dev/null || true; fi
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

          if [ -n "$SCAN_CHANNEL" ]; then
            printf '%s\n' "Channel: $SCAN_CHANNEL (locked)  Timeout: $SCAN_TIMEOUT s"
            airodump-ng -c "$SCAN_CHANNEL" \
              -w "$WORK_DIR/scan" --output-format csv \
              "$MON_IFACE" > /dev/null 2>&1 &
          else
            printf '%s\n' "Channel: hopping  Timeout: $SCAN_TIMEOUT s"
            airodump-ng \
              -w "$WORK_DIR/scan" --output-format csv \
              "$MON_IFACE" > /dev/null 2>&1 &
          fi
          AIRODUMP_PID=$!

          printf '%s\n' "Scanning... press Ctrl+C to stop early."
          sleep "$SCAN_TIMEOUT"
        '';
      };

    in
    {
      packages.${system} = {
        ap-clients = apClients;
        default = apClients;
      };

      apps.${system}.default = {
        type = "app";
        program = "${apClients}/bin/ap-clients";
      };
    };
}
