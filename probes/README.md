# Probe sniff

Passive 802.11 probe request sniffer with channel hopping.

Captures probe requests broadcast by Wi-Fi clients as they scan for known
networks. Each probe contains the client MAC address and optionally an SSID
(the network name the client is looking for). Broadcast/wildcard probes
(empty SSID) indicate the client is scanning for any available AP.

## Prerequisites

- Root privileges
- A wireless adapter that supports monitor mode (use `check-monitor-mode/`)

## Usage

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlp198s0f3u1i3 [output-file]
```

| Argument | Required | Description |
|---|---|---|
| `interface` | yes | Wireless interface (must support monitor mode) |
| `output-file` | no | Also write results to a CSV file |

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `PROBE_CHANNEL` | — | Lock to one channel instead of hopping |
| `PROBE_TIMEOUT` | `0` | Stop after n seconds (0 = run indefinitely) |
| `PROBE_UNIQUE` | `0` | Set to `1` to show each (client, SSID) pair only once |

## Examples

```bash
# Hop all channels, print to stdout
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1

# Write to CSV as well
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1 /tmp/probes.csv

# Deduplicate: one line per unique (client MAC, SSID) pair
PROBE_UNIQUE=1 \
  sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1 /tmp/probes.csv

# Lock to channel 6, stop after 60 seconds
PROBE_CHANNEL=6 PROBE_TIMEOUT=60 \
  sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1
```

## Output format

```text
TIME                  CLIENT MAC          SSID                              SIGNAL
--------------------------------------------------------------------------------
2026-09-16 14:03:21  aa:bb:cc:dd:ee:ff   HomeNetwork                       -62 dBm
2026-09-16 14:03:22  11:22:33:44:55:66   <broadcast>                       -74 dBm
```

- **TIME**: local timestamp of the captured frame
- **CLIENT MAC**: source MAC address of the probing device
- **SSID**: specific network being probed, or `<broadcast>` for wildcard scans
- **SIGNAL**: received signal strength in dBm (from the radiotap header)

CSV columns when writing to file: `timestamp,mac,ssid,signal_dbm`

## Channel hopping

By default the sniffer hops across 2.4 GHz (channels 1–13) and common
5 GHz channels (36–64, 100–112, 149–161) with a 300 ms dwell per channel.
Set `PROBE_CHANNEL=<n>` to lock to one channel instead.
