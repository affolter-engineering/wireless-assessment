# check-monitor-mode

Scans all wireless adapters present on the system and reports whether each one
supports monitor mode.

## Usage

```bash
nix run --extra-experimental-features 'nix-command flakes' .
```

No arguments required. The tool discovers adapters automatically via
`/sys/class/ieee80211`.

## Example output

```bash
PHY         INTERFACE(S)      DRIVER                MONITOR MODE
----------------------------------------------------------------------
phy0        wlan0             iwlwifi               NO
phy1        wlp196s0f3u1      rtl8xxxu              YES
----------------------------------------------------------------------
Result: 1 of 2 adapter(s) support monitor mode.
```

## Columns

| Column | Description |
|---|---|
| `PHY` | Kernel PHY identifier (`phy0`, `phy1`, …) |
| `INTERFACE(S)` | Network interface name(s) bound to that PHY |
| `DRIVER` | Kernel driver in use, resolved from sysfs |
| `MONITOR MODE` | `YES` if the driver/firmware exposes monitor mode |

## Notes

- Root is not required. A warning is printed if running unprivileged and
  certain sysfs entries are inaccessible.
- Monitor mode support is read directly from `iw phy <phy> info` - it reflects
  what the kernel driver advertises, not what the firmware will actually accept.
  Some adapters advertise support but fail when the mode is applied.
- A `NO` result for the built-in adapter (typically `phy0` / `wlan0` on
  laptops) is normal - most Intel and Broadcom chips do not expose monitor mode.
