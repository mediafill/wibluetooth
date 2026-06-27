# WiBluetooth

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-green.svg)](https://github.com/mediafill/wibluetooth)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)
[![Owner: GET BIT LABS LLC](https://img.shields.io/badge/Owner-GET%20BIT%20LABS%20LLC-purple.svg)](https://github.com/mediafill)

**Multi-interface network bonding for Linux. Combine WiFi, Ethernet, and Bluetooth for aggregated bandwidth and faster downloads.**

A free, open-source Linux network load balancer that bonds multiple internet connections (WiFi, Ethernet, Bluetooth PAN) into a single proxy. Similar to commercial channel bonding solutions, but runs entirely on your machine with no cloud dependency, no subscriptions, and no data caps.

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

## What It Does

WiBluetooth automatically detects and bonds all available network interfaces — WiFi, Ethernet, Bluetooth PAN, and more — into a single load-balanced HTTP proxy. Multi-threaded downloaders like aria2, wget2, and browser download managers can then use all connections simultaneously for aggregated throughput.

- **Auto-detects** all active network interfaces (multiple WiFi, Ethernet, Bluetooth)
- **Auto-heals** missing dependencies and non-standard setups
- **Desktop integration** with toggle icon and notifications
- **No root required** for daily use after installation

## Usage

### Desktop Shortcut
- **Click** the WiBluetooth icon to toggle proxy on/off
- **Right-click** for Start / Stop / Status options
- Shows desktop notifications with connection status

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

Set SOCKS5 proxy to `localhost:1080`:

```bash
# Environment variable
export all_proxy=socks5://localhost:1080

# aria2 (multi-threaded downloader) - recommended
aria2c -x16 --all-proxy=socks5://localhost:1080 https://example.com/file.zip

# wget
wget -e use_proxy=yes -e http_proxy=socks5://localhost:1080 https://example.com/file.zip

# curl
curl -x socks5://localhost:1080 https://example.com/file.zip
```

For apps that don't support SOCKS5, HTTP proxy is also available on port 8080.

## Requirements

- Linux with systemd (most modern distros)
- At least one active network connection
- `curl` and `bash`

## Supported Platforms

### Distros
| Distro Family | Status |
|---------------|--------|
| Ubuntu / Debian | Full support |
| Fedora / RHEL / CentOS | Full support |
| Arch / Manjaro | Full support |
| openSUSE | Full support |
| Alpine | Experimental |
| Any Linux with apt/dnf/pacman | Auto-detected |

### Desktop Environments
| Desktop | Status |
|---------|--------|
| GNOME (Ubuntu, Fedora) | Full support |
| KDE Plasma (Kubuntu, Fedora KDE) | Full support |
| XFCE (Xubuntu) | Full support |
| Cinnamon (Linux Mint) | Full support |
| MATE (Ubuntu MATE) | Full support |
| LXQt (Lubuntu) | Full support |
| Budgie (Solus, Ubuntu Budgie) | Full support |
| Deepin | Full support |
| COSMIC (Pop!_OS) | Full support |
| Pantheon (elementary OS) | Full support |
| Tiling WMs (i3, Sway, Hyprland) | Partial support |

## How It Works

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│  Your App   │────▶│  dispatch-proxy  │────▶│   Internet  │
│  (browser,  │     │  (localhost:1080)│     │             │
│   aria2)    │     └────────┬─────────┘     └─────────────┘
└─────────────┘              │
              ┌──────────────┼──────────────┐
              │              │              │
        ┌─────▼─────┐ ┌─────▼─────┐ ┌──────▼──────┐
        │  WiFi #1  │ │ Ethernet  │ │ Bluetooth   │
        │  (wlan0)  │ │  (eth0)   │ │  (bnep0)    │
        └───────────┘ └───────────┘ └─────────────┘
```

WiBluetooth uses [dispatch-proxy](https://github.com/alexkirsz/dispatch-proxy) under the hood to distribute outgoing connections across all available interfaces. Multi-threaded downloaders can then aggregate bandwidth from all bonded connections.

## Why WiBluetooth?

WiBluetooth provides multi-interface bonding functionality similar to commercial solutions like [Speedify](https://www.speedify.com), but is:

- **Free and open source** — no subscriptions, no data caps, no paywalls
- **Linux-native** — runs on any distro without proprietary drivers or VPN tunnels
- **Lightweight** — toggle on/off as needed, no persistent background services
- **Privacy-friendly** — all traffic stays on your machine, no cloud proxy servers
- **Auto-healing** — detects and fixes common issues automatically

Speedify is a trademark of Connectify, Inc. WiBluetooth is not affiliated with or endorsed by Connectify, Inc.

## Auto-Healing

WiBluetooth includes built-in auto-recovery for:

- **Missing dependencies** — auto-installs Node.js, BlueZ, network tools
- **Non-standard setups** — adapts to custom PATH configurations
- **Stale processes** — cleans up dead proxy instances automatically
- **Busy ports** — falls back to alternative ports if needed
- **Package manager issues** — retries with different flags, tries alternatives

Run `dispatch-toggle.sh heal` to manually trigger auto-recovery.

## Related Projects

- [dispatch-proxy](https://github.com/alexkirsz/dispatch-proxy) — The underlying proxy engine
- [aria2](https://aria2.github.io/) — Multi-protocol download utility
- [OpenMPTCProuter](https://www.openmptcprouter.com/) — Router-level multipath bonding
- [Speedify](https://www.speedify.com) — Commercial channel bonding (proprietary)

## Contributing

Contributions welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## LLM Installation

Point your AI assistant to [SKILL.md](SKILL.md) for structured installation instructions.

## License

MIT License. Copyright (c) 2026 GET BIT LABS LLC. See [LICENSE](LICENSE) for details.

---

## Disclaimer

**THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.**

WiBluetooth is provided for educational and personal use. The authors and contributors are not responsible for any damage, data loss, or legal issues that may arise from using this software. Use at your own risk.

- Network bonding may not work on all hardware or network configurations
- Bluetooth tethering requires a compatible phone with tethering enabled
- Results depend on the speed and reliability of your individual connections
- This software is not a VPN and does not provide encryption or anonymity
- Always comply with your ISP's terms of service regarding connection sharing

---

Copyright (c) 2026 GET BIT LABS LLC. All rights reserved.
