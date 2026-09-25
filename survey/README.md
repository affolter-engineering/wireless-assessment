# Airspace Survey with airodump-ng

This flake runs `airodump-ng` against a wireless interface in monitor mode so you can survey nearby access points and clients.

## Prerequisites

- A compatible wireless adapter
- A Linux interface in monitor mode
- Appropriate authorization and scope before scanning any wireless environment

## Run the flake

From this directory:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlp196s0f3u1
```

This starts `airodump-ng` on the `wlp196s0f3u1` interface. Replace the interface name if needed.

For a generic example:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan0
```

## Optional filters

Limit the scan to one channel:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan0 6
```

Limit the scan to one BSSID:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan0 6 AA:BB:CC:DD:EE:FF
```

## Capture output

The tool writes capture files under:

```text
./airodump-captures/
```

## Example monitor-mode setup

```bash
sudo ip link set wlan0 down
sudo iw dev wlan0 set monitor control
sudo ip link set wlan0 up
```

Then start the survey:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan0
```

## Important warning

Use this only within scope and with explicit authorization. Wireless surveying may be restricted by local laws, policies and client rules.
