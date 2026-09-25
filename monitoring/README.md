# WLAN Monitoring with Kismet

This flake runs Kismet in a Nix environment so you can monitor wireless traffic from a compatible Wi-Fi adapter.

## Prerequisites

- A supported wireless adapter
- A Linux system with the required kernel modules and drivers
- An interface that supports monitor mode
- Root privileges to configure monitor mode and run Kismet
- Appropriate authorization and scope before monitoring any wireless traffic

## Run the flake

From this directory:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlp196s0f3u1
```

This configures `wlp196s0f3u1` for monitor mode and starts Kismet. If your adapter uses a different interface name, replace it with the correct one.

For a generic example:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan0
```

## Optional usage notes

```bash
nix run --extra-experimental-features 'nix-command flakes' . -- --help
```

The script prints guidance and logs under a local `kismet-logs` directory inside the monitoring folder.

## Kismet web interface

After Kismet starts successfully, open the web UI in your browser:

- http://localhost:2501

If the UI does not load immediately, wait a few seconds and confirm Kismet is still running.

## Monitor-mode setup

The flake configures the supplied interface automatically before starting Kismet:

1. Brings the interface down
2. Sets its type to monitor with `iw`
3. Brings the interface back up
4. Verifies that monitor mode is active

If the interface is managed by NetworkManager or another network service, that service may need to be stopped or configured not to reset the interface.

## Logging

Kismet writes logs under:

```text
./kismet-logs/
```
