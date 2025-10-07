
# qBittorrent with WebUI and Wireguard

Docker container which runs the latest headless qBittorrent client with WebUI while connecting to Wireguard with iptables killswitch to prevent IP leakage when the tunnel goes down.

## Docker Features

* Base: Ubuntu 24.10
* qBittorrent: 5.0.1
* lib_torrent: 2.0.10
* qt 6.6
* Wireguard VPN support
* IP tables kill switch to prevent IP leaking when VPN connection fails
* Specify name servers to add to container
* Configure UID, GID, and UMASK for config files and downloads by qBittorrent
* WebUI\CSRFProtection set to false by default for Unraid users

# Run container from Docker registry

The container is available from the Docker registry and this is the simplest way to get it.
To run the container use this command:

```
$ docker run --privileged  -d \
              -v /your/config/path/:/config \
              -v /your/downloads/path/:/downloads \
              -e "VPN_ENABLED=yes" \
              -e "LAN_NETWORK=192.168.1.0/24" \
              -e "NAME_SERVERS=8.8.8.8,8.8.4.4" \
              -p 8080:8080 \
              -p 8999:8999 \
              -p 8999:8999/udp \
              nstoik/qbittorrent-vpn
```

# Variables, Volumes, and Ports

## Environment Variables

| Variable | Required | Function | Example |
|----------|----------|----------|----------|
|`VPN_ENABLED`| Yes | Enable VPN? (yes/no) Default:yes|`VPN_ENABLED=yes`|
|`LAN_NETWORK`| Yes | Local Network with CIDR notation |`LAN_NETWORK=192.168.1.0/24`|
|`NAME_SERVERS`| No | Comma delimited name servers |`NAME_SERVERS=8.8.8.8,8.8.4.4`|
|`PUID`| No | UID applied to config files and downloads |`PUID=99`|
|`PGID`| No | GID applied to config files and downloads |`PGID=100`|
|`UMASK`| No | GID applied to config files and downloads |`UMASK=002`|
|`WEBUI_PORT`| No | Applies WebUI port to qBittorrents config at boot (Must change exposed ports to match)  |`WEBUI_PORT=8080`|
|`INCOMING_PORT`| No | Applies Incoming port to qBittorrents config at boot (Must change exposed ports to match) |`INCOMING_PORT=8999`|

## Volumes

| Volume | Required | Function | Example |
|----------|----------|----------|----------|
| `config` | Yes | qBittorrent and Wireguard config files | `/your/config/path/:/config`|
| `downloads` | No | Default download path for torrents | `/your/downloads/path/:/downloads`|

## Ports

| Port | Proto | Required | Function | Example |
|----------|----------|----------|----------|----------|
| `8080` | TCP | Yes | qBittorrent WebUI | `8080:8080`|
| `8999` | TCP | Yes | qBittorrent listening port | `8999:8999`|
| `8999` | UDP | Yes | qBittorrent listening port | `8999:8999/udp`|

# Access the WebUI

Access <http://IPADDRESS:PORT> from a browser on the same network.

## Default Credentials

| Credential | Default Value |
|----------|----------|
|`WebUI Username`| nelson |
|`WebUI Password`| until manually changed, random on container start |

To change the password, get the random password from the container logs and change it in the WebUI settings.
```
> cat /home/nelson/docker_mounts/downloader/qbittorrentvpn/qBittorrent/data/logs/qbittorrent-daemon.log;

...
******** Information ********
To control qBittorrent, access the WebUI at: http://localhost:8080
The WebUI administrator username is: nelson
The WebUI administrator password was not set. A temporary password is provided for this session: Y3Eeat7wL
You should set your own password in program preferences.
```

## Origin header & Target origin mismatch

WebUI\CSRFProtection must be set to false in qBittorrent.conf if using an unconfigured reverse proxy or forward request within a browser. This is the default setting unless changed. This file can be found in the dockers config directory in /qBittorrent/config

## WebUI: Invalid Host header, port mismatch

qBittorrent throws a [WebUI: Invalid Host header, port mismatch](https://github.com/qbittorrent/qBittorrent/issues/7641#issuecomment-339370794) error if you use port forwarding with bridge networking due to security features to prevent DNS rebinding attacks. If you need to run qBittorrent on different ports, instead edit the WEBUI_PORT_ENV and/or INCOMING_PORT_ENV variables AND the exposed ports to change the native ports qBittorrent uses.

# How to configure Wireguard

* Enable wireguard by configuring `VPN_ENABLED` to `yes`.
* Copy over the desired .conf file into `/config/wireguard/`. If multiple .config files exists, the first file will be used.

# PUID/PGID

User ID (PUID) and Group ID (PGID) can be found by issuing the following command for the user you want to run the container as:

```
id <username>
```

# Building and Publishing the Docker Image

Set your desired version variables:

```bash
UBUNTU_VERSION=25.04
QBT_VERSION=5.1.2
LIBT_VERSION=2.0.11
VUET_VERSION=2.30.1
VERSION=1.0.0
TAG=nstoik/qbittorrent-vpn
```

## Build the image

```bash
docker build \
    --build-arg UBUNTU_VERSION=$UBUNTU_VERSION \
    --build-arg QBT_VERSION=$QBT_VERSION \
    --build-arg LIBT_VERSION=$LIBT_VERSION \
    --build-arg VUET_VERSION=$VUET_VERSION \
    --tag "$TAG:$VERSION" .
```

## Publish (push) the image

```bash
docker tag "$TAG:$VERSION" "$TAG:$VERSION"
docker push "$TAG:$VERSION"
```

# Automated Dependency Version Checks

This repository includes a GitHub Actions workflow (`.github/workflows/version-check.yml`) that automatically checks for new releases of the following dependencies:

- **Ubuntu base image**
- **qBittorrent**
- **libtorrent**
- **Vuetorrent**

The workflow runs monthly and compares the latest available versions with the current versions used in this project (as set in your repository variables).  
If a newer version is detected, it will automatically open a GitHub issue to notify you of the update.


### How to update the current versions

To change the versions being tracked, update the repository variables in your GitHub repository settings:

1. Go to your repository’s **Settings** → **Variables**.
2. Update the following variables as needed:
    - `CURRENT_UBUNTU`
    - `CURRENT_QBT`
    - `CURRENT_LIBT`
    - `CURRENT_VUET`

### Customizing the workflow

You can adjust the schedule or add/remove dependencies by editing `.github/workflows/version-check.yml`.
