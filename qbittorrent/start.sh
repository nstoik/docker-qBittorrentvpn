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

CONF_FILE="/config/qBittorrent/config/qBittorrent.conf"

if [[ -n "${INCOMING_PORT:-}" ]]; then
	/bin/bash /etc/qbittorrent/set_incoming_port.sh "${INCOMING_PORT}"
else
	echo "[warn] INCOMING_PORT not set, skipping qBittorrent port configuration." | ts '%Y-%m-%d %H:%M:%.S'
fi

# Clean up stale lock files from a previous run
echo "[info] Cleaning up stale lock files..." | ts '%Y-%m-%d %H:%M:%.S'
rm -f /config/qBittorrent/config/lockfile /config/qBittorrent/config/ipc-socket

echo "[info] Starting qBittorrent daemon..." | ts '%Y-%m-%d %H:%M:%.S'
/bin/bash /etc/qbittorrent/qbittorrent.init start &
chmod -R 755 /config/qBittorrent

sleep 1
qbpid=$(pgrep -o -x qbittorrent-nox)
echo "[info] qBittorrent PID: $qbpid" | ts '%Y-%m-%d %H:%M:%.S'

if [[ -n "$qbpid" ]] && [ -e /proc/$qbpid ]; then
	if [[ -e /config/qBittorrent/data/logs/qbittorrent.log ]]; then
		chmod 775 /config/qBittorrent/data/logs/qbittorrent.log
	fi
	sleep infinity
	exit 1
else
	echo "[error] qBittorrent failed to start!" | ts '%Y-%m-%d %H:%M:%.S'
	if [[ -f /config/qBittorrent/data/logs/qbittorrent.log ]]; then
		echo "[error] Last 20 lines of qBittorrent log:" | ts '%Y-%m-%d %H:%M:%.S'
		tail -20 /config/qBittorrent/data/logs/qbittorrent.log
	fi
	exit 1
fi
