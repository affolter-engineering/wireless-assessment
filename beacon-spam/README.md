# Beacon Spamming with mdk3

This flake builds `mdk3` from the pinned `aircrack-ng/mdk3` source repository and provides a wrapper for sending beacon frames from a monitor-mode wireless interface.

Use this only on wireless networks and equipment that you own or are explicitly authorized to test. Beacon spamming can disrupt nearby networks and clients.

## Prerequisites

- Linux with Nix and flakes enabled
- A compatible wireless adapter that supports monitor mode
- Root privileges
- Authorization for the test environment
- Network access on the first build so Nix can fetch the `mdk3` source

The flake currently targets `x86_64-linux`.

## Find the wireless interface

List wireless interfaces with:

```bash
iw dev
```

You can also inspect the adapter inventory using the hardware flake in `../hardware`.

## Enable monitor mode

Stop services that may manage the adapter, then configure monitor mode. The exact commands depend on the driver and distribution. A basic example is:

```bash
sudo ip link set wlan0 down
sudo iw dev wlan0 set monitor control
sudo ip link set wlan0 up
```

Replace `wlan0` with the actual interface name reported by `iw dev`.

## Run the flake

From this directory, run the default command:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' .
```

Provide only the wireless interface to use the default SSID, channel and frame count:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlp196s0f3u1
```

The interface must already be configured for monitor mode before running the flake.

The default values are:

| Argument | Default | Description |
| --- | --- | --- |
| 1 | `wlan0` | Monitor-mode interface |
| 2 | `TestBeaconSpam` | SSID used in beacon frames |
| 3 | `6` | Wireless channel |
| 4 | `1000` | Number of beacon frames |

Pass custom values in that order:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan0 TestNetwork 11 500
```

The wrapper invokes `mdk3` in beacon mode:

```text
mdk3 <interface> b -n <ssid> -c <channel> -s <count>
```

Press `Ctrl+C` to stop the command.

## Validate or build

Check that the flake evaluates without creating a lock-file change:

```bash
nix flake check --no-write-lock-file
```

Build the application without running it:

```bash
nix build --extra-experimental-features 'nix-command flakes' --no-link --print-build-logs .#beacon-spam
```

The first build compiles the pinned `mdk3` source locally.

## Troubleshooting

Confirm that the interface exists and is in monitor mode:

```bash
iw dev
ip link show wlan0
```

If the command reports that `mdk3` is unavailable, rebuild the flake and check the build output:

```bash
nix build --no-link --print-build-logs .#beacon-spam
```

The wrapper requires root because it changes wireless behavior and transmits management frames.
