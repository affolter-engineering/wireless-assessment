{
  description = "KRACK (Key Reinstallation Attack) testing with krackattacks-scripts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # Modified hostapd and Python attack scripts from Vanhoef's krackattacks-scripts.
      krackattacks = pkgs.stdenv.mkDerivation {
        pname = "krackattacks";
        version = "unstable";
        src = pkgs.fetchFromGitHub {
          owner = "vanhoefm";
          repo = "krackattacks-scripts";
          rev = "2dc8012adc18ee1c567b428e095837d0bc0793fd";
          hash = "sha256-8LRZUCJq5DTpMFmtvy+XMvO9JjMW6NHwlsoV3xfH33U=";
        };
        nativeBuildInputs = with pkgs; [ pkg-config ];
        buildInputs = with pkgs; [ openssl libnl dbus ];
        buildPhase = ''
          cd hostapd
          cp defconfig .config
          echo "CONFIG_CTRL_IFACE_DBUS_NEW=n" >> .config
          echo "CONFIG_CTRL_IFACE_DBUS_INTRO=n" >> .config
          make -j$(nproc)
          cd ..
        '';
        installPhase = ''
          mkdir -p $out/bin $out/share/krackattack
          cp hostapd/hostapd $out/bin/krack-hostapd
          # -L dereferences symlinks (wpaspy.py and hostapd.conf point to sibling dirs)
          cp -rL krackattack/. $out/share/krackattack/
        '';
        doCheck = false;
      };

      pythonEnv = pkgs.python3.withPackages (ps: with ps; [
        pycryptodome
        scapy
        six
      ]);

      # 4-way handshake and group key reinstallation attacks.
      # Copies scripts to a writable work dir so hostapd.conf can be patched.
      krackAttack = pkgs.writeShellApplication {
        name = "krack-attack";
        runtimeInputs = [ krackattacks pythonEnv pkgs.iproute2 pkgs.iw ];

        text = ''
          set -euo pipefail

          usage() {
            printf '%s\n' "Usage: krack-attack <interface> [attack]" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "  interface : wireless interface for the rogue AP" >&2
            printf '%s\n' "  attack    : attack type (default: fourway)" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Attack types:" >&2
            printf '%s\n' "  fourway          : 4-way handshake key reinstallation (default)" >&2
            printf '%s\n' "  group            : group key handshake reinstallation" >&2
            printf '%s\n' "  replay-broadcast : replay broadcast/multicast frames" >&2
            printf '%s\n' "  replay-unicast   : replay unicast frames using reinstalled key" >&2
            printf '%s\n' "  tptk             : Temporal PTK reinstallation" >&2
            printf '%s\n' "  tptk-rand        : Temporal PTK reinstallation with random ANonce" >&2
            printf '%s\n' "  gtkinit          : GTK reinstallation in initial 4-way handshake" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Environment variables:" >&2
            printf '%s\n' "  KRACK_DEBUG=1  : enable verbose debug output" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "For Fast BSS Transition (802.11r) attacks use: krack-ft-attack" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Example: krack-attack wlan1" >&2
            printf '%s\n' "Example: krack-attack wlan1 group" >&2
            exit 2
          }

          if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
            usage
          fi

          INTERFACE="$1"
          ATTACK="''${2:-fourway}"
          KRACK_DEBUG="''${KRACK_DEBUG:-0}"

          if [ "$(id -u)" -ne 0 ]; then
            printf '%s\n' "This tool must be run as root." >&2
            exit 1
          fi

          if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
            printf '%s\n' "Interface does not exist: $INTERFACE" >&2
            exit 1
          fi

          ATTACK_FLAG=""
          case "$ATTACK" in
            fourway)          ATTACK_FLAG="--fourway" ;;
            group)            ATTACK_FLAG="--group" ;;
            replay-broadcast) ATTACK_FLAG="--replay-broadcast" ;;
            replay-unicast)   ATTACK_FLAG="--replay-unicast" ;;
            tptk)             ATTACK_FLAG="--tptk" ;;
            tptk-rand)        ATTACK_FLAG="--tptk-rand" ;;
            gtkinit)          ATTACK_FLAG="--gtkinit" ;;
            *)
              printf '%s\n' "Unknown attack type: $ATTACK" >&2
              usage
              ;;
          esac

          DEBUG_FLAG=""
          if [ "$KRACK_DEBUG" = "1" ]; then
            DEBUG_FLAG="--debug"
          fi

          WORK_DIR="$(mktemp -d)"
          ORIG_IFACE=""

          cleanup() {
            rm -rf "$WORK_DIR"
            if [ -n "$ORIG_IFACE" ]; then
              ip link set "$INTERFACE" down 2>/dev/null || true
              ip link set "$INTERFACE" name "$ORIG_IFACE" 2>/dev/null || true
              ip link set "$ORIG_IFACE" up 2>/dev/null || true
            fi
          }
          trap cleanup EXIT INT TERM

          # Linux limits interface names to 15 chars. The script appends "mon" to
          # create a monitor interface, so the base name must be at most 12 chars.
          MON_CANDIDATE="''${INTERFACE}mon"
          if [ "''${#MON_CANDIDATE}" -gt 15 ]; then
            SHORT="wlkr0"
            for n in 0 1 2 3 4 5 6 7 8 9; do
              SHORT="wlkr$n"
              if ! ip link show "$SHORT" >/dev/null 2>&1; then break; fi
            done
            printf '%s\n' "Interface name '$INTERFACE' too long for monitor naming — renaming to '$SHORT'."
            ip link set "$INTERFACE" down
            ip link set "$INTERFACE" name "$SHORT"
            ip link set "$SHORT" up
            ORIG_IFACE="$INTERFACE"
            INTERFACE="$SHORT"
          fi

          # The script resolves hostapd as ../hostapd/hostapd relative to its own dir,
          # so we need scripts in $WORK_DIR/krackattack/ and binary in $WORK_DIR/hostapd/.
          mkdir -p "$WORK_DIR/krackattack" "$WORK_DIR/hostapd"
          cp -rL ${krackattacks}/share/krackattack/. "$WORK_DIR/krackattack/"
          cp ${krackattacks}/bin/krack-hostapd "$WORK_DIR/hostapd/hostapd"
          chmod -R u+w "$WORK_DIR"

          # Fix invalid escape sequences that warn on Python 3.12+
          sed -i \
            's/re\.compile("channel (\\d+)")/re.compile(r"channel (\\d+)")/g;
             s/re\.compile("type (\\w+)")/re.compile(r"type (\\w+)")/g' \
            "$WORK_DIR/krackattack/libwifi/wifi.py" 2>/dev/null || true

          # Patch the (possibly renamed) interface name into hostapd.conf
          sed -i "s/^interface=.*/interface=$INTERFACE/" "$WORK_DIR/krackattack/hostapd.conf" 2>/dev/null || true

          printf '%s\n' "KRACK attack"
          printf '%s\n' "  Interface : $INTERFACE"
          printf '%s\n' "  Attack    : $ATTACK ($ATTACK_FLAG)"
          printf '%s\n' ""
          printf '%s\n' "The script starts a rogue AP and waits for the target client to connect."
          printf '%s\n' "Ensure the target network SSID and passphrase match those in hostapd.conf."
          printf '%s\n' "Press Ctrl+C to stop."
          printf '%s\n' ""

          cd "$WORK_DIR/krackattack"
          # shellcheck disable=SC2086
          python3 krack-test-client.py $ATTACK_FLAG $DEBUG_FLAG
        '';
      };

      # Fast BSS Transition (802.11r) reinstallation attack.
      krackFtAttack = pkgs.writeShellApplication {
        name = "krack-ft-attack";
        runtimeInputs = [ krackattacks pythonEnv pkgs.iproute2 pkgs.iw pkgs.wpa_supplicant ];

        text = ''
          set -euo pipefail

          usage() {
            printf '%s\n' "Usage: krack-ft-attack <interface> <ssid> <psk>" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "  interface : wireless interface for the FT handshake test" >&2
            printf '%s\n' "  ssid      : SSID of the target WPA2 network" >&2
            printf '%s\n' "  psk       : passphrase of the target network" >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Tests key reinstallation in the Fast BSS Transition (802.11r) handshake." >&2
            printf '%s\n' "The target AP must have 802.11r (FT) enabled." >&2
            printf '%s\n' "" >&2
            printf '%s\n' "Example: krack-ft-attack wlan1 MyNetwork MyPassphrase" >&2
            exit 2
          }

          if [ "$#" -ne 3 ]; then
            usage
          fi

          INTERFACE="$1"
          SSID="$2"
          PSK="$3"

          if [ "$(id -u)" -ne 0 ]; then
            printf '%s\n' "This tool must be run as root." >&2
            exit 1
          fi

          if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
            printf '%s\n' "Interface does not exist: $INTERFACE" >&2
            exit 1
          fi

          WORK_DIR="$(mktemp -d)"
          ORIG_IFACE=""

          cleanup() {
            rm -rf "$WORK_DIR"
            # Restore original interface name if we renamed it
            if [ -n "$ORIG_IFACE" ]; then
              ip link set "$INTERFACE" down 2>/dev/null || true
              ip link set "$INTERFACE" name "$ORIG_IFACE" 2>/dev/null || true
              ip link set "$ORIG_IFACE" up 2>/dev/null || true
            fi
          }
          trap cleanup EXIT INT TERM

          mkdir -p "$WORK_DIR/krackattack"
          cp -rL ${krackattacks}/share/krackattack/. "$WORK_DIR/krackattack/"
          chmod -R u+w "$WORK_DIR"

          # Fix invalid escape sequences in upstream scripts that warn on Python 3.12+
          sed -i \
            's/re\.compile("channel (\\d+)")/re.compile(r"channel (\\d+)")/g;
             s/re\.compile("type (\\w+)")/re.compile(r"type (\\w+)")/g' \
            "$WORK_DIR/krackattack/libwifi/wifi.py" 2>/dev/null || true

          # Linux limits interface names to 15 chars. The script appends "mon" to
          # create a monitor interface, so the base name must be at most 12 chars.
          # Temporarily rename if needed.
          MON_CANDIDATE="''${INTERFACE}mon"
          if [ "''${#MON_CANDIDATE}" -gt 15 ]; then
            SHORT="wlft0"
            for n in 0 1 2 3 4 5 6 7 8 9; do
              SHORT="wlft$n"
              if ! ip link show "$SHORT" >/dev/null 2>&1; then break; fi
            done
            printf '%s\n' "Interface name '$INTERFACE' too long for monitor naming — renaming to '$SHORT'."
            ip link set "$INTERFACE" down
            ip link set "$INTERFACE" name "$SHORT"
            ip link set "$SHORT" up
            ORIG_IFACE="$INTERFACE"
            INTERFACE="$SHORT"
          fi

          # Generate wpa_supplicant.conf for the target network with FT-PSK enabled
          cat > "$WORK_DIR/krackattack/wpa.conf" << EOF
ctrl_interface=/tmp/krack_wpa_ctrl
network={
    ssid="$SSID"
    psk="$PSK"
    key_mgmt=FT-PSK WPA-PSK
    proto=RSN
}
EOF

          printf '%s\n' "KRACK Fast BSS Transition (802.11r) attack"
          printf '%s\n' "  Interface : $INTERFACE"
          printf '%s\n' "  SSID      : $SSID"
          printf '%s\n' ""
          printf '%s\n' "The target AP must have 802.11r (Fast BSS Transition) enabled."
          printf '%s\n' "Press Ctrl+C to stop."
          printf '%s\n' ""

          cd "$WORK_DIR/krackattack"
          python3 krack-ft-test.py \
            wpa_supplicant -D nl80211 -i "$INTERFACE" -c "$WORK_DIR/krackattack/wpa.conf"
        '';
      };

    in
    {
      packages.${system} = {
        inherit krackattacks;
        krack-attack = krackAttack;
        krack-ft-attack = krackFtAttack;
        default = krackAttack;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${krackAttack}/bin/krack-attack";
        };
        ft = {
          type = "app";
          program = "${krackFtAttack}/bin/krack-ft-attack";
        };
      };
    };
}
