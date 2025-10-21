#!/bin/bash
set -euo pipefail

# Network check
HOST="${HEALTH_CHECK_HOST:-google.com}"
echo "[info] Pinging healthcheck host: $HOST"
if ! ping -c 1 -w 2 "$HOST" &>/dev/null; then
    echo "[error] Network is down, cannot reach $HOST"
    exit 1
fi
echo "[info] Network is up"

# WireGuard check
WG_INTERFACE="wg0"
if ! ip link show "$WG_INTERFACE" &>/dev/null; then
    echo "[error] WireGuard interface $WG_INTERFACE is not running"
    exit 1
fi
echo "[info] WireGuard interface $WG_INTERFACE is up"

# qBittorrent check
QBITTORRENT_COUNT=$(pgrep -x qbittorrent-nox | wc -l)
if [ "$QBITTORRENT_COUNT" -ne 1 ]; then
    echo "[error] qbittorrent-nox process not running (found $QBITTORRENT_COUNT)"
    exit 1
fi
echo "[info] qbittorrent-nox is running"

# ProtonVPN NAT-PMP port check
if [[ "${VPN_PROVIDER:-}" == "protonvpn" ]]; then
    IP_PORT_FILE="/config/wireguard/public_ip_port.txt"
    LAST_PORT_FILE="/config/wireguard/last_port.txt"

    if [[ ! -f "$IP_PORT_FILE" ]]; then
        echo "[error] IP/Port file missing: $IP_PORT_FILE"
        exit 1
    fi

    CURRENT_PORT=$(cut -d: -f2 "$IP_PORT_FILE")
    if [[ -z "$CURRENT_PORT" ]]; then
        echo "[error] Failed to read current port from $IP_PORT_FILE"
        exit 1
    fi

    # If last_port.txt does not exist, create it and continue
    if [[ ! -f "$LAST_PORT_FILE" ]]; then
        echo "$CURRENT_PORT" > "$LAST_PORT_FILE"
        echo "[info] Last port file created with port: $CURRENT_PORT"
    else
        LAST_PORT=$(<"$LAST_PORT_FILE")
        if [[ "$CURRENT_PORT" != "$LAST_PORT" ]]; then
            echo "[error] NAT-PMP port changed: $LAST_PORT -> $CURRENT_PORT"
            exit 1
        fi
    fi

    echo "[info] NAT-PMP port check passed: $CURRENT_PORT"
fi

echo "[info] Healthcheck passed"
exit 0
