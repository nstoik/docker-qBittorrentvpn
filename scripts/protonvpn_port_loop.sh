#!/bin/bash
set -uo pipefail

# =============================================================================
# ProtonVPN NAT-PMP keep-alive
# Renews the NAT-PMP mapping every RENEW_INTERVAL while it works, retries with
# exponential backoff while it doesn't, and pushes port changes to qBittorrent.
# Never exits: a failed renewal drops back to the retry loop.
# Usage: protonvpn_port_loop.sh [port qBittorrent was started with]
# =============================================================================

# --------------------------
# Configuration
# --------------------------
IP_PORT_FILE="/config/wireguard/public_ip_port.txt"
CONF_FILE="/config/qBittorrent/config/qBittorrent.conf"
RENEW_INTERVAL=45  # seconds, Proton leases last 60s
BACKOFF_MIN=15     # seconds
BACKOFF_MAX=300    # seconds

log() { echo "$1" | ts '%Y-%m-%d %H:%M:%.S'; }

qbittorrent_running() { pgrep -x qbittorrent-nox >/dev/null; }

# --------------------------
# qBittorrent port update
# --------------------------
webui_url() {
    local scheme=http
    if grep -q '^WebUI\\HTTPS\\Enabled=true' "$CONF_FILE" 2>/dev/null; then
        scheme=https
    fi
    echo "${scheme}://127.0.0.1:${WEBUI_PORT:-8080}"
}

# Set the listening port through the WebUI API and read it back to confirm.
# Localhost is whitelisted by qbittorrent/start.sh; QBT_WEBUI_USERNAME and
# QBT_WEBUI_PASSWORD are used instead if set.
set_port_via_api() {
    local port="$1" url jar rc=1
    url=$(webui_url)
    jar=$(mktemp)
    # -k: a self-signed WebUI certificate is expected on 127.0.0.1
    local curl_args=(-fsS -k --max-time 10 -b "$jar" -c "$jar" -H "Referer: ${url}")

    if [[ -n "${QBT_WEBUI_USERNAME:-}" ]]; then
        # Password goes in via stdin so it doesn't show up in the process list
        if [[ "$(printf '%s' "${QBT_WEBUI_PASSWORD:-}" | curl "${curl_args[@]}" \
                --data-urlencode "username=${QBT_WEBUI_USERNAME}" \
                --data-urlencode "password@-" \
                "${url}/api/v2/auth/login" 2>/dev/null)" != "Ok." ]]; then
            log "[warn] qBittorrent WebUI login failed for user '${QBT_WEBUI_USERNAME}'"
        fi
    fi

    if curl "${curl_args[@]}" --data-urlencode "json={\"listen_port\":${port}}" \
            "${url}/api/v2/app/setPreferences" >/dev/null 2>&1 \
        && curl "${curl_args[@]}" "${url}/api/v2/app/preferences" 2>/dev/null \
            | grep -q "\"listen_port\":${port}[,}]"; then
        rc=0
    fi
    rm -f "$jar"
    return $rc
}

# Fallback when the API is unusable: qBittorrent rewrites its config on exit, so
# stop it, set Session\Port, and start it again
set_port_via_restart() {
    local port="$1"
    log "[warn] Restarting qBittorrent to apply port ${port}"
    /bin/bash /etc/qbittorrent/qbittorrent.init stop >/dev/null 2>&1
    for _ in {1..30}; do
        qbittorrent_running || break
        sleep 1
    done
    if qbittorrent_running; then
        log "[error] qBittorrent did not stop, port ${port} not applied"
        return 1
    fi
    /bin/bash /etc/qbittorrent/set_incoming_port.sh "$port"
    rm -f /config/qBittorrent/config/lockfile /config/qBittorrent/config/ipc-socket
    /bin/bash /etc/qbittorrent/qbittorrent.init start
    sleep 2
    qbittorrent_running
}

apply_port() {
    local port="$1"
    # qBittorrent is only ever started by qbittorrent/start.sh, after the
    # iptables kill switch is in place; never start it from here before then
    if ! qbittorrent_running; then
        log "[info] qBittorrent not running yet, will apply port ${port} on next renewal"
        return 1
    fi
    # The WebUI can take a few seconds to come up after the process starts
    for _ in 1 2 3; do
        if set_port_via_api "$port"; then
            log "[info] qBittorrent listening port set to ${port} via WebUI API"
            return 0
        fi
        sleep 5
    done
    log "[warn] Could not set qBittorrent listening port via WebUI API at $(webui_url)"
    set_port_via_restart "$port"
}

# --------------------------
# Main loop
# --------------------------
applied_port="${1:-}"
mapped=false
backoff=$BACKOFF_MIN
delay=$BACKOFF_MIN
if [[ -n "$applied_port" ]]; then
    mapped=true
    delay=$RENEW_INTERVAL
fi

log "[info] NAT-PMP keep-alive started (renew every ${RENEW_INTERVAL}s, retry backoff ${BACKOFF_MIN}-${BACKOFF_MAX}s)"
while true; do
    sleep "$delay"

    if NATPMP_QUIET=yes /etc/scripts/protonvpn_port.sh; then
        port=$(cut -d: -f2 "$IP_PORT_FILE")
        if ! $mapped; then
            log "[info] NAT-PMP port forwarding active: $(<"$IP_PORT_FILE")"
            mapped=true
        fi
        backoff=$BACKOFF_MIN
        delay=$RENEW_INTERVAL

        if [[ "$port" != "$applied_port" ]]; then
            log "[info] Forwarded port changed: ${applied_port:-none} -> ${port}, updating qBittorrent"
            # On failure applied_port is left alone, so the next renewal retries
            if apply_port "$port"; then
                applied_port="$port"
            fi
        fi
    else
        # Don't leave a stale port behind for the healthcheck to report
        rm -f "$IP_PORT_FILE"
        if $mapped; then
            log "[warn] NAT-PMP renewal failed, port forwarding lost"
            mapped=false
        fi
        log "[warn] NAT-PMP mapping unavailable, retrying in ${backoff}s"
        delay=$backoff
        backoff=$(( backoff * 2 > BACKOFF_MAX ? BACKOFF_MAX : backoff * 2 ))
    fi
done
