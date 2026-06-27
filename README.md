# WiBluetooth

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-green.svg)](https://github.com/mediafill/wibluetooth)

**Multi-interface network bonding for Linux. Combine WiFi, Ethernet, and Bluetooth for aggregated bandwidth and faster downloads.**

A free, open-source Linux network load balancer that bonds multiple internet connections into a single proxy. Similar to commercial channel bonding solutions like Speedify, but runs entirely on your machine with no cloud dependency, no subscriptions, and no data caps.

## Quick Install

```bash
bash <(curl -sL https://raw.githubusercontent.com/mediafill/wibluetooth/main/install.sh)
```

Or clone and run:

```bash
git clone https://github.com/mediafill/wibluetooth.git
cd wibluetooth
chmod +x install.sh
./install.sh
```

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────┐
│  Your App       │────▶│  HTTP Bridge     │────▶│  SOCKS5     │────▶ Internet
│  (browser, TUI, │     │  (localhost:8888)│     │  dispatch   │
│   aria2, curl)  │     └──────────────────┘     │  (:1080)    │
└─────────────────┘                              └──────┬──────┘
                                                        │
                              ┌──────────────────────────┼──────────────────────┐
                              │                          │                      │
                        ┌─────▼─────┐            ┌──────▼──────┐        ┌──────▼──────┐
                        │  WiFi     │            │  Ethernet   │        │  Bluetooth  │
                        │  (wlo1)   │            │  (enx...)   │        │  (bnep0)    │
                        └───────────┘            └─────────────┘        └─────────────┘
```

**Why two proxy ports?**
- **HTTP proxy (8888)** — Works with ALL apps including TUI tools, Node.js fetch(), Python requests, etc.
- **SOCKS5 (1080)** — Works with multi-threaded downloaders (aria2, wget2) for bandwidth aggregation

## Usage

### Desktop
- **Click** the WiBluetooth icon to toggle proxy on/off
- **Right-click** for Start / Stop / Restart / Status / Health / List / Heal

### Command Line

```bash
# Start bonding all interfaces
dispatch-toggle.sh start

# Stop (revert to direct connection)
dispatch-toggle.sh stop

# Restart (stop + start)
dispatch-toggle.sh restart

# Toggle on/off
dispatch-toggle.sh toggle

# List all detected network interfaces
dispatch-toggle.sh list

# Full health check with end-to-end test
dispatch-toggle.sh health

# Auto-heal (fix stale processes, verify deps, reconnect Bluetooth)
dispatch-toggle.sh heal

# Show proxy status notification
dispatch-toggle.sh status
```

### Auto-source Proxy Environment

After installation, new terminal sessions auto-source the proxy:

```bash
# Manual source (current session)
source ~/.wibluetooth-env

# Verify it's set
env | grep -i proxy
```

### Use with Applications

```bash
# Set HTTP proxy (works with everything)
export http_proxy=http://localhost:8888
export https_proxy=http://localhost:8888

# Or SOCKS5 (better for multi-threaded downloads)
export all_proxy=socks5://localhost:1080

# aria2 (multi-threaded downloader — recommended)
aria2c -x16 --all-proxy=socks5://localhost:1080 https://example.com/file.zip

# curl
curl --proxy http://localhost:8888 https://example.com
curl -x socks5://localhost:1080 https://example.com

# wget
wget -e use_proxy=yes -e http_proxy=http://localhost:8888 https://example.com/file.zip

# Python requests
export HTTPS_PROXY=http://localhost:8888
python3 -c "import requests; print(requests.get('https://ifconfig.me').text)"

# Node.js / Deno (the HTTP bridge fixes "UnsupportedProxyProtocol")
export HTTP_PROXY=http://localhost:8888
node -e "fetch('https://ifconfig.me').then(r=>r.text()).then(console.log)"
```

### Browser Optimization (Chrome/Edge/Brave)

Enable parallel downloading in your browser to split files into multiple chunks — this works perfectly with WiBluetooth's load balancing:

1. Open `chrome://flags` in your address bar
2. Search for **Parallel Downloading**
3. Set to **Enabled**
4. Click **Relaunch**

This creates multiple connections per download, which distributes across your bonded interfaces for faster speeds.

## Requirements

- Linux with systemd (most modern distros)
- At least one active network connection
- `bash`, `curl`, `python3`, `node`, `npm`
- `bluez`, `network-manager`, `iproute2`, `psmisc` (auto-installed)

## Auto-Healing

WiBluetooth includes a watchdog daemon that monitors every 30 seconds:

- **SOCKS5 proxy dies** → auto-restarts with all detected interfaces
- **HTTP bridge dies** → auto-restarts the Python bridge
- **Proxy unresponsive** → kills and restarts
- **Bluetooth disconnects** → re-activates via NetworkManager
- **Busy ports** → kills stale processes before starting

Run `dispatch-toggle.sh heal` for manual recovery.

## Troubleshooting

### Proxy won't start

```bash
# Full auto-heal
dispatch-toggle.sh heal

# Then start
dispatch-toggle.sh start

# Check what's wrong
dispatch-toggle.sh health
```

### "UnsupportedProxyProtocol" error in TUI apps

This means your app is seeing a `socks5://` proxy it can't handle. Fix:

```bash
# Source the HTTP proxy env vars
source ~/.wibluetooth-env

# Or manually set HTTP proxy
export http_proxy=http://localhost:8888
export https_proxy=http://localhost:8888
```

The HTTP bridge (port 8888) translates HTTPS CONNECT requests through the SOCKS5 proxy, so all apps work.

### Bluetooth not connecting

1. **Enable Bluetooth tethering on your phone:**
   - Android: Settings → Network & Internet → Hotspot & tethering → Bluetooth tethering
   - iPhone: Settings → Personal Hotspot → Allow Others to Join

2. **Pair the phone:**
   ```bash
   bluetoothctl
   [bluetooth]# pair 74:B0:59:XX:XX:XX
   [bluetooth]# trust 74:B0:59:XX:XX:XX
   [bluetooth]# connect 74:B0:59:XX:XX:XX
   ```

3. **Activate the connection:**
   ```bash
   nmcli connection up "Your Phone Name"
   ```

4. **Start WiBluetooth:**
   ```bash
   dispatch-toggle.sh start
   ```

### Bluetooth connects but no IP (bnep0 not created)

The bnep0 interface may be renamed by NetworkManager. Check:

```bash
# List all interfaces with IPs
dispatch-toggle.sh list

# Check nmcli device status
nmcli device status

# If Bluetooth shows "connected" but no IP, restart the connection:
nmcli connection down "Your Phone Name"
nmcli connection up "Your Phone Name"
```

### Only WiFi detected (no Bluetooth/Ethernet)

```bash
# Check what interfaces exist
ip link show

# Check nmcli
nmcli device status

# Force re-detect
dispatch-toggle.sh list

# If Bluetooth is paired but not showing, try:
bluetoothctl power off
sleep 2
bluetoothctl power on
dispatch-toggle.sh start
```

### Proxy starts but apps can't connect

```bash
# Check if proxy is listening
ss -tlnp | grep -E "8888|1080"

# Test proxy directly
curl --proxy http://localhost:8888 http://ifconfig.me
curl --socks5-hostname localhost:1080 http://ifconfig.me

# Check firewall
sudo iptables -L -n | grep -E "8888|1080"

# Kill any stale processes
dispatch-toggle.sh stop
sleep 2
dispatch-toggle.sh start
```

### Port already in use

```bash
# Find what's using the port
fuser 8888/tcp
fuser 1080/tcp

# Kill it
sudo fuser -k 8880/tcp
sudo fuser -k 1080/tcp

# Or use the built-in heal
dispatch-toggle.sh heal
```

### Watchdog not running

```bash
# Check watchdog
cat /tmp/wibluetooth-watchdog.pid
kill -0 $(cat /tmp/wibluetooth-watchdog.pid) 2>/dev/null && echo "alive" || echo "dead"

# Restart everything (includes watchdog)
dispatch-toggle.sh restart
```

### Proxy works for some sites but not others

Some sites block proxy connections. Try:

```bash
# Set no_proxy for local sites
export no_proxy=localhost,127.0.0.1,::1,.local

# Check if the site works without proxy
curl --noproxy '*' https://example.com
```

### Debug mode

```bash
# View SOCKS5 dispatch logs
cat /tmp/wibluetooth-dispatch.log

# View HTTP bridge logs
cat /tmp/wibluetooth-http.log

# Run with verbose output
bash -x dispatch-toggle.sh start 2>&1 | tail -50
```

### Reinstall from scratch

```bash
# Stop everything
dispatch-toggle.sh stop 2>/dev/null

# Remove old files
rm -f ~/.local/bin/dispatch-toggle.sh
rm -f ~/.local/bin/wibluetooth-proxy.py
rm -f ~/.local/bin/wibluetooth-watchdog.sh
rm -f ~/.wibluetooth-env
rm -f ~/Desktop/wibluetooth.desktop
rm -f ~/.local/share/applications/wibluetooth.desktop

# Reinstall
bash <(curl -sL https://raw.githubusercontent.com/mediafill/wibluetooth/main/install.sh)
```

## Supported Platforms

### Distros
| Distro | Status |
|--------|--------|
| Ubuntu / Debian | Full support |
| Fedora / RHEL / CentOS | Full support |
| Arch / Manjaro | Full support |
| openSUSE | Full support |
| Pop!_OS (COSMIC) | Full support |
| Alpine | Experimental |

### Desktop Environments
GNOME, KDE Plasma, XFCE, Cinnamon, MATE, LXQt, Budgie, Deepin, COSMIC, Pantheon, tiling WMs (i3, Sway, Hyprland).

## Key Files

| File | Purpose |
|------|---------|
| `~/.local/bin/dispatch-toggle.sh` | Main control script |
| `~/.local/bin/wibluetooth-proxy.py` | HTTP CONNECT → SOCKS5 bridge |
| `~/.local/bin/wibluetooth-watchdog.sh` | Auto-heal daemon |
| `~/.wibluetooth-env` | Proxy env vars (auto-sourced) |
| `~/Desktop/wibluetooth.desktop` | Desktop shortcut |
| `/tmp/wibluetooth-dispatch.log` | SOCKS5 proxy logs |
| `/tmp/wibluetooth-http.log` | HTTP bridge logs |
| `/tmp/wibluetooth-watchdog.pid` | Watchdog PID |

## Why WiBluetooth?

| Feature | WiBluetooth | Speedify | OpenMPTCProuter |
|---------|-------------|----------|-----------------|
| Price | Free | $8+/mo | Free (needs router) |
| Setup | 1 command | App install | Flash router |
| Linux native | Yes | No | Router OS |
| No cloud required | Yes | No | Yes |
| Auto-heal | Yes | No | No |
| HTTP + SOCKS5 | Yes | No | No |

## Related Projects

- [dispatch-proxy](https://github.com/alexkirsz/dispatch-proxy) — The underlying proxy engine
- [aria2](https://aria2.github.io/) — Multi-protocol download utility
- [Speedify](https://www.speedify.com) — Commercial channel bonding

## License

MIT License. Copyright (c) 2026 GET BIT LABS LLC. See [LICENSE](LICENSE).

---

**THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.** Use at your own risk. Network bonding may not work on all hardware. Bluetooth tethering requires a compatible phone. This is not a VPN.
