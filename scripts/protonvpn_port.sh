#!/bin/bash
set -euo pipefail

# =============================================================================
# ProtonVPN WireGuard NAT-PMP mapping
# Makes a single attempt to map (or renew) the forwarded port over UDP + TCP
# and saves IP:PORT. Exits non-zero if either mapping fails.
# Called once by start.sh and then repeatedly by protonvpn_port_loop.sh.
# =============================================================================

# --------------------------
# Configuration
# --------------------------
IP_PORT_FILE="/config/wireguard/public_ip_port.txt"
NATPMP_GATEWAY="10.2.0.1"   # ProtonVPN internal NAT-PMP gateway
LEASE_TIME=60  # seconds
# natpmpc retries internally for ~2 min when the gateway is silent; a healthy
# gateway answers in a second or two, so cap each call
NATPMP_TIMEOUT="${NATPMP_TIMEOUT:-30}"  # seconds

log() { echo "$1" | ts '%Y-%m-%d %H:%M:%.S'; }

if ! ip link show wg0 &>/dev/null; then
    log "[error] WireGuard interface wg0 is not up, cannot request NAT-PMP mapping"
    exit 1
fi

# --------------------------
# NAT-PMP mapping
# --------------------------
natpmp_map() {
    timeout "$NATPMP_TIMEOUT" natpmpc -g "$NATPMP_GATEWAY" -a 1 0 "$1" "$LEASE_TIME" 2>&1
}

if ! UDP_OUTPUT=$(natpmp_map udp); then
    log "[error] NAT-PMP UDP mapping failed (gateway ${NATPMP_GATEWAY}, timeout ${NATPMP_TIMEOUT}s)"
    echo "$UDP_OUTPUT" | tail -n5
    exit 1
fi
if ! TCP_OUTPUT=$(natpmp_map tcp); then
    log "[error] NAT-PMP TCP mapping failed (gateway ${NATPMP_GATEWAY}, timeout ${NATPMP_TIMEOUT}s)"
    echo "$TCP_OUTPUT" | tail -n5
    exit 1
fi

EXTERNAL_IP=$(echo "$UDP_OUTPUT" | grep -oP '(?<=Public IP address : )\S+' || true)
UDP_PORT=$(echo "$UDP_OUTPUT" | grep -oP '(?<=Mapped public port )\d+' || true)
TCP_PORT=$(echo "$TCP_OUTPUT" | grep -oP '(?<=Mapped public port )\d+' || true)

if [[ -z "$EXTERNAL_IP" || -z "$UDP_PORT" || -z "$TCP_PORT" ]]; then
    log "[error] Failed to parse NAT-PMP external IP or port"
    echo "$UDP_OUTPUT" | tail -n5
    echo "$TCP_OUTPUT" | tail -n5
    exit 1
fi

if [[ "$UDP_PORT" != "$TCP_PORT" ]]; then
    log "[warn] NAT-PMP UDP port ($UDP_PORT) differs from TCP port ($TCP_PORT), using UDP port"
fi

# Write atomically so readers (start.sh, healthcheck) never see a partial file
echo "$EXTERNAL_IP:$UDP_PORT" > "${IP_PORT_FILE}.tmp"
mv -f "${IP_PORT_FILE}.tmp" "$IP_PORT_FILE"

# The renewal loop sets NATPMP_QUIET=yes and logs port changes itself, so the
# 45s renewals don't flood the container log
if [[ "${NATPMP_QUIET:-no}" != "yes" ]]; then
    log "[info] NAT-PMP mapped ${EXTERNAL_IP}:${UDP_PORT} (UDP + TCP, ${LEASE_TIME}s lease)"
fi
