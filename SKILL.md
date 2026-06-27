# SKILL.md - WiBluetooth Installation & Operations

Copyright (c) 2026 GET BIT LABS LLC

## What is WiBluetooth?

WiBluetooth is a multi-interface network bonding tool for Linux that combines WiFi, Ethernet, and Bluetooth connections into a single load-balanced proxy for faster downloads. It uses `dispatch-proxy` (SOCKS5) + a Python HTTP CONNECT bridge for universal app compatibility.

## When to Use This Skill

Use this skill when the user wants to:
- Install WiBluetooth on their Linux system
- Combine multiple internet connections for faster downloads
- Set up channel bonding or network load balancing on Linux
- Bond WiFi and Bluetooth for aggregated bandwidth
- Install a free alternative to Speedify on Linux
- Fix proxy connectivity issues (UnsupportedProxyProtocol, connection refused, etc.)
- Debug Bluetooth PAN tethering
- Set up HTTP or SOCKS5 proxy for their applications

## Architecture

```
App → HTTP Bridge (:8888) → SOCKS5 dispatch-proxy (:1080) → [WiFi, Ethernet, Bluetooth]
```

Two proxy ports:
- **HTTP (8888)** — Universal, works with all apps including TUI tools, Node.js fetch(), Python requests
- **SOCKS5 (1080)** — Better for multi-threaded downloaders (aria2, wget2)

## Installation

### One-Line Install
```bash
bash <(curl -sL https://raw.githubusercontent.com/mediafill/wibluetooth/main/install.sh)
```

### Manual Install
```bash
git clone https://github.com/mediafill/wibluetooth.git
cd wibluetooth
chmod +x install.sh
./install.sh
```

### What the Installer Does
1. Detects Linux distro and package manager (apt/dnf/pacman/zypper/apk)
2. Installs system dependencies (Node.js, npm, Python3, bluez, network-manager, iproute2, psmisc, libnotify)
3. Installs `dispatch-proxy` via npm (with fallbacks: --unsafe-perm, yarn, pnpm)
4. Copies scripts to `~/.local/bin/`
5. Creates desktop shortcut with SVG icon
6. Sets up auto-source in ~/.bashrc, ~/.zshrc, /etc/profile.d/
7. Runs self-test to verify installation

### Dependencies
- **Required:** bash, curl, node, npm, python3
- **Bluetooth:** bluez, bluez-tools, network-manager
- **Network:** iproute2, psmisc (for fuser)
- **Notifications:** libnotify-bin / libnotify
- All auto-installed by the installer.

## Post-Installation Usage

### Commands
```bash
dispatch-toggle.sh start      # Start bonding all interfaces
dispatch-toggle.sh stop       # Stop (revert to direct connection)
dispatch-toggle.sh restart    # Stop + start
dispatch-toggle.sh toggle     # Toggle on/off
dispatch-toggle.sh list       # List all detected interfaces
dispatch-toggle.sh health     # Full health check with end-to-end test
dispatch-toggle.sh heal       # Auto-heal (kill stale, verify deps, reconnect BT)
dispatch-toggle.sh status     # Desktop notification with status
```

### Auto-source Proxy Env
```bash
source ~/.wibluetooth-env
```

This sets `http_proxy`, `https_proxy`, `all_proxy` (and uppercase variants) to `http://localhost:8888`.

### Application Configuration

#### HTTP proxy (universal — works with everything)
```bash
export http_proxy=http://localhost:8888
export https_proxy=http://localhost:8888
```

#### SOCKS5 (better for multi-threaded downloads)
```bash
export all_proxy=socks5://localhost:1080
```

#### Specific tools
```bash
# aria2 (recommended for multi-threaded downloads)
aria2c -x16 --all-proxy=socks5://localhost:1080 <url>

# curl
curl --proxy http://localhost:8888 <url>

# wget
wget -e use_proxy=yes -e http_proxy=http://localhost:8888 <url>

# Python requests
export HTTPS_PROXY=http://localhost:8888
python3 -c "import requests; print(requests.get('https://ifconfig.me').text)"

# Node.js / Deno (fixes "UnsupportedProxyProtocol")
export HTTP_PROXY=http://localhost:8888
node -e "fetch('https://ifconfig.me').then(r=>r.text()).then(console.log)"
```

## Bluetooth Setup

### Phone Configuration
1. Enable Bluetooth tethering:
   - Android: Settings → Network & Internet → Hotspot & tethering → Bluetooth tethering
   - iPhone: Settings → Personal Hotspot → Allow Others to Join

2. Pair from Linux:
```bash
bluetoothctl
[bluetooth]# pair 74:B0:59:XX:XX:XX
[bluetooth]# trust 74:B0:59:XX:XX:XX
[bluetooth]# connect 74:B0:59:XX:XX:XX
```

3. Activate:
```bash
nmcli connection up "Your Phone Name"
```

### Common Bluetooth Issues

**bnep0 interface not created:**
- NetworkManager may rename bnep0 to enx... (MAC-based name)
- Check with: `nmcli device status` and `dispatch-toggle.sh list`

**Bluetooth shows "connected" but no IP:**
```bash
nmcli connection down "Your Phone Name"
nmcli connection up "Your Phone Name"
```

**NAP connect timeout:**
- Toggle Bluetooth tethering OFF → wait 10s → ON on the phone
- Restart the phone if persistent
- Audio profiles (A2DP, HFP) can interfere — disconnect them

## Troubleshooting

### Quick Diagnosis
```bash
# What's running?
dispatch-toggle.sh health

# What interfaces exist?
dispatch-toggle.sh list

# What's in the logs?
cat /tmp/wibluetooth-dispatch.log
cat /tmp/wibluetooth-http.log

# Is the proxy listening?
ss -tlnp | grep -E "8888|1080"

# Can it reach the internet?
curl --proxy http://localhost:8888 http://ifconfig.me
```

### Common Issues

**"UnsupportedProxyProtocol" error:**
- App is seeing `socks5://` proxy it can't handle
- Fix: `source ~/.wibluetooth-env` or `export http_proxy=http://localhost:8888`

**Port already in use:**
```bash
fuser -k 8888/tcp; fuser -k 1080/tcp
dispatch-toggle.sh start
```

**Proxy starts but apps can't connect:**
- Check firewall: `sudo iptables -L -n | grep -E "8888|1080"`
- Check if proxy responds: `curl --proxy http://localhost:8888 http://example.com`

**Bluetooth not detected:**
- Check: `bluetoothctl show | grep Powered`
- Enable: `bluetoothctl power on`
- Re-pair if needed

**Watchdog not running:**
```bash
dispatch-toggle.sh restart  # Restarts everything including watchdog
```

### Debug Commands
```bash
# Verbose script execution
bash -x dispatch-toggle.sh start 2>&1 | tail -50

# Check all PID files
cat /tmp/wibluetooth-dispatch.pid /tmp/wibluetooth-http.pid /tmp/wibluetooth-watchdog.pid

# Check env vars
env | grep -i proxy
cat ~/.wibluetooth-env
```

### Reinstall from Scratch
```bash
dispatch-toggle.sh stop 2>/dev/null
rm -f ~/.local/bin/dispatch-toggle.sh ~/.local/bin/wibluetooth-proxy.py ~/.local/bin/wibluetooth-watchdog.sh
rm -f ~/.wibluetooth-env ~/Desktop/wibluetooth.desktop ~/.local/share/applications/wibluetooth.desktop
bash <(curl -sL https://raw.githubusercontent.com/mediafill/wibluetooth/main/install.sh)
```

## Key Files

| File | Purpose |
|------|---------|
| `~/.local/bin/dispatch-toggle.sh` | Main control script |
| `~/.local/bin/wibluetooth-proxy.py` | HTTP CONNECT → SOCKS5 bridge (pure Python stdlib) |
| `~/.local/bin/wibluetooth-watchdog.sh` | Auto-heal daemon (checks every 30s) |
| `~/.wibluetooth-env` | Proxy env vars (auto-sourced by new shells) |
| `~/Desktop/wibluetooth.desktop` | Desktop shortcut |
| `/tmp/wibluetooth-dispatch.log` | SOCKS5 proxy logs |
| `/tmp/wibluetooth-http.log` | HTTP bridge logs |

## Auto-Heal Behavior

The watchdog monitors:
1. SOCKS5 process alive + responsive → restarts if dead/unresponsive
2. HTTP bridge process alive → restarts if dead
3. Checks every 30 seconds
4. Re-detects all interfaces on restart (handles DHCP changes)

## Supported Platforms

- **Distros:** Ubuntu, Debian, Fedora, RHEL, CentOS, Arch, Manjaro, openSUSE, Pop!_OS, Alpine
- **Desktops:** GNOME, KDE, XFCE, Cinnamon, MATE, LXQt, Budgie, Deepin, COSMIC, Pantheon, tiling WMs
- **Package managers:** apt, dnf, yum, pacman, zypper, apk (auto-detected)

## Uninstall

```bash
dispatch-toggle.sh stop 2>/dev/null
rm -f ~/.local/bin/dispatch-toggle.sh
rm -f ~/.local/bin/wibluetooth-proxy.py
rm -f ~/.local/bin/wibluetooth-watchdog.sh
rm -f ~/.wibluetooth-env
rm -f ~/Desktop/wibluetooth.desktop
rm -f ~/.local/share/applications/wibluetooth.desktop
rm -f ~/.local/share/icons/wibluetooth.svg
rm -rf ~/.local/share/icons/hicolor/*/apps/wibluetooth.svg
npm uninstall -g dispatch-proxy
# Remove from bashrc/zshrc manually if desired
```
