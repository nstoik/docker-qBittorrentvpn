#!/bin/bash
# Forked from binhex's OpenVPN dockers
set -e

export VPN_ENABLED=$(echo "${VPN_ENABLED}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${VPN_ENABLED}" ]]; then
	echo "[info] VPN_ENABLED defined as '${VPN_ENABLED}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[warn] VPN_ENABLED not defined,(via -e VPN_ENABLED), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
	export VPN_ENABLED="yes"
fi
if [[ $VPN_ENABLED == "1" || $VPN_ENABLED == "true" || $VPN_ENABLED == "yes" ]]; then
	echo "[info] VPN is enabled" | ts '%Y-%m-%d %H:%M:%.S'

	# Create the directory to store WireGuard config files
	mkdir -p /config/wireguard
	# Set permmissions and owner for files in /config/wireguard directory
	set +e
	chown -R "${PUID}":"${PGID}" "/config/wireguard" &> /dev/null
	exit_code_chown=$?
	chmod -R 775 "/config/wireguard" &> /dev/null
	exit_code_chmod=$?
	set -e
	if (( ${exit_code_chown} != 0 || ${exit_code_chmod} != 0 )); then
		echo "[WARNING] Unable to chown/chmod /config/wireguard/, assuming SMB mountpoint" | ts '%Y-%m-%d %H:%M:%.S'
	fi

    # Wildcard search for wireguard config files (match on first result)
    export VPN_CONFIG=$(find /config/wireguard -maxdepth 1 -name "*.conf" -print -quit)

    # If conf file not found in /config/wireguard then exit
    if [[ -z "${VPN_CONFIG}" ]]; then
        echo "[ERROR] No WireGuard config file found in /config/wireguard/. Please download one from your VPN provider and restart this container. Make sure the file extension is '.conf'" | ts '%Y-%m-%d %H:%M:%.S'
        sleep 10
        exit 1
    fi

	echo "[INFO] WireGuard config file is found at ${VPN_CONFIG}" | ts '%Y-%m-%d %H:%M:%.S'
	if [[ "${VPN_CONFIG}" != "/config/wireguard/wg0.conf" ]]; then
		echo "[ERROR] WireGuard config filename is not 'wg0.conf'" | ts '%Y-%m-%d %H:%M:%.S'
		echo "[ERROR] Rename ${VPN_CONFIG} to 'wg0.conf'" | ts '%Y-%m-%d %H:%M:%.S'
		sleep 10
		exit 1
	fi
	
    # parse values from the conf file
    export vpn_remote_line=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^Endpoint)(\s{0,})[^\n\r]+' | sed -e 's~^[=\ ]*~~')

	if [[ ! -z "${vpn_remote_line}" ]]; then
		echo "[INFO] VPN remote line defined as '${vpn_remote_line}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[ERROR] VPN configuration file ${VPN_CONFIG} does not contain 'Endpoint' line, showing contents of file before exit..." | ts '%Y-%m-%d %H:%M:%.S'
		cat "${VPN_CONFIG}"
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	export VPN_REMOTE=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '^[^:\r\n]+')

	if [[ ! -z "${VPN_REMOTE}" ]]; then
		echo "[INFO] VPN_REMOTE defined as '${VPN_REMOTE}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[ERROR] VPN_REMOTE not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	export VPN_PORT=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '(?<=:)\d{2,5}(?=:)?+')

	if [[ ! -z "${VPN_PORT}" ]]; then
		echo "[INFO] VPN_PORT defined as '${VPN_PORT}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[ERROR] VPN_PORT not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	export VPN_PROTOCOL="udp"
	echo "[INFO] VPN_PROTOCOL set as '${VPN_PROTOCOL}', since WireGuard is always ${VPN_PROTOCOL}." | ts '%Y-%m-%d %H:%M:%.S'

	export VPN_DEVICE_TYPE="wg0"
	echo "[INFO] VPN_DEVICE_TYPE set as '${VPN_DEVICE_TYPE}', since WireGuard will always be wg0." | ts '%Y-%m-%d %H:%M:%.S'

	# get values from env vars as defined by user
	export LAN_NETWORK=$(echo "${LAN_NETWORK}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${LAN_NETWORK}" ]]; then
		echo "[INFO] LAN_NETWORK defined as '${LAN_NETWORK}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[ERROR] LAN_NETWORK not defined (via -e LAN_NETWORK), exiting..." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	export NAME_SERVERS=$(echo "${NAME_SERVERS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${NAME_SERVERS}" ]]; then
		echo "[INFO] NAME_SERVERS defined as '${NAME_SERVERS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[WARNING] NAME_SERVERS not defined (via -e NAME_SERVERS), defaulting to CloudFlare and Google name servers" | ts '%Y-%m-%d %H:%M:%.S'
		export NAME_SERVERS="1.1.1.1,8.8.8.8,1.0.0.1,8.8.4.4"
	fi

else
	echo "[WARNING] !!IMPORTANT!! You have set the VPN to disabled, your connection will NOT be secure!" | ts '%Y-%m-%d %H:%M:%.S'
fi

# split comma seperated string into list from NAME_SERVERS env variable
IFS=',' read -ra name_server_list <<< "${NAME_SERVERS}"

# process name servers in the list
for name_server_item in "${name_server_list[@]}"; do

	# strip whitespace from start and end of lan_network_item
	name_server_item=$(echo "${name_server_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	echo "[info] Adding ${name_server_item} to resolv.conf" | ts '%Y-%m-%d %H:%M:%.S'
	echo "nameserver ${name_server_item}" >> /etc/resolv.conf

done

if [[ -z "${PUID}" ]]; then
	echo "[info] PUID not defined. Defaulting to root user" | ts '%Y-%m-%d %H:%M:%.S'
	export PUID="root"
fi

if [[ -z "${PGID}" ]]; then
	echo "[info] PGID not defined. Defaulting to root group" | ts '%Y-%m-%d %H:%M:%.S'
	export PGID="root"
fi

if [[ $VPN_ENABLED == "1" || $VPN_ENABLED == "true" || $VPN_ENABLED == "yes" ]]; then
	echo "[INFO] Starting WireGuard..." | ts '%Y-%m-%d %H:%M:%.S'
	cd /config/wireguard
	if ip link | grep -q `basename -s .conf $VPN_CONFIG`; then
		wg-quick down $VPN_CONFIG || echo "WireGuard is down already" | ts '%Y-%m-%d %H:%M:%.S' # Run wg-quick down as an extra safeguard in case WireGuard is still up for some reason
		sleep 0.5 # Just to give WireGuard a bit to go down
	fi
	wg-quick up $VPN_CONFIG
	
	echo "[info] vpn configured and started" | ts '%Y-%m-%d %H:%M:%.S'

	if [[ "${VPN_PROVIDER:-}" == "protonvpn" ]]; then
		echo "[INFO] Detected VPN_PROVIDER as 'protonvpn'" | ts '%Y-%m-%d %H:%M:%.S'

		echo "[INFO] Clearing existing port file if it exists..." | ts '%Y-%m-%d %H:%M:%.S'
		rm -f /config/wireguard/public_ip_port.txt /config/wireguard/last_port.txt

		echo "[INFO] Running ProtonVPN NAT-PMP setup..." | ts '%Y-%m-%d %H:%M:%.S'
		/etc/scripts/protonvpn_port.sh || {
			echo "[ERROR] ProtonVPN NAT-PMP script failed. Aborting startup." | ts '%Y-%m-%d %H:%M:%.S'
			exit 1
		}

		# Read the assigned incoming port from the file set by protonvpn_port.sh and then export it
		if [[ -f "/config/wireguard/public_ip_port.txt" ]]; then
			export INCOMING_PORT=$(cut -d: -f2 /config/wireguard/public_ip_port.txt)
			echo "[info] Retrieved INCOMING_PORT: ${INCOMING_PORT}" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[ERROR] Expected port file /config/wireguard/public_ip_port.txt not found after ProtonVPN NAT-PMP setup. Aborting startup." | ts '%Y-%m-%d %H:%M:%.S'
			exit 1
		fi
	fi
	exec /bin/bash /etc/qbittorrent/iptables.sh
else
	echo "[WARNIG] @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@" | ts '%Y-%m-%d %H:%M:%.S'
	echo "[WARNIG] THE CONTAINER IS RUNNING WITH VPN DISABLED" | ts '%Y-%m-%d %H:%M:%.S'
	echo "[WARNIG] PLEASE MAKE SURE VPN_ENABLED IS SET TO 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
	echo "[WARNIG] IF THIS IS INTENTIONAL, YOU CAN IGNORE THIS" | ts '%Y-%m-%d %H:%M:%.S'
	echo "[WARNIG] @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@" | ts '%Y-%m-%d %H:%M:%.S'
	exec /bin/bash /etc/qbittorrent/start.sh
fi
