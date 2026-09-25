# ap-clients

Enumerates all access points in range together with their associated clients
and writes the result to a timestamped text report.

Uses `airodump-ng` for the capture and enables monitor mode automatically.

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
| `SCAN_TIMEOUT` | `60` | Capture duration in seconds |
| `SCAN_CHANNEL` | — | Lock to one channel instead of hopping all channels |

## Examples

```bash
# 60-second full-spectrum scan
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlp198s0f3u1i3

# Longer scan for quieter environments
SCAN_TIMEOUT=180 \
  sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlp198s0f3u1i3

# Lock to channel 6 only
SCAN_CHANNEL=6 \
  sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlp198s0f3u1i3
```

## Output

The report is printed to stdout and saved to:

```
./ap-client-reports/ap-clients-<timestamp>.txt
```

Example report:

```text
AP + Client Report
Generated  : 20260917T091500Z
Interface  : wlp198s0f3u1i3 (wlp198s0f3u1i3mon)
Duration   : 60 seconds
APs seen   : 3
Clients    : 5

--------------------------------------------------------------------------------
AP    : AA:BB:CC:DD:EE:FF  CH 6    -52 dBm  WPA2/CCMP/PSK
ESSID : BWGV-HUB
  +-- 11:22:33:44:55:66  -61 dBm  142 pkts
  +-- 77:88:99:AA:BB:CC  -74 dBm   38 pkts  probes: BWGV-HUB
--------------------------------------------------------------------------------
AP    : 11:22:33:44:55:00  CH 11   -78 dBm  WPA2/CCMP/PSK
ESSID : Nachbar-WLAN
       (no associated clients observed)
--------------------------------------------------------------------------------

Unassociated Clients
--------------------------------------------------------------------------------
  DD:EE:FF:00:11:22  -80 dBm  12 pkts  probes: HomeNet, CorpWifi
--------------------------------------------------------------------------------
```

Fields per AP line: BSSID, channel, signal strength, security suite.

Fields per client line: MAC address, signal strength, packet count, and any
SSIDs the client has been observed probing for.
