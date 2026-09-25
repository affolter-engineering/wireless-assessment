# Wireless Adapter Inventory

This flake gathers basic information about the host and any wireless-capable adapters, then writes the results to a text report file.

## What it checks

- host information (`uname -a`)
- network interfaces (`ip link`)
- wireless interfaces (`iw dev`)
- USB devices (`lsusb`)
- PCI network devices (`lspci`)
- wireless details (`iwconfig`)
- loaded wireless-related kernel modules (`lsmod`)
- recent kernel log messages (`dmesg | tail -n 100`)

## Run it

From this directory:

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' .
```

This writes the report to:

```text
./wireless-adapter-report.txt
```

## Optional arguments

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- --output /tmp/wifi-report.txt
sudo nix run --extra-experimental-features 'nix-command flakes' . -- --quiet
sudo nix run --extra-experimental-features 'nix-command flakes' . -- --help
```

## Notes

- The script creates the destination directory automatically if it does not exist.
- The tool is intended for discovery and documentation only.
- Use the output to confirm the adapter is present, the correct driver is loaded and the interface is visible before attempting monitor mode or wireless testing.
