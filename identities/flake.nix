{
	description = "Collect passive Wi-Fi network and client identity details";

	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
	};

	outputs = { self, nixpkgs }:
		let
			system = "x86_64-linux";
			pkgs = import nixpkgs { inherit system; };
		in
		{
			packages.${system}.wifi-identities = pkgs.writeShellApplication {
				name = "wifi-identities";
				runtimeInputs = with pkgs; [
					aircrack-ng
					coreutils
					iproute2
					util-linux
				];

				text = ''
					set -euo pipefail

					INTERFACE="''${1:-wlan0}"
					DURATION="''${2:-30}"
					OUT_DIR="''${3:-$PWD/wifi-identity-captures}"

					usage() {
						printf '%s\n' "Usage: wifi-identities <monitor-interface> [duration-seconds] [output-directory]"
						printf '%s\n' "Example: wifi-identities wlp196s0f3u1 60 ./captures"
					}

					if [ "$#" -gt 3 ]; then
						usage >&2
						exit 2
					fi

					case "$DURATION" in
						""|*[!0-9]*)
							printf '%s\n' "Duration must be a positive integer." >&2
							exit 2
							;;
					esac
					if [ "$DURATION" -lt 1 ]; then
						printf '%s\n' "Duration must be greater than zero." >&2
						exit 2
					fi

					if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
						printf '%s\n' "Wireless interface does not exist: $INTERFACE" >&2
						exit 1
					fi

					mkdir -p "$OUT_DIR"
					TIMESTAMP="$(date -u +'%Y%m%dT%H%M%SZ')"
					PREFIX="$OUT_DIR/$TIMESTAMP-$INTERFACE"

					printf '%s\n' "Collecting passive Wi-Fi identity details"
					printf '%s\n' "Interface: $INTERFACE"
					printf '%s\n' "Duration: $DURATION seconds"
					printf '%s\n' "Output prefix: $PREFIX"
					printf '%s\n' "The interface must already be in monitor mode."
					printf '%s\n' "Press Ctrl+C to stop early."

					 timeout --signal=INT --kill-after=5s "''${DURATION}s" \
						airodump-ng \
							--band abg \
							--write-interval 1 \
							--output-format csv \
							-w "$PREFIX" \
							"$INTERFACE" || STATUS=$?

					STATUS="''${STATUS:-0}"
					if [ "$STATUS" -ne 0 ] && [ "$STATUS" -ne 124 ] && [ "$STATUS" -ne 130 ]; then
						printf '%s\n' "airodump-ng failed with status $STATUS." >&2
						exit "$STATUS"
					fi

					printf '%s\n' "Identity data written to: $PREFIX-01.csv"
				'';
			};

			apps.${system}.default = {
				type = "app";
				program = "${self.packages.${system}.wifi-identities}/bin/wifi-identities";
			};
		};
}
