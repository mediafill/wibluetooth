#!/bin/bash
# WiBluetooth Watchdog - monitors and restarts proxy components
# Runs as a daemon, checks every 30 seconds

PID_DIR="/tmp"
SOCKS_PID="$PID_DIR/wibluetooth-dispatch.pid"
HTTP_PID="$PID_DIR/wibluetooth-http.pid"
WATCHDOG_PID="$PID_DIR/wibluetooth-watchdog.pid"
SOCKS_LOG="/tmp/wibluetooth-dispatch.log"
HTTP_LOG="/tmp/wibluetooth-http.log"
SOCKS_PORT=1080
HTTP_PORT=8888

echo $$ > "$WATCHDOG_PID"

kill_port() {
    fuser -k "$1/tcp" 2>/dev/null || true
    local pids
    pids=$(ss -tlnp "sport = :$1" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | sort -u)
    [[ -n "$pids" ]] && echo "$pids" | xargs -r kill -9 2>/dev/null
}

pid_alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

find_dispatch() {
    local d=$(which dispatch 2>/dev/null || true)
    [[ -x "$d" ]] && echo "$d" && return
    for p in "$HOME/.nvm/versions/node/"*/bin/dispatch /usr/local/bin/dispatch /usr/bin/dispatch; do
        [[ -x "$p" ]] && echo "$p" && return
    done
    echo "dispatch"
}

detect_addrs() {
    local addrs=""
    local skip="^(lo|docker|br-|veth|virbr|vboxnet|tun|tap|wg|tailscale|bond|dummy)"
    while IFS=: read -r _ iface _; do
        iface=$(echo "$iface" | xargs)
        [[ -z "$iface" ]] && continue
        [[ "$iface" =~ $skip ]] && continue
        local ip
        ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || true)
        [[ -n "$ip" ]] && addrs="$addrs $ip"
    done < <(ip -o link show | awk -F': ' '{print NR": "$2}')
    echo "$addrs" | xargs
}

while true; do
    sleep 30

    # ── Check SOCKS5 ──
    if ! pid_alive "$SOCKS_PID"; then
        echo "[$(date +%H:%M:%S)] WATCHDOG: SOCKS5 dead, restarting..." >> "$SOCKS_LOG"
        kill_port $SOCKS_PORT
        sleep 2
        addrs=$(detect_addrs)
        if [[ -n "$addrs" ]]; then
            DISPATCH_BIN=$(find_dispatch)
            nohup "$DISPATCH_BIN" start $addrs >> "$SOCKS_LOG" 2>&1 &
            echo $! > "$SOCKS_PID"
            sleep 2
            pid_alive "$SOCKS_PID" && echo "[$(date +%H:%M:%S)] WATCHDOG: SOCKS5 restarted (PID: $(cat "$SOCKS_PID"))" >> "$SOCKS_LOG"
        fi
    else
        # Check if SOCKS5 is responsive
        if ! curl -s -o /dev/null --max-time 5 --socks5-hostname localhost:$SOCKS_PORT http://example.com 2>/dev/null; then
            echo "[$(date +%H:%M:%S)] WATCHDOG: SOCKS5 unresponsive, restarting..." >> "$SOCKS_LOG"
            kill -9 "$(cat "$SOCKS_PID")" 2>/dev/null || true
            kill_port $SOCKS_PORT
            rm -f "$SOCKS_PID"
            sleep 2
            addrs=$(detect_addrs)
            if [[ -n "$addrs" ]]; then
                DISPATCH_BIN=$(find_dispatch)
                nohup "$DISPATCH_BIN" start $addrs >> "$SOCKS_LOG" 2>&1 &
                echo $! > "$SOCKS_PID"
                sleep 2
                pid_alive "$SOCKS_PID" && echo "[$(date +%H:%M:%S)] WATCHDOG: SOCKS5 restarted (PID: $(cat "$SOCKS_PID"))" >> "$SOCKS_LOG"
            fi
        fi
    fi

    # ── Check HTTP bridge ──
    if ! pid_alive "$HTTP_PID"; then
        echo "[$(date +%H:%M:%S)] WATCHDOG: HTTP bridge dead, restarting..." >> "$HTTP_LOG"
        kill_port $HTTP_PORT
        sleep 1
        nohup python3 "$HOME/.local/bin/wibluetooth-proxy.py" >> "$HTTP_LOG" 2>&1 &
        echo $! > "$HTTP_PID"
        sleep 1
        pid_alive "$HTTP_PID" && echo "[$(date +%H:%M:%S)] WATCHDOG: HTTP bridge restarted (PID: $(cat "$HTTP_PID"))" >> "$HTTP_LOG"
    fi
done
