# WLAN Deauthentication Testing

This flake provides a wrapper around `aireplay-ng` for controlled deauthentication testing on a wireless network.

Deauthentication frames can disconnect wireless clients and disrupt network access.

## Prerequisites

- Linux with Nix and flakes enabled
- A compatible wireless adapter that supports monitor mode
- Root privileges
- The target BSSID and wireless channel
- Explicit written permission for the test

The flake currently targets `x86_64-linux`.

## Find the wireless interface

List wireless interfaces with:

```bash
iw dev
```

As with the other WLAN flakes in this project, configure the interface in monitor mode before starting the test. The flake does not change the interface mode itself. A basic example is:

```bash
sudo ip link set wlan0 down
sudo iw dev wlan0 set monitor control
sudo ip link set wlan0 up
```

Replace `wlan0` with the actual interface name reported by `iw dev`.

## Run the flake

From this directory, run a test against all clients associated with the target BSSID:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- \
  wlan0 6 AA:BB:CC:DD:EE:FF

To target one client, add its MAC address:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- \
  wlan0 6 AA:BB:CC:DD:EE:FF 00:11:22:33:44:55
```

The arguments are:

| Argument | Description |
| --- | --- |
| 1 | Monitor-mode wireless interface |
| 2 | Wireless channel |
| 3 | Target access point BSSID |
| 4 | Path to a non-empty written permission file |
| 5 | Optional target client MAC address |

The wrapper invokes `aireplay-ng` with a default count of five deauthentication frames. Stop the test with `Ctrl+C`.

## Set the frame count

Set `DEAUTH_COUNT` for a different positive count:

```bash
sudo env DEAUTH_COUNT=3 nix run --extra-experimental-features 'nix-command flakes' . -- \
  wlan0 6 AA:BB:CC:DD:EE:FF
```

Use the smallest count needed for the authorized test. Higher counts increase the potential for disruption.

## Validate or build

Check that the flake evaluates:

```bash
nix flake check --extra-experimental-features 'nix-command flakes' --no-write-lock-file
```

Build the application without running a wireless test:

```bash
nix build --extra-experimental-features 'nix-command flakes' --no-link --print-build-logs .#deauth-test
```

## Troubleshooting

Confirm that the interface exists and is in monitor mode:

```bash
iw dev
ip link show wlan0
```

If the wrapper refuses to start, verify that:

- the command is run with `sudo`
- `DEAUTH_COUNT` is a positive integer
- the interface, channel and BSSID match the authorized scope

## Safety and scope

Deauthentication affects client connectivity and may violate law, policy, or the authorization agreement when used outside the defined scope. Do not test public or third-party networks without documented permission.
