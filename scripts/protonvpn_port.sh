#!/bin/bash
set -euo pipefail

# =============================================================================
# ProtonVPN WireGuard NAT-PMP Startup Script
# Waits for VPN tunnel, retrieves NAT-PMP forwarded port, and saves IP:PORT.
# =============================================================================

# --------------------------
# Configuration
# --------------------------
IP_PORT_FILE="/config/wireguard/public_ip_port.txt"
NATPMP_GATEWAY="10.2.0.1"   # ProtonVPN internal NAT-PMP gateway
LEASE_TIME=60  # seconds

# --------------------------
# Wait for VPN
# --------------------------
echo "[info] Waiting for WireGuard tunnel..." | ts '%Y-%m-%d %H:%M:%.S'
while ! ip link show wg0 &>/dev/null; do sleep 1; done
echo "[info] WireGuard is up" | ts '%Y-%m-%d %H:%M:%.S'

# --------------------------
# NAT-PMP Setup
# --------------------------
echo "[info] Using NAT-PMP gateway: ${NATPMP_GATEWAY}" | ts '%Y-%m-%d %H:%M:%.S'
echo "[info] Requesting NAT-PMP port mappings (UDP + TCP, ${LEASE_TIME}s)" | ts '%Y-%m-%d %H:%M:%.S'

UDP_OUTPUT=$(natpmpc -g "${NATPMP_GATEWAY}" -a 0 1 udp "${LEASE_TIME}" 2>&1 || true)
TCP_OUTPUT=$(natpmpc -g "${NATPMP_GATEWAY}" -a 0 1 tcp "${LEASE_TIME}" 2>&1 || true)

EXTERNAL_IP=$(echo "$UDP_OUTPUT" | grep -oP '(?<=Public IP address : )\S+' || true)
UDP_PORT=$(echo "$UDP_OUTPUT" | grep -oP '(?<=Mapped public port )\d+' || true)
TCP_PORT=$(echo "$TCP_OUTPUT" | grep -oP '(?<=Mapped public port )\d+' || true)

if [[ -z "$EXTERNAL_IP" || -z "$UDP_PORT" ]]; then
    echo "[error] Failed to retrieve NAT-PMP external IP or port" | ts '%Y-%m-%d %H:%M:%.S'
    echo "[debug] UDP_OUTPUT:" | ts '%Y-%m-%d %H:%M:%.S'; echo "$UDP_OUTPUT" | tail -n10
    echo "[debug] TCP_OUTPUT:" | ts '%Y-%m-%d %H:%M:%.S'; echo "$TCP_OUTPUT" | tail -n10
    exit 1
fi

echo "[info] External IP: $EXTERNAL_IP" | ts '%Y-%m-%d %H:%M:%.S'
echo "[info] UDP Port: $UDP_PORT, TCP Port: ${TCP_PORT:-none}" | ts '%Y-%m-%d %H:%M:%.S'
echo "$EXTERNAL_IP:$UDP_PORT" > "$IP_PORT_FILE"
export INCOMING_PORT="$UDP_PORT"
echo "[info] NAT-PMP setup complete" | ts '%Y-%m-%d %H:%M:%.S'

# --------------------------
# Background NAT-PMP renewal
# --------------------------
renew_script() {
    echo "[info] Renewing NAT-PMP ports forever..." | ts '%Y-%m-%d %H:%M:%.S'
    while true; do
        if ! natpmpc -a 1 0 udp "$LEASE_TIME" -g "$NATPMP_GATEWAY" \
             && natpmpc -a 1 0 tcp "$LEASE_TIME" -g "$NATPMP_GATEWAY"; then
            echo "[error] NAT-PMP renewal failed, stopping loop" | ts '%Y-%m-%d %H:%M:%.S'
            break
        fi
        RENEW_SLEEP=$((LEASE_TIME - 15))
        sleep "$RENEW_SLEEP"
    done
}

# Launch in background
nohup bash -c 'renew_script' >/dev/null 2>&1 &