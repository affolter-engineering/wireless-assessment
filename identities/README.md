# Wi-Fi Identity Collection

This flake passively collects wireless network and client identity details with `airodump-ng`. It records information visible in management and data-frame metadata, including:

- SSIDs and BSSIDs
- channels and operating bands
- signal levels
- encryption, cipher and authentication information when advertised
- observed client MAC addresses and associated access points
- first-seen and last-seen timestamps reported by `airodump-ng`

The flake does not transmit deauthentication frames or otherwise attack the networks it observes.

## Prerequisites

- Linux with Nix and flakes enabled
- A compatible wireless adapter that supports monitor mode
- Root privileges
- A wireless interface already configured in monitor mode
- Authorization for the assessment
- The first run needs network access to fetch the flake input and packages

The flake currently targets `x86_64-linux`.

## Prepare monitor mode

The flake does not change the interface mode. Configure it before running the collector. For example:

```bash
sudo ip link set wlp196s0f3u1 down
sudo iw dev wlp196s0f3u1 set monitor control
sudo ip link set wlp196s0f3u1 up
```

Confirm the interface before starting:

```bash
iw dev
```

## Run the flake

From this directory, use the default interface, duration and output directory:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' .
```

To collect data from a specific interface, such as `wlp196s0f3u1`:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlp196s0f3u1
```

The default duration is 30 seconds. Supply a custom duration in seconds:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlp196s0f3u1 60
```

You can also select the output directory:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- \
  wlp196s0f3u1 60 ./captures
```

The arguments are:

| Argument | Default | Description |
| --- | --- | --- |
| 1 | `wlan0` | Existing monitor-mode interface |
| 2 | `30` | Capture duration in seconds |
| 3 | `./wifi-identity-captures` | Output directory |

The collector sends an interrupt after the requested duration. If `airodump-ng` does not exit within five additional seconds, `timeout` forcibly terminates it. Press `Ctrl+C` to stop early.

## Output files

Each run creates timestamped `airodump-ng` CSV output in the selected directory. For example:

```text
wifi-identity-captures/20260915T120000Z-wlp196s0f3u1-01.csv
```

The CSV contains separate access-point and station sections. Review both sections when correlating network identities with observed clients.

## Validate or build

Check the flake without running a capture:

```bash
nix flake check --extra-experimental-features 'nix-command flakes' --no-write-lock-file
```

Build the collector without running it:

```bash
nix build --extra-experimental-features 'nix-command flakes' \
  --no-link --print-build-logs .#wifi-identities
```

## Troubleshooting

If the interface is not found, verify its name with `iw dev` and pass that name as the first argument. If `airodump-ng` reports that the interface is not suitable for capture, configure monitor mode before running the flake and stop network-management services that may change the interface state.
