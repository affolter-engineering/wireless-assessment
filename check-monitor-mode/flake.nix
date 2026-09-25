{
  description = "Check all present WiFi adapters for monitor mode support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      checkMonitorMode = pkgs.writeShellApplication {
        name = "check-monitor-mode";
        runtimeInputs = with pkgs; [
          coreutils
          iw
          iproute2
        ];

        text = ''
          set -euo pipefail

          if [ "$(id -u)" -ne 0 ]; then
            printf '%s\n' "Note: running without root - some driver details may be unavailable." >&2
          fi

          SYS_IEEE="/sys/class/ieee80211"

          if [ ! -d "$SYS_IEEE" ] || [ -z "$(ls -A "$SYS_IEEE" 2>/dev/null)" ]; then
            printf '%s\n' "No wireless hardware found under $SYS_IEEE."
            exit 0
          fi

          SUPPORTED=0
          TOTAL=0

          printf '%-10s  %-16s  %-20s  %s\n' "PHY" "INTERFACE(S)" "DRIVER" "MONITOR MODE"
          printf '%s\n' "----------------------------------------------------------------------"

          for phy_path in "$SYS_IEEE"/*/; do
            phy="$(basename "$phy_path")"
            TOTAL=$((TOTAL + 1))

            # Associated interface names (a PHY may have multiple)
            ifaces=""
            if [ -d "$phy_path/device/net" ]; then
              ifaces="$(find "$phy_path/device/net/" -maxdepth 1 -mindepth 1 -printf '%f,' 2>/dev/null | sed 's/,$//')"
            fi
            [ -z "$ifaces" ] && ifaces="-"

            # Driver name via sysfs symlink
            driver="-"
            driver_link="$(readlink "$phy_path/device/driver" 2>/dev/null || true)"
            if [ -n "$driver_link" ]; then
              driver="$(basename "$driver_link")"
            fi

            # Check supported interface modes reported by the kernel
            if iw phy "$phy" info 2>/dev/null | grep -q '^\s*\* monitor'; then
              monitor="YES"
              SUPPORTED=$((SUPPORTED + 1))
            else
              monitor="NO"
            fi

            printf '%-10s  %-16s  %-20s  %s\n' "$phy" "$ifaces" "$driver" "$monitor"
          done

          printf '%s\n' "----------------------------------------------------------------------"
          printf '%s\n' "Result: $SUPPORTED of $TOTAL adapter(s) support monitor mode."
        '';
      };
    in
    {
      packages.${system} = {
        check-monitor-mode = checkMonitorMode;
        default = checkMonitorMode;
      };

      apps.${system}.default = {
        type = "app";
        program = "${checkMonitorMode}/bin/check-monitor-mode";
      };
    };
}
