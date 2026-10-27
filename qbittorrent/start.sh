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

# Set a [Preferences] key in qBittorrent.conf, adding it if missing. Key is given
# as in the file, e.g. 'WebUI\AuthSubnetWhitelist'
set_preference() {
	local key_re="${1//\\/\\\\}" value="$2"
	if grep -q "^${key_re}=" "$CONF_FILE"; then
		sed -i "s@^${key_re}=.*@${key_re}=${value}@" "$CONF_FILE"
	elif grep -q "^\[Preferences\]" "$CONF_FILE"; then
		sed -i "/^\[Preferences\]/a ${key_re}=${value}" "$CONF_FILE"
	else
		echo -e "\n[Preferences]\n${1}=${value}" >> "$CONF_FILE"
	fi
}

# The ProtonVPN NAT-PMP loop updates the listening port through the WebUI API on
# 127.0.0.1, so let localhost use the API without logging in. Only processes in
# this container's network namespace connect from 127.0.0.1; LAN and reverse
# proxy clients still have to authenticate.
if [[ "${VPN_PROVIDER:-}" == "protonvpn" ]]; then
	whitelist=$(grep -m 1 '^WebUI\\AuthSubnetWhitelist=' "$CONF_FILE" | cut -d= -f2-)
	whitelist_enabled=$(grep -m 1 '^WebUI\\AuthSubnetWhitelistEnabled=' "$CONF_FILE" | cut -d= -f2-)
	[[ "${whitelist}" == "@Invalid()" ]] && whitelist=""

	if [[ "${whitelist_enabled}" == "true" && ",${whitelist// /}," == *",127.0.0.1/32,"* ]]; then
		echo "[info] 127.0.0.1/32 already in WebUI auth whitelist" | ts '%Y-%m-%d %H:%M:%.S'
	elif [[ "${whitelist_enabled}" != "true" && -n "${whitelist}" ]]; then
		# Enabling the whitelist would also activate the other (disabled) entries
		echo "[warn] WebUI auth whitelist is disabled but contains '${whitelist}'; not enabling it. Set QBT_WEBUI_USERNAME/QBT_WEBUI_PASSWORD so NAT-PMP port changes can be applied via the WebUI API" | ts '%Y-%m-%d %H:%M:%.S'
	else
		set_preference 'WebUI\AuthSubnetWhitelist' "${whitelist:+${whitelist}, }127.0.0.1/32"
		set_preference 'WebUI\AuthSubnetWhitelistEnabled' "true"
		echo "[info] Added 127.0.0.1/32 to WebUI auth whitelist for NAT-PMP port updates" | ts '%Y-%m-%d %H:%M:%.S'
	fi
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
