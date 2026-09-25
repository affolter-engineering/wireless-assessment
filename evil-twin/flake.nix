{
  description = "Run an evil-twin access point for authorized wireless testing";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system}.evil-twin = pkgs.writeShellApplication {
        name = "evil-twin";
        runtimeInputs = with pkgs; [
          hostapd
          dnsmasq
          iproute2
          coreutils
          util-linux
          iw
        ];

        text = ''
          set -euo pipefail

          SSID="''${1:-TestAP}"
          INTERFACE="''${2:-wlan0}"
          CHANNEL="''${3:-6}"
          WORK_DIR="''${PWD}/evil-twin-data"
          HOSTAPD_CONF="''${WORK_DIR}/hostapd.conf"
          DNSMASQ_CONF="''${WORK_DIR}/dnsmasq.conf"

          if [ "$(id -u)" -ne 0 ]; then
            printf '%s\n' "This tool must be run as root because it creates a wireless access point." >&2
            exit 1
          fi

          mkdir -p "$WORK_DIR"

          cat > "$HOSTAPD_CONF" <<EOF
          interface=$INTERFACE
          driver=nl80211
          ssid=$SSID
          hw_mode=g
          channel=$CHANNEL
          ieee80211n=1
          wmm_enabled=1
          auth_algs=1
          ignore_broadcast_ssid=0
          EOF

          cat > "$DNSMASQ_CONF" <<EOF
          interface=$INTERFACE
          dhcp-range=10.0.0.2,10.0.0.50,255.255.255.0,12h
          dhcp-option=3,10.0.0.1
          dhcp-option=6,10.0.0.1
          address=/#/10.0.0.1
          log-queries
          log-dhcp
          EOF

          printf '%s\n' "=== Evil Twin Setup ==="
          printf '%s\n' "SSID: $SSID"
          printf '%s\n' "Interface: $INTERFACE"
          printf '%s\n' "Channel: $CHANNEL"
          printf '%s\n' "Hostapd config: $HOSTAPD_CONF"
          printf '%s\n' "Dnsmasq config: $DNSMASQ_CONF"
          printf '\n'
          printf '%s\n' "Important: use this only within explicit scope and authorization."
          printf '%s\n' "This tool is intended for authorized wireless testing and lab use only."
          printf '\n'

          ip link set "$INTERFACE" up
          ip addr flush dev "$INTERFACE" || true
          ip addr add 10.0.0.1/24 dev "$INTERFACE"

          dnsmasq -C "$DNSMASQ_CONF" -d &
          DNSMASQ_PID=$!

          hostapd "$HOSTAPD_CONF"

          wait "$DNSMASQ_PID"
        '';
      };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.evil-twin}/bin/evil-twin";
      };
    };
}
