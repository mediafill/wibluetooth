#!/bin/bash
# WiBluetooth - Multi-interface proxy load balancer
# Combines WiFi, Ethernet, and Bluetooth connections via SOCKS5 + HTTP bridge
# Auto-heals, auto-reconnects Bluetooth, auto-sources env vars
# No set -e: we handle errors explicitly throughout

APP_NAME="WiBluetooth"
SOCKS_PORT=1080
HTTP_PORT=8888
PID_DIR="/tmp"
SOCKS_PID="$PID_DIR/wibluetooth-dispatch.pid"
HTTP_PID="$PID_DIR/wibluetooth-http.pid"
ENV_FILE="$HOME/.wibluetooth-env"
LOG_DIR="/tmp"
SOCKS_LOG="$LOG_DIR/wibluetooth-dispatch.log"
HTTP_LOG="$LOG_DIR/wibluetooth-http.log"
WATCHDOG_PID="$PID_DIR/wibluetooth-watchdog.pid"
DISPATCH_BIN=""

# ─── Helpers ───────────────────────────────────────────────────────────────────
ok()   { echo -e "  \033[0;32m✓\033[0m $*"; }
warn() { echo -e "  \033[0;33m⚠\033[0m $*"; }
err()  { echo -e "  \033[0;31m✗\033[0m $*"; }
info() { echo -e "  \033[0;34mℹ\033[0m $*"; }
header() { echo -e "\n\033[1;36m$*\033[0m"; }

log() {
    local ts; ts=$(date '+%H:%M:%S')
    echo "[$ts] $*" >> "$SOCKS_LOG" 2>/dev/null || true
}

pid_alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

kill_port() {
    local port=$1
    # Try fuser first (fast)
    fuser -k "$port/tcp" 2>/dev/null && return 0
    # Fallback: find by ss
    local pids
    pids=$(ss -tlnp "sport = :$port" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | sort -u)
    [[ -n "$pids" ]] && echo "$pids" | xargs -r kill -9 2>/dev/null
}

find_dispatch() {
    DISPATCH_BIN=$(which dispatch 2>/dev/null || true)
    if [[ -z "$DISPATCH_BIN" || ! -x "$DISPATCH_BIN" ]]; then
        for p in \
            "$HOME/.nvm/versions/node/"*/bin/dispatch \
            /usr/local/bin/dispatch \
            /usr/bin/dispatch \
            "$HOME/.npm-global/bin/dispatch" \
            "$HOME/.local/bin/dispatch"; do
            [[ -x "$p" ]] && DISPATCH_BIN="$p" && break
        done
    fi
    [[ -z "$DISPATCH_BIN" ]] && DISPATCH_BIN="dispatch"
}

# ─── Interface Detection ───────────────────────────────────────────────────────
detect_interfaces() {
    local result=()
    local skip="^(lo|docker|br-|veth|virbr|vboxnet|tun|tap|wg|tailscale|bond|dummy|veth)"

    while IFS=: read -r _ iface _; do
        iface=$(echo "$iface" | xargs)
        [[ -z "$iface" ]] && continue
        [[ "$iface" =~ $skip ]] && continue

        local ip
        ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || true)
        [[ -z "$ip" ]] && continue

        local state
        state=$(cat /sys/class/net/"$iface"/operstate 2>/dev/null || echo "unknown")

        local is_bt=false
        case "$iface" in bnep*|enx*) is_bt=true ;; esac

        [[ "$state" != "up" && "$is_bt" != "true" ]] && continue

        local iftype="unknown"
        local type_raw
        type_raw=$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | grep "^${iface}:" | cut -d: -f2 || true)
        case "$type_raw" in
            wifi)       iftype="wifi" ;;
            ethernet)   iftype="ethernet" ;;
            bluetooth|bt) iftype="bluetooth" ;;
            tun|tunl*)  iftype="vpn" ;;
        esac
        if [[ "$iftype" == "unknown" ]]; then
            case "$iface" in
                wl*)         iftype="wifi" ;;
                bnep*|enx*) iftype="bluetooth" ;;
                eth*|en*)    iftype="ethernet" ;;
                tun*|tap*)   iftype="vpn" ;;
            esac
        fi
        [[ "$iftype" == "vpn" ]] && continue

        result+=("${iface}|${ip}|${iftype}")
    done < <(ip -o link show | awk -F': ' '{print NR": "$2}')

    if [[ ${#result[@]} -gt 0 ]]; then
        printf '%s\n' "${result[@]}"
    fi
}

# ─── Bluetooth Auto-Connect ───────────────────────────────────────────────────
auto_connect_bluetooth() {
    local raw_ifaces
    raw_ifaces=$(detect_interfaces)

    if echo "$raw_ifaces" | grep -q "bluetooth"; then
        return 0
    fi

    local bt_conn
    bt_conn=$(nmcli -t -f NAME,UUID,TYPE connection show 2>/dev/null | grep ':bluetooth:' | head -1)
    [[ -z "$bt_conn" ]] && return 1

    local bt_uuid bt_name
    bt_uuid=$(echo "$bt_conn" | cut -d: -f2)
    bt_name=$(echo "$bt_conn" | cut -d: -f1)

    info "Activating Bluetooth: $bt_name"
    nmcli connection up "$bt_uuid" &>/dev/null || true
    sleep 5

    raw_ifaces=$(detect_interfaces)
    if echo "$raw_ifaces" | grep -q "bluetooth"; then
        ok "Bluetooth connected: $bt_name"
        return 0
    fi
    warn "Bluetooth activation failed"
    return 1
}

# ─── Start ─────────────────────────────────────────────────────────────────────
start_proxy() {
    find_dispatch

    # Detect interfaces
    local raw_ifaces
    raw_ifaces=$(detect_interfaces)

    if [[ -z "$raw_ifaces" ]]; then
        # Try Bluetooth auto-connect
        auto_connect_bluetooth
        raw_ifaces=$(detect_interfaces)
    fi

    if [[ -z "$raw_ifaces" ]]; then
        err "No active network interfaces found!"
        notify-send -u critical -i network-offline "$APP_NAME" "No active network interfaces found!" 2>/dev/null || true
        exit 1
    fi

    # Build address list
    local ADDRS="" IFACE_INFO="" IFACE_COUNT=0
    while IFS='|' read -r iface ip iftype; do
        [[ -z "$iface" ]] && continue
        ADDRS="$ADDRS $ip"
        local icon="🔗"
        case "$iftype" in
            wifi)       icon="📡" ;;
            ethernet)   icon="🔌" ;;
            bluetooth)  icon="📶" ;;
        esac
        IFACE_INFO="$IFACE_INFO\n${icon} ${iftype^} ($iface): $ip"
        IFACE_COUNT=$((IFACE_COUNT + 1))
    done <<< "$raw_ifaces"

    ADDRS=$(echo "$ADDRS" | xargs)

    # ── Start SOCKS5 dispatch-proxy ──────────────────────────────────────
    kill_port $SOCKS_PORT
    sleep 1

    local attempt=0 max_attempts=3
    while [[ $attempt -lt $max_attempts ]]; do
        nohup "$DISPATCH_BIN" start $ADDRS > "$SOCKS_LOG" 2>&1 &
        echo $! > "$SOCKS_PID"
        sleep 2

        if pid_alive "$SOCKS_PID"; then
            break
        fi

        ((attempt++))
        if [[ $attempt -lt $max_attempts ]]; then
            kill_port $SOCKS_PORT
            kill_port $HTTP_PORT
            pkill -9 -f "dispatch start" 2>/dev/null || true
            sleep 1
            warn "SOCKS5 attempt $attempt failed, retrying..."
        fi
    done

    if ! pid_alive "$SOCKS_PID"; then
        err "Failed to start SOCKS5 proxy after $max_attempts attempts"
        notify-send -u critical -i network-offline "$APP_NAME" "SOCKS5 failed.\nCheck $SOCKS_LOG" 2>/dev/null || true
        exit 1
    fi
    ok "SOCKS5 started on :$SOCKS_PORT (PID: $(cat "$SOCKS_PID"))"

    # ── Start HTTP CONNECT bridge ────────────────────────────────────────
    if pid_alive "$HTTP_PID"; then
        info "HTTP bridge already running (PID: $(cat "$HTTP_PID"))"
    else
        kill_port $HTTP_PORT
        sleep 1
        nohup python3 "$HOME/.local/bin/wibluetooth-proxy.py" > "$HTTP_LOG" 2>&1 &
        echo $! > "$HTTP_PID"
        sleep 1

        if pid_alive "$HTTP_PID"; then
            ok "HTTP bridge started on :$HTTP_PORT (PID: $(cat "$HTTP_PID"))"
        else
            warn "HTTP bridge failed to start (SOCKS5 still works)"
        fi
    fi

    # ── Write env vars ───────────────────────────────────────────────────
    write_env_file

    # ── Start watchdog ───────────────────────────────────────────────────
    start_watchdog

    # ── Notify ───────────────────────────────────────────────────────────
    local summary="Proxy Started\n\nBonded $IFACE_COUNT interface(s):$IFACE_INFO\n\nSOCKS5: localhost:$SOCKS_PORT\nHTTP: localhost:$HTTP_PORT\nAuto-heal: active"
    notify-send -u normal -i network-transmit-receive -t 5000 "$APP_NAME" "$summary" 2>/dev/null || true
    echo ""
    echo -e "\033[1;36m$APP_NAME Started\033[0m"
    echo ""
    while IFS='|' read -r iface ip iftype; do
        [[ -z "$iface" ]] && continue
        local icon="🔗"
        case "$iftype" in wifi) icon="📡" ;; ethernet) icon="🔌" ;; bluetooth) icon="📶" ;; esac
        printf "  %s %-12s %-18s %s\n" "$icon" "[$iftype]" "$ip" "$iface"
    done <<< "$raw_ifaces"
    echo ""
    echo "  SOCKS5: localhost:$SOCKS_PORT"
    echo "  HTTP:   localhost:$HTTP_PORT"
    echo ""
    ok "Env vars written to $ENV_FILE"
    ok "Source it: source $ENV_FILE"
}

# ─── Stop ──────────────────────────────────────────────────────────────────────
stop_proxy() {
    info "Stopping $APP_NAME..."

    # Stop watchdog first
    if pid_alive "$WATCHDOG_PID"; then
        kill -9 "$(cat "$WATCHDOG_PID")" 2>/dev/null || true
        rm -f "$WATCHDOG_PID"
    fi
    pkill -9 -f "wibluetooth-watchdog" 2>/dev/null || true

    # Stop HTTP bridge
    if pid_alive "$HTTP_PID"; then
        kill -9 "$(cat "$HTTP_PID")" 2>/dev/null || true
    fi
    rm -f "$HTTP_PID"
    pkill -9 -f "wibluetooth-proxy.py" 2>/dev/null || true
    kill_port $HTTP_PORT

    # Stop SOCKS5 dispatch
    if pid_alive "$SOCKS_PID"; then
        kill -9 "$(cat "$SOCKS_PID")" 2>/dev/null || true
    fi
    rm -f "$SOCKS_PID"
    pkill -9 -f "dispatch start" 2>/dev/null || true
    pkill -9 -f "dispatch-proxy" 2>/dev/null || true
    kill_port $SOCKS_PORT

    sleep 1

    # Unset env vars
    write_env_file true

    notify-send -u normal -i network-offline -t 3000 "$APP_NAME" "Proxy Stopped\nReverted to direct connection." 2>/dev/null || true
    ok "Proxy stopped. Direct connection restored."
}

# ─── Env File ──────────────────────────────────────────────────────────────────
write_env_file() {
    local unset_mode="${1:-false}"
    if [[ "$unset_mode" == "true" ]]; then
        cat > "$ENV_FILE" <<'ENVEOF'
unset http_proxy 2>/dev/null
unset https_proxy 2>/dev/null
unset all_proxy 2>/dev/null
unset HTTP_PROXY 2>/dev/null
unset HTTPS_PROXY 2>/dev/null
unset ALL_PROXY 2>/dev/null
export no_proxy=localhost,127.0.0.1,::1
export NO_PROXY=localhost,127.0.0.1,::1
ENVEOF
    else
        cat > "$ENV_FILE" <<ENVEOF
export http_proxy=http://localhost:$HTTP_PORT
export https_proxy=http://localhost:$HTTP_PORT
export all_proxy=http://localhost:$HTTP_PORT
export HTTP_PROXY=http://localhost:$HTTP_PORT
export HTTPS_PROXY=http://localhost:$HTTP_PORT
export ALL_PROXY=http://localhost:$HTTP_PORT
export no_proxy=localhost,127.0.0.1,::1
export NO_PROXY=localhost,127.0.0.1,::1
ENVEOF
    fi
}

# ─── Watchdog (auto-heal loop) ────────────────────────────────────────────────
start_watchdog() {
    # Kill existing watchdog
    if pid_alive "$WATCHDOG_PID"; then
        kill -9 "$(cat "$WATCHDOG_PID")" 2>/dev/null || true
        sleep 1
    fi
    pkill -f "wibluetooth-watchdog.sh" 2>/dev/null || true
    sleep 1

    nohup bash "$HOME/.local/bin/wibluetooth-watchdog.sh" > /dev/null 2>&1 &
    disown
    sleep 1
    if pid_alive "$WATCHDOG_PID"; then
        ok "Watchdog started (PID: $(cat "$WATCHDOG_PID"))"
    else
        warn "Watchdog failed to start"
    fi
}

# ─── Heal ──────────────────────────────────────────────────────────────────────
heal_proxy() {
    header "Running Auto-Heal"

    # Kill everything
    info "Killing stale processes..."
    pid_alive "$WATCHDOG_PID" && kill -9 "$(cat "$WATCHDOG_PID")" 2>/dev/null || true
    pkill -9 -f "wibluetooth-watchdog" 2>/dev/null || true
    pid_alive "$HTTP_PID" && kill -9 "$(cat "$HTTP_PID")" 2>/dev/null || true
    pkill -9 -f "wibluetooth-proxy.py" 2>/dev/null || true
    pid_alive "$SOCKS_PID" && kill -9 "$(cat "$SOCKS_PID")" 2>/dev/null || true
    pkill -9 -f "dispatch start" 2>/dev/null || true
    pkill -9 -f "dispatch-proxy" 2>/dev/null || true
    kill_port $SOCKS_PORT
    kill_port $HTTP_PORT
    rm -f "$SOCKS_PID" "$HTTP_PID" "$WATCHDOG_PID"
    sleep 2

    # Check dependencies
    header "Checking dependencies"
    for cmd in node npm python3 curl; do
        if command -v "$cmd" &>/dev/null; then
            ok "$cmd: $(which "$cmd")"
        else
            err "$cmd: NOT FOUND"
        fi
    done

    # Check dispatch binary
    find_dispatch
    if [[ -x "$DISPATCH_BIN" ]]; then
        ok "dispatch: $DISPATCH_BIN"
    else
        err "dispatch: NOT FOUND - reinstall with: npm install -g dispatch-proxy"
    fi

    # Check Python proxy
    if python3 -c "import socket" 2>/dev/null; then
        ok "python3: available"
    else
        err "python3: socket module missing"
    fi

    # Check Bluetooth
    header "Checking Bluetooth"
    local bt_state
    bt_state=$(bluetoothctl show 2>/dev/null | grep "Powered:" | awk '{print $2}')
    if [[ "$bt_state" == "yes" ]]; then
        ok "Bluetooth powered on"
    else
        warn "Bluetooth powered off - attempting to enable"
        bluetoothctl power on 2>/dev/null || true
        sleep 2
    fi

    # Check interfaces
    header "Checking interfaces"
    local raw_ifaces
    raw_ifaces=$(detect_interfaces)
    if [[ -n "$raw_ifaces" ]]; then
        while IFS='|' read -r iface ip iftype; do
            [[ -z "$iface" ]] && continue
            local icon="🔗"
            case "$iftype" in wifi) icon="📡" ;; ethernet) icon="🔌" ;; bluetooth) icon="📶" ;; esac
            ok "${icon} $iftype ($iface): $ip"
        done <<< "$raw_ifaces"
    else
        err "No active interfaces detected"
    fi

    # Try Bluetooth auto-connect
    auto_connect_bluetooth || true

    header "Heal complete"
    ok "Run: dispatch-toggle.sh start"
}

# ─── Health ────────────────────────────────────────────────────────────────────
health_check() {
    header "Health Check"

    local all_ok=true

    # SOCKS5
    if pid_alive "$SOCKS_PID"; then
        if curl -s -o /dev/null --max-time 3 --socks5-hostname localhost:$SOCKS_PORT http://example.com 2>/dev/null; then
            ok "SOCKS5: healthy (PID: $(cat "$SOCKS_PID"), port $SOCKS_PORT)"
        else
            warn "SOCKS5: process alive but not responding"
            all_ok=false
        fi
    else
        err "SOCKS5: not running"
        all_ok=false
    fi

    # HTTP bridge
    if pid_alive "$HTTP_PID"; then
        if curl -s -o /dev/null --max-time 3 --proxy http://127.0.0.1:$HTTP_PORT http://example.com 2>/dev/null; then
            ok "HTTP bridge: healthy (PID: $(cat "$HTTP_PID"), port $HTTP_PORT)"
        else
            warn "HTTP bridge: process alive but not responding"
            all_ok=false
        fi
    else
        err "HTTP bridge: not running"
        all_ok=false
    fi

    # Watchdog
    if pid_alive "$WATCHDOG_PID"; then
        ok "Watchdog: active (PID: $(cat "$WATCHDOG_PID"))"
    else
        warn "Watchdog: not running (auto-heal disabled)"
    fi

    # Interfaces
    local raw_ifaces
    raw_ifaces=$(detect_interfaces)
    local iface_count=0
    while IFS='|' read -r iface ip iftype; do
        [[ -z "$iface" ]] && continue
        ((iface_count++))
    done <<< "$raw_ifaces"
    ok "Interfaces: $iface_count active"

    # End-to-end test
    header "End-to-end test"
    local public_ip
    public_ip=$(curl -s --proxy http://127.0.0.1:$HTTP_PORT --max-time 5 http://ifconfig.me 2>/dev/null || echo "FAILED")
    if [[ "$public_ip" != "FAILED" ]]; then
        ok "HTTPS through proxy: $public_ip"
    else
        err "HTTPS through proxy: FAILED"
        all_ok=false
    fi

    echo ""
    if $all_ok; then
        ok "All systems operational"
    else
        warn "Issues detected - run: dispatch-toggle.sh heal"
    fi
}

# ─── Status (desktop notification) ────────────────────────────────────────────
show_status() {
    if pid_alive "$SOCKS_PID"; then
        local ifaces
        ifaces=$(grep "Dispatching to" "$SOCKS_LOG" 2>/dev/null | sed 's/.*addresses //' | tail -1)
        notify-send -u normal -i network-transmit-receive -t 5000 "$APP_NAME" \
            "Running\n\n$ifaces\nSOCKS5: :$SOCKS_PORT | HTTP: :$HTTP_PORT\nWatchdog: active" 2>/dev/null || true
    else
        notify-send -u normal -i network-offline -t 3000 "$APP_NAME" "Stopped\nDirect connection." 2>/dev/null || true
    fi
}

# ─── List Interfaces ───────────────────────────────────────────────────────────
list_interfaces() {
    echo "Available network interfaces:"
    echo ""
    while IFS='|' read -r iface ip iftype; do
        [[ -z "$iface" ]] && continue
        local icon="🔗"
        case "$iftype" in wifi) icon="📡" ;; ethernet) icon="🔌" ;; bluetooth) icon="📶" ;; esac
        printf "  %s %-12s %-18s %s\n" "$icon" "[$iftype]" "$ip" "$iface"
    done <<< "$(detect_interfaces)"
}

# ─── Toggle ────────────────────────────────────────────────────────────────────
toggle() {
    if pid_alive "$SOCKS_PID"; then
        stop_proxy
    else
        start_proxy
    fi
}

# ─── Main ──────────────────────────────────────────────────────────────────────
case "${1:-toggle}" in
    start)          start_proxy ;;
    stop)           stop_proxy ;;
    toggle)         toggle ;;
    restart)        stop_proxy; sleep 2; start_proxy ;;
    list)           list_interfaces ;;
    status)         show_status ;;
    health)         health_check ;;
    heal)           heal_proxy ;;
    watchdog)       start_watchdog ;;
    env)            write_env_file; cat "$ENV_FILE" ;;
    *)              echo "Usage: $0 {start|stop|toggle|restart|list|status|health|heal|watchdog|env}"; exit 1 ;;
esac
