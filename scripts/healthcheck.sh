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
# Port forwarding is best-effort: protonvpn_port_loop.sh keeps retrying it and
# applies port changes to qBittorrent itself, so a missing port only fails the
# healthcheck when NATPMP_REQUIRED is set.
if [[ "${VPN_PROVIDER:-}" == "protonvpn" ]]; then
    IP_PORT_FILE="/config/wireguard/public_ip_port.txt"
    NATPMP_REQUIRED="${NATPMP_REQUIRED:-no}"

    CURRENT_PORT=""
    if [[ -f "$IP_PORT_FILE" ]]; then
        CURRENT_PORT=$(cut -d: -f2 "$IP_PORT_FILE")
    fi

    if [[ -n "$CURRENT_PORT" ]]; then
        echo "[info] NAT-PMP forwarded port: $CURRENT_PORT"
    elif [[ $NATPMP_REQUIRED == "1" || $NATPMP_REQUIRED == "true" || $NATPMP_REQUIRED == "yes" ]]; then
        echo "[error] No NAT-PMP forwarded port ($IP_PORT_FILE missing or empty) and NATPMP_REQUIRED is '$NATPMP_REQUIRED'"
        exit 1
    else
        echo "[warn] No NAT-PMP forwarded port ($IP_PORT_FILE missing or empty), port forwarding is being retried"
    fi
fi

echo "[info] Healthcheck passed"
exit 0
