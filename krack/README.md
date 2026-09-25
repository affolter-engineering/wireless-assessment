# KRACK attack

KRACK (Key Reinstallation Attack) testing using
[krackattacks-scripts](https://github.com/vanhoefm/krackattacks-scripts) by Vanhoef.

Tests key reinstallation vulnerabilities in the WPA2 4-way handshake, group key
handshake and Fast BSS Transition (802.11r) handshake.

## Prerequisites

- Root privileges
- A wireless adapter that supports AP mode (to run the rogue AP)
- The target client must connect to the rogue AP - put it in range and configure
  the SSID/passphrase in `hostapd.conf` to match the target network

## Tools exposed

| Command | Description |
|---|---|
| `nix run .` | `krack-attack` - 4-way / group key / PTK reinstallation |
| `nix run .#ft` | `krack-ft-attack` - Fast BSS Transition (802.11r) attack |

## krack-attack (4-way handshake and group key)

### Usage

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- <interface> [attack]
```

| Argument | Required | Description |
|---|---|---|
| `interface` | yes | Wireless interface for the rogue AP |
| `attack` | no | Attack type (default: `fourway`) |

### Attack types

| Type | Description |
|---|---|
| `fourway` | 4-way handshake PTK reinstallation (default) |
| `group` | Group key handshake GTK reinstallation |
| `replay-broadcast` | Replay broadcast/multicast frames with reinstalled key |
| `replay-unicast` | Replay unicast frames with reinstalled PTK |
| `tptk` | Temporal PTK reinstallation |
| `tptk-rand` | Temporal PTK reinstallation with random ANonce |
| `gtkinit` | GTK reinstallation in initial 4-way handshake |

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `KRACK_DEBUG` | `0` | Set to `1` for verbose debug output |

### Examples

```bash
# 4-way handshake attack (most common - tests CVE-2017-13077)
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1

# Group key reinstallation
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1 group

# Temporal PTK reinstallation
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1 tptk

# With debug output
KRACK_DEBUG=1 sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1
```

## krack-ft-attack (Fast BSS Transition / 802.11r)

Tests key reinstallation in the FT handshake (CVE-2017-13082). The target AP
must have 802.11r enabled.

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' .#ft -- <interface>
```

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' .#ft -- wlan1
```

## How it works

The attack tool starts a rogue AP (using a modified hostapd) that mimics the
target network. When the victim client associates, the tool manipulates the
handshake to force nonce/key reinstallation:

1. The rogue AP completes the handshake normally up to message 3
2. It then retransmits message 3, causing the client to reinstall an already-used
   key with a reset nonce
3. With a reset nonce, an attacker can replay, decrypt, or forge frames

The attack is script-driven via `krack-test-client.py` from Vanhoef's research
toolkit. Results are printed to stdout showing whether the target is vulnerable.

## Notes

- KRACK affects the **client** side (the supplicant), not the AP. A patched
  client is not vulnerable even against a rogue AP running these scripts.
- Most modern clients (Linux wpa_supplicant ≥ 2.7 android ≥ 6 Nov 2017
  patch, iOS ≥ 11.1, Windows) have been patched. Embedded devices (IoT,
  older routers acting as clients) are the most likely remaining targets.
- The `fourway` attack (CVE-2017-13077) and `group` attack (CVE-2017-13078/80)
  are the most broadly applicable. `tptk` and `tptk-rand` target a subset of
  implementations that accept retransmitted message 1.
- The FT attack (CVE-2017-13082) requires 802.11r on the AP - uncomment and
  configure the `ieee80211r` options in the hostapd.conf work copy if needed.
