#!/bin/bash

# Network check
# Ping uses both exit codes 1 and 2. Exit code 2 cannot be used for docker health checks,
# therefore we use this script to catch error code 2
HOST="${HEALTH_CHECK_HOST}"

if [ -z "$HOST" ]; then
    echo "Host not set! Set env 'HEALTH_CHECK_HOST'. Using default google.com for now."
    HOST="google.com"
fi

ping -c 1 "$HOST"
STATUS=$?
if [ "${STATUS}" -ne 0 ]; then
    echo "Network is down"
    exit 1
fi

echo "Network is up"

# Service check
# We expect to have at least one VPN running and exactly one qbittorrent-nox process
WIREGUARD=$(wg show | wc -l)
QBITTORRENT=$(pgrep qbittorrent-nox | wc -l)

if [ "${WIREGUARD}" -eq 0 ]; then
    echo "WireGuard is not running"
    exit 1
fi

if [ "${QBITTORRENT}" -ne 1 ]; then
    echo "qbittorrent-nox process not running"
    exit 1
fi

echo "WireGuard and qbittorrent-nox processes are running"
exit 0
