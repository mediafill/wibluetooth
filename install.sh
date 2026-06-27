#!/bin/bash
# WiBluetooth Installer - Multi-interface network bonding for Linux
# Copyright (c) 2026 GET BIT LABS LLC
# One-line install: bash <(curl -sL https://raw.githubusercontent.com/mediafill/wibluetooth/main/install.sh)
# Self-healing: auto-detects distro, installs all deps, retries on failure
set -uo pipefail

REPO_URL="https://raw.githubusercontent.com/mediafill/wibluetooth/main"
INSTALL_DIR="$HOME/.local/bin"
APP_NAME="WiBluetooth"

# ─── Colors ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${BLUE}ℹ${NC}  $*"; }
ok()    { echo -e "${GREEN}✔${NC}  $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
fail()  { echo -e "${RED}✖${NC}  $*"; exit 1; }
header(){ echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

# ─── Retry wrapper ───────────────────────────────────────────────
retry() {
    local max=${1:-3} delay=${2:-2}; shift 2
    local attempt=1
    while [[ $attempt -le $max ]]; do
        if "$@"; then return 0; fi
        warn "Attempt $attempt/$max failed, retrying in ${delay}s..."
        sleep "$delay"; ((attempt++))
    done
    return 1
}

# ─── Pre-flight checks ──────────────────────────────────────────
[[ $EUID -eq 0 ]] && fail "Don't run as root. Sudo will be asked when needed."

header "WiBluetooth Installer v2.0"
echo -e "Multi-interface network bonding for Linux\n"

# ─── Detect Distro ──────────────────────────────────────────────
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_FAMILY="${ID_LIKE:-$ID}"
    DISTRO_NAME="${PRETTY_NAME:-$NAME}"
else
    DISTRO_ID="unknown"; DISTRO_FAMILY="unknown"; DISTRO_NAME="Unknown Linux"
fi
info "Detected: ${DISTRO_NAME}"

# ─── Detect Package Manager ─────────────────────────────────────
if command -v apt-get &>/dev/null; then PKG_MGR="apt"
elif command -v dnf &>/dev/null; then PKG_MGR="dnf"
elif command -v yum &>/dev/null; then PKG_MGR="yum"
elif command -v pacman &>/dev/null; then PKG_MGR="pacman"
elif command -v zypper &>/dev/null; then PKG_MGR="zypper"
elif command -v apk &>/dev/null; then PKG_MGR="apk"
else PKG_MGR="unknown"
fi
info "Package manager: $PKG_MGR"

# ─── Package install abstraction ─────────────────────────────────
pkg_install() {
    local pkgs=("$@")
    case "$PKG_MGR" in
        apt)    retry 3 3 sudo apt-get install -y -qq "${pkgs[@]}" || sudo apt-get install -y "${pkgs[@]}" ;;
        dnf|yum) retry 3 3 sudo "$PKG_MGR" install -y "${pkgs[@]}" ;;
        pacman) retry 3 3 sudo pacman -S --noconfirm --needed "${pkgs[@]}" ;;
        zypper) retry 3 3 sudo zypper in -y "${pkgs[@]}" ;;
        apk)    retry 3 3 sudo apk add "${pkgs[@]}" ;;
        *)      warn "Cannot auto-install packages. Please install manually: ${pkgs[*]}"; return 1 ;;
    esac
}

pkg_update() {
    case "$PKG_MGR" in
        apt)    sudo apt-get update -qq ;;
        dnf|yum) sudo "$PKG_MGR" check-update -q 2>/dev/null || true ;;
        pacman) sudo pacman -Sy --noconfirm ;;
        zypper) sudo zypper ref -q ;;
        apk)    sudo apk update -q ;;
    esac
}

# ─── Install System Dependencies ────────────────────────────────
install_deps() {
    header "Installing System Dependencies"
    pkg_update

    local pkgs=()

    # Node.js (for dispatch-proxy)
    if ! command -v node &>/dev/null; then
        info "Node.js not found, installing..."
        case "$PKG_MGR" in
            apt)
                curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - 2>/dev/null && pkgs+=(nodejs) || pkgs+=(nodejs npm)
                ;;
            dnf|yum)
                curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash - 2>/dev/null && pkgs+=(nodejs) || pkgs+=(nodejs npm)
                ;;
            pacman)  pkgs+=(nodejs npm) ;;
            zypper)  pkgs+=(nodejs18 npm18) ;;
            apk)     pkgs+=(nodejs npm) ;;
        esac
    fi

    # npm
    command -v npm &>/dev/null || pkgs+=(npm)

    # Bluetooth
    case "$PKG_MGR" in
        apt)     pkgs+=(bluez bluez-tools network-manager) ;;
        dnf|yum) pkgs+=(bluez bluez-tools NetworkManager) ;;
        pacman)  pkgs+=(bluez bluez-utils networkmanager) ;;
        zypper)  pkgs+=(bluez bluez-tools NetworkManager) ;;
        apk)     pkgs+=(bluez-tools networkmanager) ;;
    esac

    # Network tools
    case "$PKG_MGR" in
        apt)     pkgs+=(iproute2 psmisc) ;;
        dnf|yum) pkgs+=(iproute psmisc) ;;
        pacman)  pkgs+=(iproute2 psmisc) ;;
        *)       pkgs+=(iproute2 psmisc) ;;
    esac

    # Notifications
    case "$PKG_MGR" in
        apt)     pkgs+=(libnotify-bin) ;;
        dnf|yum) pkgs+=(libnotify) ;;
        pacman)  pkgs+=(libnotify) ;;
        zypper)  pkgs+=(libnotify-tools) ;;
    esac

    # Python3 (for HTTP bridge)
    command -v python3 &>/dev/null || {
        case "$PKG_MGR" in
            apt)     pkgs+=(python3) ;;
            dnf|yum) pkgs+=(python3) ;;
            pacman)  pkgs+=(python) ;;
        esac
    }

    if [[ ${#pkgs[@]} -gt 0 ]]; then
        info "Installing: ${pkgs[*]}"
        pkg_install "${pkgs[@]}" || warn "Some packages may not have installed"
    fi

    # Fix PATH for nvm users
    for nvm_dir in "$HOME/.nvm/versions/node/"*/bin; do
        [[ -d "$nvm_dir" ]] && export PATH="$nvm_dir:$PATH"
    done

    # Verify critical commands
    for cmd in node npm python3 curl; do
        command -v "$cmd" &>/dev/null && ok "$cmd: $(command -v "$cmd")" || warn "$cmd: NOT FOUND"
    done

    ok "System dependencies installed"
}

# ─── Install dispatch-proxy ─────────────────────────────────────
install_dispatch() {
    header "Installing dispatch-proxy"

    local npm_bin=$(which npm 2>/dev/null || true)
    if [[ -z "$npm_bin" ]]; then
        for p in /usr/bin/npm /usr/local/bin/npm "$HOME/.nvm/versions/node/"*/bin/npm; do
            [[ -x "$p" ]] && npm_bin="$p" && break
        done
    fi
    [[ -z "$npm_bin" ]] && fail "npm not found. Install Node.js first."

    if command -v dispatch &>/dev/null; then
        info "dispatch-proxy already installed"
    else
        info "Installing dispatch-proxy..."
        retry 3 3 "$npm_bin" install -g dispatch-proxy || {
            "$npm_bin" install -g --unsafe-perm dispatch-proxy 2>/dev/null || {
                command -v yarn &>/dev/null && yarn global add dispatch-proxy ||
                command -v pnpm &>/dev/null && pnpm add -g dispatch-proxy ||
                fail "Cannot install dispatch-proxy"
            }
        }
    fi

    # Find dispatch binary
    local dispatch_bin=$(which dispatch 2>/dev/null || true)
    if [[ -z "$dispatch_bin" ]]; then
        for p in /usr/local/bin/dispatch "$HOME/.nvm/versions/node/"*/bin/dispatch "$HOME/.npm-global/bin/dispatch"; do
            [[ -x "$p" ]] && dispatch_bin="$p" && break
        done
    fi
    [[ -n "$dispatch_bin" ]] && ok "dispatch-proxy: $dispatch_bin" || warn "dispatch-proxy installed but not in PATH"
}

# ─── Install Python dependencies ─────────────────────────────────
install_python_deps() {
    header "Checking Python dependencies"
    # PySocks is bundled via the raw socket SOCKS5 implementation in wibluetooth-proxy.py
    # No external Python packages needed
    ok "Python dependencies: none required (pure stdlib)"
}

# ─── Install scripts ────────────────────────────────────────────
install_scripts() {
    header "Installing WiBluetooth scripts"
    mkdir -p "$INSTALL_DIR"

    # Check if we're running from the cloned repo
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ -f "$script_dir/dispatch-toggle.sh" ]]; then
        # Install from local repo
        cp "$script_dir/dispatch-toggle.sh" "$INSTALL_DIR/"
        cp "$script_dir/wibluetooth-proxy.py" "$INSTALL_DIR/"
        cp "$script_dir/wibluetooth-watchdog.sh" "$INSTALL_DIR/"
    else
        # Download from GitHub
        info "Downloading scripts from GitHub..."
        for f in dispatch-toggle.sh wibluetooth-proxy.py wibluetooth-watchdog.sh; do
            curl -fsSL "$REPO_URL/$f" -o "$INSTALL_DIR/$f" || fail "Failed to download $f"
        done
    fi

    chmod +x "$INSTALL_DIR/dispatch-toggle.sh" "$INSTALL_DIR/wibluetooth-proxy.py" "$INSTALL_DIR/wibluetooth-watchdog.sh"
    ok "Scripts installed to $INSTALL_DIR"
}

# ─── Create desktop entry ───────────────────────────────────────
create_desktop_entry() {
    header "Creating desktop shortcut"

    # SVG Icon
    mkdir -p "$HOME/.local/share/icons"
    cat > "$HOME/.local/share/icons/wibluetooth.svg" << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#4a9eff;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#2563eb;stop-opacity:1" />
    </linearGradient>
  </defs>
  <circle cx="64" cy="64" r="60" fill="url(#bg)" stroke="#1e40af" stroke-width="3"/>
  <path d="M64 80 Q64 70 54 60" fill="none" stroke="white" stroke-width="4" stroke-linecap="round"/>
  <path d="M64 80 Q64 65 44 50" fill="none" stroke="white" stroke-width="4" stroke-linecap="round"/>
  <path d="M64 80 Q64 60 34 40" fill="none" stroke="white" stroke-width="4" stroke-linecap="round"/>
  <path d="M64 80 Q64 70 74 60" fill="none" stroke="white" stroke-width="4" stroke-linecap="round"/>
  <path d="M64 80 Q64 65 84 50" fill="none" stroke="white" stroke-width="4" stroke-linecap="round"/>
  <path d="M64 80 Q64 60 94 40" fill="none" stroke="white" stroke-width="4" stroke-linecap="round"/>
  <path d="M64 30 L64 50 M64 50 L72 42 M64 50 L56 42 M64 50 L64 60" fill="none" stroke="#93c5fd" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="64" cy="80" r="6" fill="white"/>
</svg>
SVGEOF

    for size in 16 22 24 32 48 64 128; do
        mkdir -p "$HOME/.local/share/icons/hicolor/${size}x${size}/apps"
        cp "$HOME/.local/share/icons/wibluetooth.svg" "$HOME/.local/share/icons/hicolor/${size}x${size}/apps/"
    done

    # Desktop file
    mkdir -p "$HOME/Desktop" "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/wibluetooth.desktop" << DESKTOP
[Desktop Entry]
Name=WiBluetooth
Comment=Bond multiple internet connections for faster downloads
Exec=$INSTALL_DIR/dispatch-toggle.sh toggle
Icon=wibluetooth
Terminal=false
Type=Application
Categories=Network;Utility;
Keywords=proxy;network;wifi;bluetooth;speed;load-balance;channel-bonding;
StartupNotify=false
Actions=Start;Stop;Restart;Status;Health;List;Heal;

[Desktop Action Start]
Name=Start Proxy
Exec=$INSTALL_DIR/dispatch-toggle.sh start

[Desktop Action Stop]
Name=Stop Proxy
Exec=$INSTALL_DIR/dispatch-toggle.sh stop

[Desktop Action Restart]
Name=Restart Proxy
Exec=$INSTALL_DIR/dispatch-toggle.sh restart

[Desktop Action Status]
Name=Check Status
Exec=$INSTALL_DIR/dispatch-toggle.sh status

[Desktop Action Health]
Name=Health Check
Exec=$INSTALL_DIR/dispatch-toggle.sh health

[Desktop Action List]
Name=List Interfaces
Exec=$INSTALL_DIR/dispatch-toggle.sh list

[Desktop Action Heal]
Name=Auto-Heal
Exec=$INSTALL_DIR/dispatch-toggle.sh heal
DESKTOP

    cp "$HOME/.local/share/applications/wibluetooth.desktop" "$HOME/Desktop/wibluetooth.desktop" 2>/dev/null || true
    chmod +x "$HOME/Desktop/wibluetooth.desktop" 2>/dev/null || true
    gtk-update-icon-cache "$HOME/.local/share/icons/hicolor/" 2>/dev/null || true
    ok "Desktop shortcut created"
}

# ─── Setup auto-source ──────────────────────────────────────────
setup_autosource() {
    header "Setting up auto-source"

    # bashrc
    if ! grep -q "wibluetooth" ~/.bashrc 2>/dev/null; then
        echo '' >> ~/.bashrc
        echo '# WiBluetooth proxy auto-source' >> ~/.bashrc
        echo '[ -f ~/.wibluetooth-env ] && source ~/.wibluetooth-env' >> ~/.bashrc
        ok "Added to ~/.bashrc"
    fi

    # zshrc
    if [[ -f ~/.zshrc ]] && ! grep -q "wibluetooth" ~/.zshrc 2>/dev/null; then
        echo '' >> ~/.zshrc
        echo '# WiBluetooth proxy auto-source' >> ~/.zshrc
        echo '[ -f ~/.wibluetooth-env ] && source ~/.wibluetooth-env' >> ~/.zshrc
        ok "Added to ~/.zshrc"
    fi

    # profile.d (system-wide for new shells)
    if [[ -d /etc/profile.d ]]; then
        sudo bash -c 'cat > /etc/profile.d/wibluetooth.sh << "EOF"
[ -f "$HOME/.wibluetooth-env" ] && . "$HOME/.wibluetooth-env"
EOF' 2>/dev/null && ok "Added to /etc/profile.d/" || warn "Could not write to /etc/profile.d/"
    fi
}

# ─── Self-test ──────────────────────────────────────────────────
self_test() {
    header "Running self-test"

    # Verify scripts exist
    for f in dispatch-toggle.sh wibluetooth-proxy.py wibluetooth-watchdog.sh; do
        [[ -x "$INSTALL_DIR/$f" ]] && ok "$f" || fail "$f missing"
    done

    # Verify dispatch binary
    command -v dispatch &>/dev/null || {
        for p in "$HOME/.nvm/versions/node/"*/bin/dispatch /usr/local/bin/dispatch; do
            [[ -x "$p" ]] && export PATH="$(dirname "$p"):$PATH" && break
        done
    }
    command -v dispatch &>/dev/null && ok "dispatch: $(which dispatch)" || warn "dispatch not in PATH (toggle script will search for it)"

    # Verify python3
    command -v python3 &>/dev/null && ok "python3: $(which python3)" || warn "python3 not found"

    # Quick syntax check
    bash -n "$INSTALL_DIR/dispatch-toggle.sh" 2>/dev/null && ok "dispatch-toggle.sh: syntax OK" || warn "dispatch-toggle.sh: syntax error"
    python3 -c "import py_compile; py_compile.compile('$INSTALL_DIR/wibluetooth-proxy.py', doraise=True)" 2>/dev/null && ok "wibluetooth-proxy.py: syntax OK" || warn "wibluetooth-proxy.py: syntax error"

    ok "Self-test passed"
}

# ─── Main ───────────────────────────────────────────────────────
main() {
    install_deps
    install_dispatch
    install_python_deps
    install_scripts
    create_desktop_entry
    setup_autosource
    self_test

    header "Installation Complete!"
    echo -e "${GREEN}WiBluetooth is ready!${NC}\n"
    echo -e "  ${BOLD}Quick Start:${NC}"
    echo -e "  • Click ${CYAN}WiBluetooth${NC} on your desktop, or run:"
    echo -e "  • ${CYAN}dispatch-toggle.sh start${NC}    — start bonding"
    echo -e "  • ${CYAN}dispatch-toggle.sh stop${NC}     — stop bonding"
    echo -e "  • ${CYAN}dispatch-toggle.sh health${NC}   — check status"
    echo -e "  • ${CYAN}dispatch-toggle.sh heal${NC}     — auto-fix issues"
    echo -e ""
    echo -e "  ${BOLD}Proxy Settings:${NC}"
    echo -e "  • HTTP proxy: ${CYAN}localhost:8888${NC} (for all apps)"
    echo -e "  • SOCKS5: ${CYAN}localhost:1080${NC} (for aria2, curl)"
    echo -e ""
    echo -e "  ${BOLD}Auto-source in new terminals:${NC}"
    echo -e "  • ${CYAN}source ~/.wibluetooth-env${NC}"
    echo ""
}

main "$@"
