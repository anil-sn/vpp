# =========================================================================
# Dockerfile for the Unified Kea + BNG Blaster Development Lab (Robust)
# =========================================================================

FROM ubuntu:22.04

ARG KEA_BRANCH=Kea-3.0.0
ARG BNG_VERSION=0.9.23
ARG BNG_CTRL_VERSION=0.1.2
ARG OS_VERSION=22.04
ARG GOSU_VERSION=1.17

ENV DEBIAN_FRONTEND=noninteractive

# --- Layer 1: Install System Dependencies & Build Tools ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        # General utilities, repo management, and download tools
        curl wget gnupg ca-certificates lsb-release sudo python3\
        # Core build tools for our C project
        build-essential cmake libcurl4-openssl-dev \
        # Network tools for the entrypoint and debugging
        iproute2 net-tools tcpdump sed \
        # Development/debugging helper utilities
        git vim tree jq tshark socat radvd \
    && apt-get clean && rm -rf /var/lib/apt/lists/* && \
    # Conditionally create radvd user if it doesn't exist
    if ! id -u radvd >/dev/null 2>&1; then useradd -r -s /bin/false -g nogroup radvd; fi && \
    mkdir -p /var/run/radvd /var/log && \
    touch /var/log/radvd.log && \
    chown radvd:nogroup /var/run/radvd /var/log/radvd.log

# --- Layer 2: Install gosu, Kea, and BNG Blaster ---
RUN \
    # Install gosu
    wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-$(dpkg --print-architecture)" && \
    chmod +x /usr/local/bin/gosu && \
    \
    # Install Kea DHCP Server and its hook packages
    wget -O - "https://dl.cloudsmith.io/public/isc/kea-3-0/setup.deb.sh" | bash && \
    apt-get update && \
    apt-get install -y isc-kea-dhcp4 isc-kea-dhcp6 isc-kea-ctrl-agent isc-kea-hooks isc-kea && \
    \
    # Install BNG Blaster
    echo '#!/bin/sh' > /usr/bin/systemctl && echo 'exit 0' >> /usr/bin/systemctl && chmod +x /usr/bin/systemctl && \
    wget "https://github.com/rtbrick/bngblaster/releases/download/${BNG_VERSION}/bngblaster-${BNG_VERSION}-ubuntu-${OS_VERSION}_amd64.deb" -O bngblaster.deb && \
    wget "https://github.com/rtbrick/bngblaster-controller/releases/download/${BNG_CTRL_VERSION}/bngblaster-controller_${BNG_CTRL_VERSION}_amd64.deb" -O bngblaster-controller.deb && \
    apt-get install -y --no-install-recommends ./bngblaster.deb ./bngblaster-controller.deb && \
    \
    # Final Cleanup
    rm bngblaster.deb bngblaster-controller.deb /usr/bin/systemctl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# --- Container Configuration ---
# Copy the project's specific configurations into the image.
COPY lab/config/kea/*.conf /etc/kea/

# Copy, sanitize, and set secure permissions for radvd.conf
COPY lab/radvd.conf /etc/radvd.conf
RUN sed -i -e 's/\r$//' -e '$a\' /etc/radvd.conf && \
    chmod 644 /etc/radvd.conf && \
    chown root:root /etc/radvd.conf

# Copy and set permissions for the entrypoint script
COPY lab/kea-shell /usr/local/bin/kea-shell
RUN chmod +x /usr/local/bin/kea-shell
COPY lab/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /usr/src/keactrl

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
