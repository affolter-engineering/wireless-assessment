# Beacon sniffing

Passive 802.11 beacon frame sniffer with channel hopping.

Captures beacon frames broadcast by access points, streams them to stdout,
and writes a deduplicated report sorted by signal strength on exit.

## Prerequisites

- Root privileges
- A wireless adapter that supports monitor mode (use `check-monitor-mode/` to verify)

## Usage

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- <interface>
```

| Argument | Required | Description |
|---|---|---|
| `interface` | yes | Wireless interface (monitor mode enabled automatically) |

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `BEACON_TIMEOUT` | `0` | Stop after n seconds (0 = run indefinitely) |
| `BEACON_CHANNEL` | — | Lock to one channel instead of hopping |
| `BEACON_UNIQUE` | `1` | `1` = one line per AP in live view, `0` = show every frame |

## Examples

```bash
# Hop all channels, stream one line per AP
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlp198s0f3u1i3

# Stop automatically after 60 seconds
BEACON_TIMEOUT=60 sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlp198s0f3u1i3

# Lock to channel 6, show every beacon frame
BEACON_CHANNEL=6 BEACON_UNIQUE=0 sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlp198s0f3u1i3
```

## Live output

```text
TIME                  BSSID               CH    SSID                              SIGNAL
--------------------------------------------------------------------------------
2026-09-17 10:00:01  aa:bb:cc:dd:ee:ff   6     BWGV-HUB                         -52 dBm
2026-09-17 10:00:02  11:22:33:44:55:66   11    Nachbar-WLAN                      -74 dBm
```

## Report file

On Ctrl+C or when `BEACON_TIMEOUT` expires the report is written to:

```bash
./beacon-reports/beacons-<timestamp>.txt
```

APs are deduplicated by BSSID and sorted by best observed signal strength
(strongest first).

```text
Beacon Scan Report
Generated:   20260917T100000Z
Interface:   wlp198s0f3u1i3 (wlp198s0f3u1i3mon)
APs found:   8
Frames:      2341

BSSID               CH    SSID                              SIGNAL    BEACONS
--------------------------------------------------------------------------------
aa:bb:cc:dd:ee:ff    6    BWGV-HUB                         -52 dBm      847
11:22:33:44:55:66   11    Nachbar-WLAN                      -74 dBm      312
...
```

- **SIGNAL** — best (strongest) signal observed for that AP
- **BEACONS** — total beacon frames captured from that AP

## Channel hopping

By default hops across 2.4 GHz (channels 1–13) and common 5 GHz channels
(36–64, 100–112, 149–161) with a 300 ms dwell per channel.
Set `BEACON_CHANNEL=<n>` to lock to one channel.
