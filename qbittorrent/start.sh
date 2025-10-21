#!/bin/bash
if [[ ! -e /config/qBittorrent ]]; then
	mkdir -p /config/qBittorrent/config/
	chown -R ${PUID}:${PGID} /config/qBittorrent
else
	chown -R ${PUID}:${PGID} /config/qBittorrent
fi

if [[ ! -e /config/qBittorrent/config/qBittorrent.conf ]]; then
	/bin/cp /etc/qbittorrent/qBittorrent.conf /config/qBittorrent/config/qBittorrent.conf
	chmod 755 /config/qBittorrent/config/qBittorrent.conf
fi

# Check for existing group by GID
if getent group "$PGID" >/dev/null; then
    echo "[info] Group with GID $PGID exists"
else
    groupadd -g "$PGID" qbittorrent
    echo "[info] Group 'qbittorrent' created with GID $PGID"
fi

# Check for existing user by UID
if getent passwd "$PUID" >/dev/null; then
    echo "[info] User with UID $PUID exists"
else
    useradd -u "$PUID" -g "$PGID" -c "qbittorrent user" qbittorrent
    echo "[info] User 'qbittorrent' created with UID $PUID"
fi

# set umask
export UMASK=$(echo "${UMASK}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

if [[ ! -z "${UMASK}" ]]; then
  echo "[info] UMASK defined as '${UMASK}'" | ts '%Y-%m-%d %H:%M:%.S'
else
  echo "[warn] UMASK not defined (via -e UMASK), defaulting to '002'" | ts '%Y-%m-%d %H:%M:%.S'
  export UMASK="002"
fi

# Set qBittorrent WebUI and Incoming ports
if [ ! -z "${WEBUI_PORT}" ]; then
	webui_port_exist=$(cat /config/qBittorrent/config/qBittorrent.conf | grep -m 1 'WebUI\\Port='${WEBUI_PORT})
	if [[ -z "${webui_port_exist}" ]]; then
		webui_exist=$(cat /config/qBittorrent/config/qBittorrent.conf | grep -m 1 'WebUI\\Port')
		if [[ ! -z "${webui_exist}" ]]; then
			# Get line number of WebUI Port
			LINE_NUM=$(grep -Fn -m 1 'WebUI\Port' /config/qBittorrent/config/qBittorrent.conf | cut -d: -f 1)
			sed -i "${LINE_NUM}s@.*@WebUI\\Port=${WEBUI_PORT}@" /config/qBittorrent/config/qBittorrent.conf
		else
			echo "WebUI\Port=${WEBUI_PORT}" >> /config/qBittorrent/config/qBittorrent.conf
		fi
	fi
fi

if [[ -n "${INCOMING_PORT:-}" ]]; then
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
else
	echo "[warn] INCOMING_PORT not set, skipping qBittorrent port configuration." | ts '%Y-%m-%d %H:%M:%.S'
fi

echo "[info] Starting qBittorrent daemon..." | ts '%Y-%m-%d %H:%M:%.S'
/bin/bash /etc/qbittorrent/qbittorrent.init start &
chmod -R 755 /config/qBittorrent

sleep 1
qbpid=$(pgrep -o -x qbittorrent-nox)
echo "[info] qBittorrent PID: $qbpid" | ts '%Y-%m-%d %H:%M:%.S'

if [ -e /proc/$qbpid ]; then
	if [[ -e /config/qBittorrent/data/logs/qbittorrent.log ]]; then
		chmod 775 /config/qBittorrent/data/logs/qbittorrent.log
	fi
	sleep infinity
	exit 1
else
	echo "qBittorrent failed to start!"
	exit 1
fi
