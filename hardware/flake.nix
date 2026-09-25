{
  description = "Collect wireless adapter details and save them to a text report";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system}.wireless-adapter-report = pkgs.writeShellApplication {
        name = "wireless-adapter-report";
        runtimeInputs = with pkgs; [
          coreutils
          iproute2
          iw
          kmod
          pciutils
          usbutils
          util-linux
          wirelesstools
        ];
        text = ''
          set -euo pipefail

          TS="$(date -u +'%Y%m%dT%H%M%SZ')"
          OUT="$PWD/wireless-adapter-report-$TS.txt"
          QUIET=0

          usage() {
            printf '%s\n' "Usage: wireless-adapter-report [--output PATH] [--quiet] [--help]"
            printf '%s\n' "  --output PATH   Write the report to PATH instead of ./wireless-adapter-report-<ts>.txt"
            printf '%s\n' "  --quiet         Suppress the success message after writing the report"
            printf '%s\n' "  --help          Show this help message"
          }

          while [ "$#" -gt 0 ]; do
            case "$1" in
              --output)
                shift
                if [ "$#" -lt 1 ]; then
                  printf '%s\n' "Error: --output requires a file path." >&2
                  exit 1
                fi
                OUT="$1"
                ;;
              --quiet)
                QUIET=1
                ;;
              --help|-h)
                usage
                exit 0
                ;;
              *)
                printf '%s\n' "Unknown argument: $1" >&2
                usage >&2
                exit 1
                ;;
            esac
            shift
          done

          mkdir -p "$(dirname "$OUT")"

          {
            printf '%s\n' "Wireless Adapter Inventory"
            printf '%s\n' "Generated: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
            printf '\n'
            printf '%s\n' "## 1. Host information"
            uname -a
            printf '\n'
            printf '%s\n' "## 2. Network interfaces"
            ip link || true
            printf '\n'
            printf '%s\n' "## 3. Wireless interfaces"
            iw dev || true
            printf '\n'
            printf '%s\n' "## 4. USB devices"
            lsusb || true
            printf '\n'
            printf '%s\n' "## 5. USB wireless adapters"
            found_usb=0
            if [ -d /sys/class/ieee80211 ]; then
              for phy_path in /sys/class/ieee80211/*/; do
                [ -e "$phy_path" ] || continue
                phy="$(basename "$phy_path")"
                dev_path="$(readlink -f "$phy_path/device" 2>/dev/null || true)"
                echo "$dev_path" | grep -q '/usb' || continue
                found_usb=1
                # Walk up sysfs to the USB device node (has idVendor)
                usb_dev="$dev_path"
                while [ "$usb_dev" != "/" ] && [ ! -f "$usb_dev/idVendor" ]; do
                  usb_dev="$(dirname "$usb_dev")"
                done
                vendor_id="$(cat "$usb_dev/idVendor" 2>/dev/null || printf '????')"
                product_id="$(cat "$usb_dev/idProduct" 2>/dev/null || printf '????')"
                manufacturer="$(cat "$usb_dev/manufacturer" 2>/dev/null || printf '-')"
                product="$(cat "$usb_dev/product" 2>/dev/null || printf '-')"
                driver="$(basename "$(readlink "$phy_path/device/driver" 2>/dev/null || printf '-')")"
                ifaces="$(find "$phy_path/device/net/" -maxdepth 1 -mindepth 1 -printf '%f ' 2>/dev/null || printf '-')"
                bus_path="$(echo "$dev_path" | grep -oE 'usb[0-9]+/[0-9-]+' | tail -1 || printf '-')"
                printf '  PHY:    %s\n' "$phy"
                printf '  Iface:  %s\n' "$ifaces"
                printf '  Driver: %s\n' "$driver"
                printf '  USB ID: %s:%s  %s %s\n' "$vendor_id" "$product_id" "$manufacturer" "$product"
                printf '  Bus:    %s\n' "$bus_path"
                printf '\n'
              done
            fi
            [ "$found_usb" -eq 0 ] && printf '  (none found)\n'
            printf '\n'
            printf '%s\n' "## 6. PCI network devices"
            lspci | grep -i -E 'wireless|network|ethernet' || true
            printf '\n'
            printf '%s\n' "## 7. Wireless details"
            iwconfig 2>/dev/null || true
            printf '\n'
            printf '%s\n' "## 8. Loaded wireless-related kernel modules"
            lsmod | grep -E 'rtl|rtl8xxxu|rt2800|ath|mt76|mt79|iwlwifi|brcmsmac|b43|carl9170' || true
            printf '\n'
            printf '%s\n' "## 8. Kernel messages"
            dmesg | tail -n 100 || true
          } > "$OUT"

          if [ "$QUIET" -eq 0 ]; then
            printf '%s\n' "Wireless adapter report written to: $OUT"
          fi
        '';
      };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.wireless-adapter-report}/bin/wireless-adapter-report";
      };
    };
}
