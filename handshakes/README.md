# WLAN Handshake Capture

This flake captures wireless handshakes with `airodump-ng` and can optionally force a reconnection with `aireplay-ng` to trigger a fresh WPA/WPA2 handshake.

## Prerequisites

- A compatible wireless adapter
- A Linux interface in monitor mode
- The target BSSID and, optionally, the client MAC address

## Run the flake

From this directory:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlp196s0f3u1 6 AA:BB:CC:DD:EE:FF 00:11:22:33:44:55
```

This targets the interface `wlp196s0f3u1`, the channel `6`, the BSSID `AA:BB:CC:DD:EE:FF` and the client `00:11:22:33:44:55`.

If you do not know the client MAC, omit it:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan0 6 AA:BB:CC:DD:EE:FF
```

## Capture output

Files are saved under:

```text
./handshake-captures/
```

The output is timestamped and uses the interface and BSSID in the filename.

## Example monitor-mode setup

```bash
sudo ip link set wlan0 down
sudo iw dev wlan0 set monitor control
sudo ip link set wlan0 up
```

Then run the capture:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan0 6 AA:BB:CC:DD:EE:FF
```
