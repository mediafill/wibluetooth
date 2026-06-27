#!/bin/bash
# WiBluetooth - Multi-interface network bonding for Linux
# Copyright (c) 2026 GET BIT LABS LLC
# One-line installer: bash <(curl -sL https://raw.githubusercontent.com/mediafill/wibluetooth/main/install.sh)
# Combines WiFi, Ethernet, and Bluetooth for aggregated bandwidth
# Compatible with: GNOME, KDE Plasma, XFCE, Cinnamon, MATE, LXQt, Budgie, Deepin, COSMIC, Pantheon, Unity
set -uo pipefail

# ─── Colors & Icons ─────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${BLUE}ℹ${NC}  $*"; }
ok()    { echo -e "${GREEN}✔${NC}  $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
fail()  { echo -e "${RED}✖${NC}  $*"; exit 1; }
header(){ echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

# ─── Auto-Healing: Retry wrapper ────────────────────────────────
retry() {
    local max_attempts=${1:-3}
    local delay=${2:-2}
    shift 2
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if "$@"; then return 0; fi
        warn "Attempt $attempt/$max_attempts failed, retrying in ${delay}s..."
        sleep "$delay"
        ((attempt++))
    done
    return 1
}

# ─── Detect Desktop Environment ─────────────────────────────────
detect_desktop() {
    DESKTOP="${XDG_CURRENT_DESKTOP:-unknown}"
    DESKTOP_SESSION="${DESKTOP_SESSION:-unknown}"

    # Normalize desktop name
    case "${DESKTOP,,}" in
        *gnome*|*unity*|*cinnamon*|*mate*|*budgie*|*pantheon*|*pop*|*cosmic*)
            NOTIFY_TOOL="notify-send"
            TRAY_SUPPORT=false
            ;;
        *kde*|*plasma*)
            NOTIFY_TOOL="notify-send"
            TRAY_SUPPORT=true
            ;;
        *xfce*|*xubuntu*)
            NOTIFY_TOOL="notify-send"
            TRAY_SUPPORT=true
            ;;
        *lxqt*|*lubuntu*)
            NOTIFY_TOOL="notify-send"
            TRAY_SUPPORT=true
            ;;
        *deepin*)
            NOTIFY_TOOL="notify-send"
            TRAY_SUPPORT=true
            ;;
        *i3*|*sway*|*hyprland*|*wayfire*|*river*)
            NOTIFY_TOOL="notify-send"
            TRAY_SUPPORT=false
            ;;
        *)
            # Auto-detect: try notify-send, fall back to terminal
            if command -v notify-send &>/dev/null; then
                NOTIFY_TOOL="notify-send"
            else
                NOTIFY_TOOL="echo"
            fi
            TRAY_SUPPORT=false
            ;;
    esac

    info "Desktop: ${DESKTOP:-unknown} (notifications: ${NOTIFY_TOOL}, tray: ${TRAY_SUPPORT})"
}

# ─── Pre-flight ─────────────────────────────────────────────────
[[ $EUID -eq 0 ]] && fail "Don't run as root. The script will ask for sudo when needed."

header "WiBluetooth Installer"
echo -e "Multi-interface network bonding for Linux\n"

# ─── Detect Distro ──────────────────────────────────────────────
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_FAMILY="${ID_LIKE:-$ID}"
        DISTRO_NAME="${PRETTY_NAME:-$NAME}"
    else
        # Fallback: try lsb_release
        if command -v lsb_release &>/dev/null; then
            DISTRO_ID=$(lsb_release -si 2>/dev/null || echo "unknown")
            DISTRO_FAMILY="$DISTRO_ID"
            DISTRO_NAME=$(lsb_release -sd 2>/dev/null || echo "Unknown Linux")
        else
            warn "Cannot detect distro. /etc/os-release not found. Assuming generic Linux."
            DISTRO_ID="unknown"
            DISTRO_FAMILY="unknown"
            DISTRO_NAME="Unknown Linux"
        fi
    fi
    info "Detected: ${DISTRO_NAME}"
}

# ─── Package Manager Abstraction (auto-detect) ──────────────────
detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then PKG_MGR="apt"
    elif command -v dnf &>/dev/null; then PKG_MGR="dnf"
    elif command -v yum &>/dev/null; then PKG_MGR="yum"
    elif command -v pacman &>/dev/null; then PKG_MGR="pacman"
    elif command -v zypper &>/dev/null; then PKG_MGR="zypper"
    elif command -v apk &>/dev/null; then PKG_MGR="apk"
    elif command -v brew &>/dev/null; then PKG_MGR="brew"
    else PKG_MGR="unknown"
    fi
    info "Package manager: $PKG_MGR"
}

pkg_update() {
    case "$PKG_MGR" in
        apt)    sudo apt-get update -qq ;;
        dnf)    sudo dnf check-update -q 2>/dev/null || true ;;
        yum)    sudo yum check-update -q 2>/dev/null || true ;;
        pacman) sudo pacman -Sy --noconfirm ;;
        zypper) sudo zypper ref -q ;;
        apk)    sudo apk update -q ;;
        brew)   brew update ;;
        *)      warn "Unknown package manager, attempting manual install..." ;;
    esac
}

pkg_install() {
    local pkgs=("$@")
    local install_func

    case "$PKG_MGR" in
        apt)    install_func="sudo apt-get install -y -qq" ;;
        dnf)    install_func="sudo dnf install -y -q" ;;
        yum)    install_func="sudo yum install -y -q" ;;
        pacman) install_func="sudo pacman -S --noconfirm --needed" ;;
        zypper) install_func="sudo zypper in -y -q" ;;
        apk)    install_func="sudo apk add -q" ;;
        brew)   install_func="brew install" ;;
        *)      fail "Cannot install packages: no supported package manager found." ;;
    esac

    retry 3 3 $install_func "${pkgs[@]}" || {
        warn "Standard install failed, trying alternative method..."
        case "$PKG_MGR" in
            apt)
                # Try with --fix-broken
                sudo apt-get install -y -qq --fix-broken "${pkgs[@]}" 2>/dev/null ||
                sudo apt-get install -y "${pkgs[@]}" 2>/dev/null
                ;;
            dnf|yum)
                # Try with --allowerasing
                sudo "$PKG_MGR" install -y --allowerasing "${pkgs[@]}" 2>/dev/null
                ;;
            *)
                warn "Could not auto-recover package install for: ${pkgs[*]}"
                return 1
                ;;
        esac
    }
}

# ─── Check & Install Dependencies (with auto-healing) ───────────
install_deps() {
    header "Installing Dependencies"

    detect_pkg_manager

    # Build dependency list
    local pkgs=()

    # Node.js / npm (needed for dispatch-proxy)
    if ! command -v node &>/dev/null; then
        info "Node.js not found, installing..."
        case "$PKG_MGR" in
            apt)
                # Try NodeSource first, fallback to distro package
                if curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - 2>/dev/null; then
                    pkgs+=(nodejs)
                else
                    pkgs+=(nodejs npm)
                fi
                ;;
            dnf|yum)
                if curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash - 2>/dev/null; then
                    pkgs+=(nodejs)
                else
                    pkgs+=(nodejs npm)
                fi
                ;;
            pacman)  pkgs+=(nodejs npm) ;;
            zypper)  pkgs+=(nodejs18 npm18) ;;
            apk)     pkgs+=(nodejs npm) ;;
            brew)    pkgs+=(node) ;;
            *)       warn "Cannot auto-install Node.js. Please install manually." ;;
        esac
    fi

    # npm (verify it's available)
    if ! command -v npm &>/dev/null; then
        case "$PKG_MGR" in
            apt)    pkgs+=(npm) ;;
            dnf|yum) pkgs+=(npm) ;;
            *)      # Try installing npm standalone
                    pkgs+=(npm) ;;
        esac
    fi

    # Bluetooth packages
    case "$PKG_MGR" in
        apt)     pkgs+=(bluez bluez-tools network-manager) ;;
        dnf|yum) pkgs+=(bluez bluez-tools NetworkManager) ;;
        pacman)  pkgs+=(bluez bluez-utils networkmanager) ;;
        zypper)  pkgs+=(bluez bluez-tools NetworkManager) ;;
        apk)     pkgs+=(bluez-tools networkmanager) ;;
        brew)    # Bluetooth is built-in on macOS, skip
                ;;
    esac

    # Network tools
    case "$PKG_MGR" in
        apt)     pkgs+=(iproute2 psmisc) ;;
        dnf|yum) pkgs+=(iproute psmisc) ;;
        pacman)  pkgs+=(iproute2 psmisc) ;;
        zypper)  pkgs+=(iproute2 psmisc) ;;
        apk)     pkgs+=(iproute2 psmisc) ;;
        brew)    pkgs+=(psmisc) ;;
    esac

    # Notification tool
    case "$PKG_MGR" in
        apt)     pkgs+=(libnotify-bin) ;;
        dnf|yum) pkgs+=(libnotify) ;;
        pacman)  pkgs+=(libnotify) ;;
        zypper)  pkgs+=(libnotify-tools) ;;
        apk)     pkgs+=(libnotify) ;;
        brew)    # Notifications built-in on macOS
                ;;
    esac

    # Install what we collected
    if [[ ${#pkgs[@]} -gt 0 ]]; then
        info "Installing packages: ${pkgs[*]}"
        pkg_install "${pkgs[@]}" || warn "Some packages may not have installed correctly"
    fi

    # Verify critical commands (with auto-heal attempts)
    local missing=()
    for cmd in node npm; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing commands: ${missing[*]}"
        info "Attempting auto-heal..."

        # Try to fix PATH issues
        for nvm_dir in "$HOME/.nvm/versions/node/"*/bin; do
            if [[ -d "$nvm_dir" ]]; then
                export PATH="$nvm_dir:$PATH"
                info "Added $nvm_dir to PATH"
            fi
        done

        # Re-check after PATH fix
        for cmd in "${missing[@]}"; do
            if ! command -v "$cmd" &>/dev/null; then
                warn "Still missing: $cmd - will attempt to use alternatives"
            fi
        done
    fi

    # Bluetooth and network tools are nice-to-have, warn but don't fail
    for cmd in bluetoothctl nmcli ip; do
        if ! command -v "$cmd" &>/dev/null; then
            warn "Optional command '$cmd' not found. Some features may be limited."
        fi
    done

    ok "Dependencies installed"
}

# ─── Install dispatch-proxy (with auto-recovery) ────────────────
install_dispatch() {
    header "Installing dispatch-proxy"

    # Find npm location
    local npm_bin=$(which npm 2>/dev/null || true)
    if [[ -z "$npm_bin" ]]; then
        # Try to find npm in common locations
        for path in /usr/bin/npm /usr/local/bin/npm "$HOME/.nvm/versions/node/"*/bin/npm; do
            if [[ -x "$path" ]]; then
                npm_bin="$path"
                break
            fi
        done
    fi

    if [[ -z "$npm_bin" ]]; then
        warn "npm not found. Attempting to install via nvm..."
        if ! command -v nvm &>/dev/null; then
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash 2>/dev/null
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        fi
        nvm install --lts 2>/dev/null || fail "Cannot install Node.js/npm"
        npm_bin=$(which npm)
    fi

    if command -v dispatch &>/dev/null; then
        info "dispatch-proxy already installed, updating..."
        retry 2 2 "$npm_bin" update -g dispatch-proxy 2>/dev/null || {
            warn "Update failed, reinstalling..."
            "$npm_bin" uninstall -g dispatch-proxy 2>/dev/null || true
            retry 2 2 "$npm_bin" install -g dispatch-proxy
        }
    else
        info "Installing dispatch-proxy via npm..."
        retry 3 3 "$npm_bin" install -g dispatch-proxy || {
            # Fallback: try with different npm flags
            warn "Standard install failed, trying with --unsafe-perm..."
            "$npm_bin" install -g --unsafe-perm dispatch-proxy 2>/dev/null || {
                # Last resort: try yarn or pnpm
                if command -v yarn &>/dev/null; then
                    yarn global add dispatch-proxy
                elif command -v pnpm &>/dev/null; then
                    pnpm add -g dispatch-proxy
                else
                    fail "Cannot install dispatch-proxy. Please install Node.js and npm manually."
                fi
            }
        }
    fi

    # Verify installation
    local dispatch_bin=$(which dispatch 2>/dev/null || true)
    if [[ -z "$dispatch_bin" ]]; then
        # Search common locations
        for path in /usr/local/bin/dispatch "$HOME/.nvm/versions/node/"*/bin/dispatch "$HOME/.npm-global/bin/dispatch"; do
            if [[ -x "$path" ]]; then
                dispatch_bin="$path"
                break
            fi
        done
    fi

    if [[ -n "$dispatch_bin" && -x "$dispatch_bin" ]]; then
        ok "dispatch-proxy installed: $dispatch_bin"
    else
        warn "dispatch-proxy installed but not found in PATH. The toggle script will search for it."
    fi
}

# ─── Create Toggle Script ───────────────────────────────────────
create_toggle_script() {
    header "Creating toggle script"

    INSTALL_DIR="$HOME/.local/bin"
    SCRIPT_PATH="$INSTALL_DIR/dispatch-toggle.sh"
    mkdir -p "$INSTALL_DIR"

    cat > "$SCRIPT_PATH" << 'TOGGLE_SCRIPT'
#!/bin/bash
# WiBluetooth Toggle - Multi-interface proxy load balancer
# Combines WiFi, Ethernet, and Bluetooth connections
PROXY_PID_FILE="/tmp/wibluetooth.pid"
APP_NAME="WiBluetooth"
LOG_FILE="/tmp/wibluetooth.log"
SOCKS_PORT=1080
HTTP_PORT=8080

get_ip() { ip -4 addr show "$1" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1; }
is_running() { [ -f "$PROXY_PID_FILE" ] && kill -0 "$(cat "$PROXY_PID_FILE")" 2>/dev/null; }

# Detect ALL active interfaces with IPs
detect_interfaces() {
    local ifaces=()
    local lo_ifaces=()

    # Skip these virtual/container interfaces
    local skip_pattern="^(lo|docker|br-|veth|virbr|vboxnet|tun|tap|wg|tailscale|bond|dummy)"

    while IFS=: read -r num iface _; do
        iface=$(echo "$iface" | xargs)  # trim whitespace
        [[ -z "$iface" ]] && continue
        [[ "$iface" =~ $skip_pattern ]] && continue

        # Check if interface has an IPv4 address and is UP
        local state=$(cat /sys/class/net/"$iface"/operstate 2>/dev/null || echo "unknown")
        local ip=$(get_ip "$iface")

        # For Bluetooth interfaces, operstate may be "unknown" - just check for IP
        local is_bt=false
        case "$iface" in
            bnep*|enx*) is_bt=true ;;
        esac

        if [[ -n "$ip" && ("$state" == "up" || "$is_bt" == "true") ]]; then
            # Classify the interface type
            local iftype="unknown"
            local type_raw=$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | grep "^${iface}:" | cut -d: -f2)
            case "$type_raw" in
                wifi)       iftype="wifi" ;;
                ethernet)   iftype="ethernet" ;;
                bluetooth)  iftype="bluetooth" ;;
                bt)         iftype="bluetooth" ;;
                tun|tunl*)  iftype="vpn" ;;
            esac

            # Also check by interface name patterns
            if [[ "$iftype" == "unknown" ]]; then
                case "$iface" in
                    wl*)       iftype="wifi" ;;
                    bnep*|enx*) iftype="bluetooth" ;;
                    eth*|en*)  iftype="ethernet" ;;
                    tun*|tap*) iftype="vpn" ;;
                esac
            fi

            # Skip VPN/tunnel interfaces
            [[ "$iftype" == "vpn" ]] && continue

            lo_ifaces+=("${iface}|${ip}|${iftype}")
        fi
    done < <(ip -o link show | awk -F': ' '{print NR": "$2}')

    printf '%s\n' "${lo_ifaces[@]}"
}

start_proxy() {
    # Detect all available interfaces
    local raw_ifaces
    raw_ifaces=$(detect_interfaces)

    if [[ -z "$raw_ifaces" ]]; then
        notify-send -u critical -i network-offline "$APP_NAME" "No active network interfaces found!"
        exit 1
    fi

    # Try to activate Bluetooth if not already connected
    if ! echo "$raw_ifaces" | grep -q "bluetooth"; then
        # Check if there's a Bluetooth connection in NetworkManager
        local BT_CONN=$(nmcli -t -f NAME,UUID,TYPE connection show 2>/dev/null | grep ':bluetooth:' | head -1)
        if [[ -n "$BT_CONN" ]]; then
            local BT_UUID=$(echo "$BT_CONN" | cut -d: -f2)
            local BT_NAME=$(echo "$BT_CONN" | cut -d: -f1)
            info "Activating Bluetooth: $BT_NAME"
            nmcli connection up "$BT_UUID" &>/dev/null
            sleep 5
            # Re-detect after BT activation
            raw_ifaces=$(detect_interfaces)
        fi
    fi

    # Build address list and info display
    local ADDRS=""
    local IFACE_INFO=""
    local IFACE_COUNT=0

    while IFS='|' read -r iface ip iftype; do
        [[ -z "$iface" ]] && continue
        ADDRS="$ADDRS $ip"
        local icon=""
        case "$iftype" in
            wifi)       icon="📡" ;;
            ethernet)   icon="🔌" ;;
            bluetooth)  icon="📶"; has_bt=true ;;
            *)          icon="🔗" ;;
        esac
        IFACE_INFO="$IFACE_INFO\n${icon} ${iftype^} ($iface): $ip"
        ((IFACE_COUNT++))
    done <<< "$raw_ifaces"

    if [[ $IFACE_COUNT -lt 1 ]]; then
        notify-send -u critical -i network-offline "$APP_NAME" "No active network interfaces found!"
        exit 1
    fi

    ADDRS=$(echo "$ADDRS" | xargs)  # trim leading/trailing spaces

    # Auto-heal: find dispatch binary
    local DISPATCH_BIN=$(which dispatch 2>/dev/null || true)
    if [[ -z "$DISPATCH_BIN" || ! -x "$DISPATCH_BIN" ]]; then
        # Search common locations
        for search_path in \
            "$HOME/.nvm/versions/node/"*/bin/dispatch \
            /usr/local/bin/dispatch \
            /usr/bin/dispatch \
            "$HOME/.npm-global/bin/dispatch" \
            "$HOME/.local/bin/dispatch"; do
            [[ -x "$search_path" ]] && DISPATCH_BIN="$search_path" && break
        done
    fi
    [[ -z "$DISPATCH_BIN" ]] && DISPATCH_BIN="dispatch"

    # Start with auto-recovery
    local start_attempts=0
    local max_start_attempts=3
    local proxy_type="SOCKS5"
    local proxy_port=$SOCKS_PORT

    while [[ $start_attempts -lt $max_start_attempts ]]; do
        nohup "$DISPATCH_BIN" start $ADDRS > "$LOG_FILE" 2>&1 &
        local DPID=$!
        echo "$DPID" > "$PROXY_PID_FILE"
        sleep 2

        if kill -0 "$DPID" 2>/dev/null; then
            break
        fi

        ((start_attempts++))
        if [[ $start_attempts -lt $max_start_attempts ]]; then
            # Auto-heal: kill stale processes and retry
            fuser -k $SOCKS_PORT/tcp 2>/dev/null || true
            fuser -k $HTTP_PORT/tcp 2>/dev/null || true
            pkill -9 -f "dispatch" 2>/dev/null || true
            sleep 1
            warn "Start attempt $start_attempts failed, retrying..."
        fi
    done

    # If SOCKS5 failed, try HTTP mode
    if ! kill -0 "$DPID" 2>/dev/null; then
        warn "SOCKS5 failed, trying HTTP mode..."
        proxy_type="HTTP"
        proxy_port=$HTTP_PORT
        nohup "$DISPATCH_BIN" start $ADDRS --http > "$LOG_FILE" 2>&1 &
        DPID=$!
        echo "$DPID" > "$PROXY_PID_FILE"
        sleep 2

        if ! kill -0 "$DPID" 2>/dev/null; then
            # Last resort: try different port
            warn "Port $HTTP_PORT busy, trying port 8081..."
            proxy_port=8081
            nohup "$DISPATCH_BIN" start $ADDRS --http --port 8081 > "$LOG_FILE" 2>&1 &
            DPID=$!
            echo "$DPID" > "$PROXY_PID_FILE"
            sleep 2

            if ! kill -0 "$DPID" 2>/dev/null; then
                notify-send -u critical -i network-offline "$APP_NAME" "Failed to start proxy.\nCheck $LOG_FILE"
                rm -f "$PROXY_PID_FILE"
                exit 1
            fi
        fi
    fi

    local summary="Proxy Started\n\nBonded $IFACE_COUNT interface(s):$IFACE_INFO\n\n$proxy_type: localhost:$proxy_port"
    notify-send -u normal -i network-transmit-receive -t 5000 "$APP_NAME" "$summary"
}

stop_proxy() {
    [[ -f "$PROXY_PID_FILE" ]] && kill -9 "$(cat "$PROXY_PID_FILE")" 2>/dev/null && rm -f "$PROXY_PID_FILE"
    fuser -k $SOCKS_PORT/tcp 2>/dev/null || true
    fuser -k $HTTP_PORT/tcp 2>/dev/null || true
    pkill -9 -f "dispatch-proxy" 2>/dev/null || true
    pkill -9 -f "dispatch start" 2>/dev/null || true
    sleep 1
    rm -f ~/.wibluetooth-env
    notify-send -u normal -i network-offline -t 3000 "$APP_NAME" "Proxy Stopped\nReverted to direct connection."
}

list_interfaces() {
    local raw_ifaces
    raw_ifaces=$(detect_interfaces)
    echo "Available network interfaces:"
    echo ""
    while IFS='|' read -r iface ip iftype; do
        [[ -z "$iface" ]] && continue
        local icon=""
        case "$iftype" in
            wifi)       icon="📡" ;;
            ethernet)   icon="🔌" ;;
            bluetooth)  icon="📶" ;;
            *)          icon="🔗" ;;
        esac
        printf "  %s %-12s %-18s %s\n" "$icon" "[$iftype]" "$ip" "$iface"
    done <<< "$raw_ifaces"
}

toggle() { is_running && stop_proxy || start_proxy; }

case "${1:-toggle}" in
    start)      start_proxy ;;
    stop)       stop_proxy ;;
    toggle)     toggle ;;
    list)       list_interfaces ;;
    heal)
        header "Running Auto-Heal"
        # Kill stale processes
        fuser -k $SOCKS_PORT/tcp 2>/dev/null || true
        fuser -k $HTTP_PORT/tcp 2>/dev/null || true
        pkill -9 -f "dispatch" 2>/dev/null || true
        rm -f "$PROXY_PID_FILE"
        sleep 1
        # Verify dependencies
        for cmd in node npm dispatch; do
            if command -v "$cmd" &>/dev/null; then
                ok "$cmd: $(which $cmd)"
            else
                warn "$cmd: NOT FOUND"
            fi
        done
        # Check network interfaces
        local iface_count=$(ip -o link show 2>/dev/null | grep -c -v "lo:" || echo 0)
        info "Active network interfaces: $iface_count"
        ok "Auto-heal complete. Try: dispatch-toggle.sh start"
        ;;
    health)
        if is_running; then
            PID=$(cat "$PROXY_PID_FILE")
            if kill -0 "$PID" 2>/dev/null; then
                # Check if proxy responds (try SOCKS5 then HTTP)
                if curl -s -o /dev/null -w "%{http_code}" --max-time 3 --socks5 localhost:$SOCKS_PORT http://example.com 2>/dev/null | grep -q "200\|301\|302"; then
                    ok "Proxy healthy (PID: $PID, SOCKS5 on :$SOCKS_PORT)"
                elif curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://localhost:$HTTP_PORT 2>/dev/null | grep -q "200\|404"; then
                    ok "Proxy healthy (PID: $PID, HTTP on :$HTTP_PORT)"
                else
                    warn "Proxy running but not responding. Run: dispatch-toggle.sh heal"
                fi
            else
                warn "PID file exists but process dead. Run: dispatch-toggle.sh heal"
            fi
        else
            info "Proxy not running"
        fi
        ;;
    status)
        if is_running; then
            PID=$(cat "$PROXY_PID_FILE")
            IFACES=$(grep "Dispatching to" "$LOG_FILE" 2>/dev/null | sed 's/.*addresses //')
            # Determine which port is active
            local active_port=$SOCKS_PORT
            if fuser $HTTP_PORT/tcp &>/dev/null; then
                active_port=$HTTP_PORT
            fi
            notify-send -u normal -i network-transmit-receive -t 5000 "$APP_NAME" \
                "Running (PID: $PID)\n\n$IFACES\nSOCKS5: localhost:$SOCKS_PORT\nHTTP: localhost:$HTTP_PORT"
        else
            notify-send -u normal -i network-offline -t 3000 "$APP_NAME" "Stopped\nUsing direct connection."
        fi
        ;;
    *) echo "Usage: $0 {start|stop|toggle|list|status|heal|health}"; exit 1 ;;
esac
TOGGLE_SCRIPT

    chmod +x "$SCRIPT_PATH"
    ok "Toggle script: $SCRIPT_PATH"
}

# ─── Create Desktop Entry (DE-aware) ────────────────────────────
create_desktop_entry() {
    header "Creating desktop shortcut"

    detect_desktop

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

    # Install icons to hicolor (works on all DEs)
    for size in 16 22 24 32 48 64 128; do
        mkdir -p "$HOME/.local/share/icons/hicolor/${size}x${size}/apps"
        cp "$HOME/.local/share/icons/wibluetooth.svg" "$HOME/.local/share/icons/hicolor/${size}x${size}/apps/wibluetooth.svg"
    done

    # Desktop file on Desktop (if Desktop folder exists)
    if [[ -d "$HOME/Desktop" ]]; then
        mkdir -p "$HOME/Desktop"
        cat > "$HOME/Desktop/wibluetooth.desktop" << DESKTOPTEOF
[Desktop Entry]
Name=WiBluetooth
Comment=Bond multiple internet connections for faster downloads
Exec=$HOME/.local/bin/dispatch-toggle.sh toggle
Icon=wibluetooth
Terminal=false
Type=Application
Categories=Network;Utility;
Keywords=proxy;network;wifi;bluetooth;speed;load-balance;channel-bonding;
StartupNotify=false
Actions=Start;Stop;Status;List;Heal;

[Desktop Action Start]
Name=Start Proxy
Exec=$HOME/.local/bin/dispatch-toggle.sh start

[Desktop Action Stop]
Name=Stop Proxy
Exec=$HOME/.local/bin/dispatch-toggle.sh stop

[Desktop Action Status]
Name=Check Status
Exec=$HOME/.local/bin/dispatch-toggle.sh status

[Desktop Action List]
Name=List Interfaces
Exec=$HOME/.local/bin/dispatch-toggle.sh list

[Desktop Action Heal]
Name=Auto-Heal
Exec=$HOME/.local/bin/dispatch-toggle.sh heal
DESKTOPTEOF
        chmod +x "$HOME/Desktop/wibluetooth.desktop"
    fi

    # Always add to applications menu (works on all DEs)
    mkdir -p "$HOME/.local/share/applications"
    cp "$HOME/Desktop/wibluetooth.desktop" "$HOME/.local/share/applications/wibluetooth.desktop" 2>/dev/null ||
    cat > "$HOME/.local/share/applications/wibluetooth.desktop" << DESKTOPTEOF
[Desktop Entry]
Name=WiBluetooth
Comment=Bond multiple internet connections for faster downloads
Exec=$HOME/.local/bin/dispatch-toggle.sh toggle
Icon=wibluetooth
Terminal=false
Type=Application
Categories=Network;Utility;
Keywords=proxy;network;wifi;bluetooth;speed;load-balance;channel-bonding;
StartupNotify=false
Actions=Start;Stop;Status;List;Heal;

[Desktop Action Start]
Name=Start Proxy
Exec=$HOME/.local/bin/dispatch-toggle.sh start

[Desktop Action Stop]
Name=Stop Proxy
Exec=$HOME/.local/bin/dispatch-toggle.sh stop

[Desktop Action Status]
Name=Check Status
Exec=$HOME/.local/bin/dispatch-toggle.sh status

[Desktop Action List]
Name=List Interfaces
Exec=$HOME/.local/bin/dispatch-toggle.sh list

[Desktop Action Heal]
Name=Auto-Heal
Exec=$HOME/.local/bin/dispatch-toggle.sh heal
DESKTOPTEOF

    # Update icon cache
    gtk-update-icon-cache "$HOME/.local/share/icons/hicolor/" 2>/dev/null || true

    # KDE-specific: also install to pixmaps
    if [[ "${DESKTOP,,}" == *"kde"* || "${DESKTOP,,}" == *"plasma"* ]]; then
        mkdir -p "$HOME/.local/share/pixmaps"
        cp "$HOME/.local/share/icons/wibluetooth.svg" "$HOME/.local/share/pixmaps/wibluetooth.svg" 2>/dev/null || true
    fi

    ok "Desktop shortcut created"
}

# ─── Main ───────────────────────────────────────────────────────
main() {
    detect_distro
    install_deps
    install_dispatch
    create_toggle_script
    create_desktop_entry

    header "Installation Complete!"
    echo -e "${GREEN}WiBluetooth is ready!${NC}\n"
    echo -e "  ${BOLD}Usage:${NC}"
    echo -e "  • Click ${CYAN}WiBluetooth${NC} on your desktop to toggle"
    echo -e "  • Right-click for Start / Stop / Status / List / Heal"
    echo -e "  • Or run: ${CYAN}dispatch-toggle.sh start|stop|toggle|list|status|heal|health${NC}"
    echo -e ""
    echo -e "  ${BOLD}Proxy Settings:${NC}"
    echo -e "  • SOCKS5 proxy: ${CYAN}localhost:1080${NC} (recommended - works with all sites)"
    echo -e "  • HTTP proxy: ${CYAN}localhost:8080${NC} (for apps that don't support SOCKS5)"
    echo -e ""
    echo -e "  ${BOLD}Multi-threaded downloads:${NC}"
    echo -e "  • ${CYAN}aria2c -x16 --all-proxy=socks5://localhost:1080 <url>${NC}"
    echo -e ""
    echo -e "  ${BOLD}Troubleshooting:${NC}"
    echo -e "  • ${CYAN}dispatch-toggle.sh heal${NC} - auto-fix issues"
    echo -e "  • ${CYAN}dispatch-toggle.sh health${NC} - check proxy status"
    echo ""
}

main "$@"
