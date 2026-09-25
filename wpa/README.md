# WPA attacks

WPA/WPA2 attack testing using [wifite2](https://github.com/derv82/wifite2) for
automated attacks.

## Prerequisites

- Root privileges
- A wireless adapter that supports monitor mode (see `check-monitor-mode`)

## Tools exposed

| Command | Description |
|---|---|
| `nix run .` | `wpa-attack` - automated wifite2 wrapper |

## WPA attack (automated)

### Usage

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- <interface> [bssid] [output-dir]
```

| Argument | Required | Description |
|---|---|---|
| `interface` | yes | Wireless interface to use |
| `bssid` | no | Target a specific AP; omit to scan and attack all WPA APs |
| `output-dir` | no | Directory for captured handshakes and results (default: current dir) |

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `WPA_MODE` | `both` | Attack method: `both`, `handshake` or `pmkid` |
| `WPA_TIMEOUT` | `300` | Seconds to spend per target on handshake capture |
| `PMKID_TIMEOUT` | `150` | Seconds to spend per target on PMKID capture |
| `WORDLIST` | - | Path to a wordlist; enables immediate cracking after capture |

### Attack modes

| Mode | Method | Client required | Description |
|---|---|---|---|
| `both` (default) | PMKID then handshake | No / Yes | Tries PMKID first; falls back to deauth + handshake capture |
| `handshake` | 4-way handshake | Yes | Deauths a connected client to force a fresh handshake |
| `pmkid` | PMKID via hcxdumptool | No | Associates with the AP without deauthing any client |

### Examples

Scan for all WPA APs and run both capture methods:

```bash
sudo nix run . -- wlan1
```

PMKID-only against a specific AP (quieter, no deauth):

```bash
WPA_MODE=pmkid sudo nix run . -- wlan1 AA:BB:CC:DD:EE:FF /tmp/wpa
```

Capture and immediately attempt to crack with a wordlist:

```bash
WORDLIST=/path/to/rockyou.txt sudo nix run . -- wlan1 AA:BB:CC:DD:EE:FF /tmp/wpa
```

Crack a captured handshake manually:

```bash
# aircrack-ng (CPU)
aircrack-ng -w /path/to/wordlist.txt capture.cap

# hashcat (GPU, faster) - convert first
hcxpcaptool -z capture.pmkid capture.pcapng
hashcat -m 22000 capture.pmkid /path/to/wordlist.txt
```

## Notes

- `wifite2` manages monitor mode switching and process cleanup automatically.
  `--kill` is passed so NetworkManager and wpa_supplicant are stopped before
  the attack starts.
- PMKID attacks do not require any connected clients and generate less noise on
  the air than deauth-based handshake capture. Prefer `WPA_MODE=pmkid` when
  stealth matters.
- Captured handshakes are saved as `.cap` files in `output-dir`; PMKID hashes
  as `.pmkid` files. Both formats are accepted by `hashcat` (`-m 22000`).
