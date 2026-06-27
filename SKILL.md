# SKILL.md - WiBluetooth Installation

Copyright (c) 2026 GET BIT LABS LLC

## What is WiBluetooth?

WiBluetooth is a multi-interface network bonding tool for Linux that combines WiFi, Ethernet, and Bluetooth connections into a single load-balanced proxy for faster downloads.

## When to Use This Skill

Use this skill when the user wants to:
- Install WiBluetooth on their Linux system
- Combine multiple internet connections for faster downloads
- Set up channel bonding or network load balancing on Linux
- Bond WiFi and Bluetooth for aggregated bandwidth
- Install a free alternative to Speedify on Linux

## Installation

### One-Line Install

```bash
bash <(curl -sL https://raw.githubusercontent.com/mediafill/wibluetooth/main/install.sh)
```

### Manual Install

```bash
# Clone the repository
git clone https://github.com/mediafill/wibluetooth.git
cd wibluetooth

# Run the installer
chmod +x install.sh
./install.sh
```

### What the Installer Does

1. **Detects your Linux distro** (Debian, Fedora, Arch, openSUSE, Alpine, and derivatives)
2. **Detects your desktop environment** (GNOME, KDE, XFCE, Cinnamon, MATE, LXQt, Budgie, Deepin, COSMIC, Pantheon)
3. **Installs dependencies** (Node.js, BlueZ, network-manager, notification tools)
4. **Installs dispatch-proxy** via npm
5. **Creates a desktop shortcut** with toggle icon
6. **Sets up auto-healing** for missing dependencies

## Post-Installation Usage

### Desktop Shortcut
- Click the WiBluetooth icon to toggle proxy on/off
- Right-click for Start / Stop / Status / List / Heal options

### Command Line

```bash
# Toggle proxy (auto-detects all interfaces)
dispatch-toggle.sh toggle

# List all detected interfaces
dispatch-toggle.sh list

# Check proxy health
dispatch-toggle.sh health

# Auto-heal (fix stale processes, verify deps)
dispatch-toggle.sh heal

# Explicit start/stop/status
dispatch-toggle.sh start
dispatch-toggle.sh stop
dispatch-toggle.sh status
```

### Use with Download Managers

```bash
# Set proxy environment
export http_proxy=http://localhost:8080
export https_proxy=http://localhost:8080

# aria2 (recommended for multi-threaded downloads)
aria2c -x16 --all-proxy=http://localhost:8080 <url>

# wget
wget -e use_proxy=yes -e http_proxy=localhost:8080 <url>

# curl
curl -x http://localhost:8080 <url>
```

## Supported Platforms

### Distros
- Ubuntu / Debian (apt)
- Fedora / RHEL / CentOS (dnf/yum)
- Arch / Manjaro (pacman)
- openSUSE (zypper)
- Alpine (apk)
- Any Linux with a supported package manager

### Desktop Environments
- GNOME (Ubuntu, Fedora)
- KDE Plasma (Kubuntu, Fedora KDE)
- XFCE (Xubuntu)
- Cinnamon (Linux Mint)
- MATE (Ubuntu MATE)
- LXQt (Lubuntu)
- Budgie (Solus, Ubuntu Budgie)
- Deepin
- COSMIC (Pop!_OS)
- Pantheon (elementary OS)
- Tiling WMs (i3, Sway, Hyprland)

## Troubleshooting

### Proxy Won't Start
```bash
dispatch-toggle.sh heal
dispatch-toggle.sh start
```

### Missing Dependencies
```bash
dispatch-toggle.sh heal
# Or reinstall
bash <(curl -sL https://raw.githubusercontent.com/mediafill/wibluetooth/main/install.sh)
```

### No Bluetooth Interface
1. Ensure Bluetooth is enabled on your phone
2. Enable Bluetooth tethering on the phone
3. Pair the phone with your Linux machine
4. Run `dispatch-toggle.sh start` to auto-activate

### Check What's Running
```bash
dispatch-toggle.sh list      # Show all interfaces
dispatch-toggle.sh health    # Check proxy status
cat /tmp/wibluetooth.log     # View logs
```

## Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│  Your App   │────▶│  dispatch-proxy  │────▶│   Internet  │
│  (browser,  │     │  (localhost:8080) │     │             │
│   aria2)    │     └────────┬─────────┘     └─────────────┘
└─────────────┘              │
              ┌──────────────┼──────────────┐
              │              │              │
        ┌─────▼─────┐ ┌─────▼─────┐ ┌──────▼──────┐
        │  WiFi #1  │ │ Ethernet  │ │ Bluetooth   │
        │  (wlan0)  │ │  (eth0)   │ │  (bnep0)    │
        └───────────┘ └───────────┘ └─────────────┘
```

## Key Files

- `~/.local/bin/dispatch-toggle.sh` - Main toggle script
- `~/.local/share/applications/wibluetooth.desktop` - Desktop entry
- `~/.local/share/icons/wibluetooth.svg` - App icon
- `/tmp/wibluetooth.pid` - Running process ID
- `/tmp/wibluetooth.log` - Proxy logs

## Uninstall

```bash
rm -f ~/.local/bin/dispatch-toggle.sh
rm -f ~/Desktop/wibluetooth.desktop
rm -f ~/.local/share/applications/wibluetooth.desktop
rm -f ~/.local/share/icons/wibluetooth.svg
rm -rf ~/.local/share/icons/hicolor/*/apps/wibluetooth.svg
npm uninstall -g dispatch-proxy
```
