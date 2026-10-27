#!/bin/bash
# Sets Session\Port in qBittorrent.conf. Only takes effect if qBittorrent is not
# running, since it rewrites its config on exit.
# Usage: set_incoming_port.sh <port>

INCOMING_PORT="$1"
CONF_FILE="/config/qBittorrent/config/qBittorrent.conf"
echo "[info] Setting incoming port in qBittorrent config: ${INCOMING_PORT}" | ts '%Y-%m-%d %H:%M:%.S'

# Show current port before updating
CURRENT_PORT=$(grep -m 1 "Session\\\\Port=" "$CONF_FILE" | cut -d= -f2 || echo "none")
echo "[info] Current qBittorrent port: ${CURRENT_PORT}" | ts '%Y-%m-%d %H:%M:%.S'

# Replace existing Session\Port= value if found
if grep -q "^Session\\\\Port=" "$CONF_FILE"; then
	sed -i "s@^Session\\\\Port=.*@Session\\\\Port=${INCOMING_PORT}@" "$CONF_FILE"
	echo "[info] Replaced existing Session\\Port with ${INCOMING_PORT}" | ts '%Y-%m-%d %H:%M:%.S'
else
	# If not found, insert it under the [BitTorrent] section
	if grep -q "^\[BitTorrent\]" "$CONF_FILE"; then
		 sed -i "/^\[BitTorrent\]/a Session\\\\Port=${INCOMING_PORT}" "$CONF_FILE"
		echo "[info] Inserted Session\\Port=${INCOMING_PORT} under [BitTorrent] section" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] [BitTorrent] section not found — appending Session\\Port=${INCOMING_PORT} at end of file" | ts '%Y-%m-%d %H:%M:%.S'
		echo -e "\n[BitTorrent]\nSession\\Port=${INCOMING_PORT}" >> "$CONF_FILE"
	fi
fi

# Show final result
NEW_PORT=$(grep -m 1 "Session\\\\Port=" "$CONF_FILE" | cut -d= -f2 || echo "none")
echo "[info] Updated Session\\Port in config: ${NEW_PORT}" | ts '%Y-%m-%d %H:%M:%.S'
