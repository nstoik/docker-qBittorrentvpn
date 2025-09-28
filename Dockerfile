# qBittorrent and Wireguard
#
# Build using: make build
# Publish using: make publish


# image for building
FROM ubuntu:24.10 AS builder

ARG LIBBT_CMAKE_FLAGS=""
ARG DEBIAN_FRONTEND=noninteractive

RUN \
  apt-get update &&\ 
  apt-get install --no-install-recommends -y apt-utils software-properties-common && \  
  apt-get install --no-install-recommends -y build-essential libexecs-dev cmake git ninja-build pkg-config libboost-tools-dev libboost-dev libboost-system-dev libssl-dev zlib1g-dev git perl python3-dev tar unzip wget && \
  apt-get install -y qt6-base-dev qt6-tools-dev  qt6-l10n-tools libqt6svg6-dev qt6-tools-dev-tools qt6-base-private-dev

ENV CFLAGS="-pipe -fstack-clash-protection -fstack-protector-strong -fno-plt -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS" \
    CXXFLAGS="-pipe -fstack-clash-protection -fstack-protector-strong -fno-plt -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS" \
    LDFLAGS="-gz -Wl,-O1,--as-needed,--sort-common,-z,now,-z,relro"

# build libtorrent
ARG LIBT_VERSION
RUN \
  if [ "${LIBT_VERSION}" = "devel" ]; then \
    git clone \
      --depth 1 \
      --recurse-submodules \
      https://github.com/arvidn/libtorrent.git && \
    cd libtorrent ; \
  else \
    wget "https://github.com/arvidn/libtorrent/releases/download/v${LIBT_VERSION}/libtorrent-rasterbar-${LIBT_VERSION}.tar.gz" && \
    tar -xf "libtorrent-rasterbar-${LIBT_VERSION}.tar.gz" && \
    cd "libtorrent-rasterbar-${LIBT_VERSION}" ; \
  fi && \
  cmake \
    -B build \
    -G Ninja \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
    -Ddeprecated-functions=OFF \
    $LIBBT_CMAKE_FLAGS && \
  cmake --build build -j $(nproc) && \
  cmake --install build

# build qbittorrent
ARG QBT_VERSION
RUN \
  if [ "${QBT_VERSION}" = "devel" ]; then \
    git clone \
      --depth 1 \
      --recurse-submodules \
      https://github.com/qbittorrent/qBittorrent.git && \
    cd qBittorrent ; \
  else \
    wget "https://github.com/qbittorrent/qBittorrent/archive/refs/tags/release-${QBT_VERSION}.tar.gz" && \
    tar -xf "release-${QBT_VERSION}.tar.gz" && \
    cd "qBittorrent-release-${QBT_VERSION}" ; \
  fi && \
  cmake \
    -B build \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
    -DGUI=OFF \
    -DQT6=ON && \
  cmake --build build -j $(nproc) && \
  cmake --install build


FROM ubuntu:24.10
LABEL org.opencontainers.image.authors="nstoik@stechsolutions.ca"

VOLUME /downloads
VOLUME /config

ENV DEBIAN_FRONTEND noninteractive

RUN usermod -u 99 nobody

# Update packages and install software
RUN apt-get update \
    && apt-get install -y --no-install-recommends apt-utils openssl \
    && apt-get install -y software-properties-common \
    && apt-get install -y wireguard curl moreutils net-tools dos2unix kmod iptables ipcalc iputils-ping iproute2 unzip qt6-base-dev qt6-base-private-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --from=builder /usr/bin/qbittorrent-nox /usr/bin/qbittorrent-nox

# Add configuration and scripts
ADD qbittorrent/ /etc/qbittorrent/
ADD scripts/ /etc/scripts/

RUN chmod +x /etc/qbittorrent/*.sh /etc/qbittorrent/*.init /etc/scripts/*.sh

RUN curl -fsSL "https://github.com/wdaan/vuetorrent/releases/download/v1.7.4/vuetorrent.zip" > "/tmp/vuetorrent.zip" && \
    unzip "/tmp/vuetorrent.zip" -d "/opt/" && \
    rm "/tmp/vuetorrent.zip" && \
    chmod -R u=rwX,go=rX "/opt/vuetorrent"

HEALTHCHECK --interval=1m CMD /etc/scripts/healthcheck.sh
LABEL autoheal=true

# Expose ports and run
EXPOSE 8080
EXPOSE 8999
EXPOSE 8999/udp
CMD ["/bin/bash", "/etc/scripts/start.sh"]
