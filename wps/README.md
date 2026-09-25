# WPS attacks

WPS attack testing using wifite2 with Pixie Dust and PIN brute-force
methods. Requires a wireless adapter that supports monitor mode.

Use `check-monitor-mode` flake to verify.

## Prerequisites

- Root privileges
- A wireless adapter that supports monitor mode

## Usage

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- <interface> [bssid] [output-dir]
```

| Argument | Required | Description |
|---|---|---|
| `interface` | yes | Wireless interface to use |
| `bssid` | no | Target a specific AP; omit to scan and attack all WPS APs |
| `output-dir` | no | Directory for result files (default: current dir) |

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `WPS_MODE` | `both` | Attack method: `pixie`, `pin`, or `both` |
| `WPS_TIMEOUT` | `300` | Seconds to spend per target |

## Examples

Scan for all WPS-enabled APs and attack them:

```bash
sudo nix run . -- wlan1
```

Target a specific AP using Pixie Dust only (fast, no PIN brute-force):

```bash
WPS_MODE=pixie sudo nix run . -- wlan1 AA:BB:CC:DD:EE:FF /tmp/wps
```

Run PIN brute-force only with a longer timeout:

```bash
WPS_MODE=pin WPS_TIMEOUT=600 sudo nix run . -- wlan1 AA:BB:CC:DD:EE:FF
```

## Attack modes

| Mode | Tool | Description |
|---|---|---|
| `pixie` | pixiewps + reaver/bully | Recovers the WPS PIN from weak random-number generators; completes in seconds against vulnerable APs |
| `pin` | reaver / bully | Brute-forces the 8-digit WPS PIN; slow (hours) but works on APs not vulnerable to Pixie Dust |
| `both` (default) | both | Tries Pixie Dust first, falls back to PIN |

## Notes

- wifite2 manages monitor mode switching and process cleanup automatically.
  `--kill` is passed so conflicting processes (NetworkManager, wpa_supplicant)
  are stopped automatically before the attack starts.
- Results (recovered PINs, PSKs) are written to `output-dir` by wifite2.
- WPS lockout: many APs lock after a number of failed PIN attempts. Use
  `WPS_MODE=pixie` first to avoid triggering the lockout before trying PIN.
