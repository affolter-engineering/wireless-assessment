# Evil Twin Access Point

This flake creates a cloned wireless access point using `hostapd` and `dnsmasq` for authorized testing in a controlled lab or approved engagement environment.

## Prerequisites

- Root privileges
- A compatible wireless adapter that supports AP mode or virtual AP creation
- A Linux interface that can be used for the evil-twin SSID
- Explicit written authorization and scope before using this tool

## Run the flake

From this directory:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- DemoAP wlan0 6
```

This creates an AP named `DemoAP` on interface `wlan0` on channel `6`.

You can replace the SSID, interface and channel as needed:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- MyTestAP wlan1 11
```

## Important notes

- This tool is intended only for authorized wireless testing.
- The script creates a DHCP and DNS service for the fake access point.
- The access point is only suitable for controlled and explicitly approved use.

## Access point files

The generated configuration files are written under:

```text
./evil-twin-data/
```

This includes:

- `hostapd.conf`
- `dnsmasq.conf`

## Warning

Use this only within scope and with explicit approval. Running an evil-twin access point without authorization may be illegal or violate policy.
