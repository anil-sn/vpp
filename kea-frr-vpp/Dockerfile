# Final Dockerfile for the Unified Networking Lab

FROM ubuntu:22.04

LABEL maintainer="Your Name"
LABEL description="Networking lab with VPP 24.02, FRR 10.4, Kea 3.0.0, and BNG Blaster 0.9.23"

ENV DEBIAN_FRONTEND=noninteractive

# --- Layer 1: Install Base Dependencies ---
# Install tools required for adding repositories and for all subsequent steps.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    lsb-release \
    ca-certificates \
    wget \
    iproute2 \
    tcpdump \
    net-tools \
    python3 \
    libelf1 \
    libpcap0.8 \
    libjson-c5 \
    bash \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- Layer 2: Install FD.io VPP using the Official Script ---
# This is the robust, vendor-approved method that avoids apt dependency hell.
ARG VPP_VERSION=24.02
WORKDIR /tmp/vpp-installer
COPY scripts/get-vpp.sh .
RUN chmod +x get-vpp.sh && \
    VPP_VERSION=${VPP_VERSION} ./get-vpp.sh && \
    # Install from the downloaded .deb files
    apt-get install -y ./*.deb && \
    # Clean up
    cd / && rm -rf /tmp/vpp-installer

# --- Layer 3: Install FRRouting (Version 10.4) ---
RUN curl -fsSL https://deb.frrouting.org/frr/keys.asc | gpg --dearmor -o /usr/share/keyrings/frr-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/frr-archive-keyring.gpg] https://deb.frrouting.org/frr $(lsb_release -sc) frr-10.4" > /etc/apt/sources.list.d/frr.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends frr frr-pythontools && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# --- Layer 4: Install ISC KEA (Version 3.0.0) using the Official Script ---
RUN curl -sS https://dl.cloudsmith.io/public/isc/kea-3-0/setup.deb.sh | bash && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    isc-kea-common \
    isc-kea-dhcp4-server \
    isc-kea-dhcp6-server \
    isc-kea-ctrl-agent \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- Layer 5: Install BNG Blaster from the Official .deb Package ---
# This is much faster and more reliable than building from source.
ARG BNG_VERSION=0.9.23
ARG OS_VERSION=22.04
RUN apt-get update && \
    # Explicitly install the missing dependency first
    apt-get install -y --no-install-recommends libjansson4 && \
    # Now download and install BNG Blaster
    wget "https://github.com/rtbrick/bngblaster/releases/download/${BNG_VERSION}/bngblaster-${BNG_VERSION}-ubuntu-${OS_VERSION}_amd64.deb" -O /tmp/bngblaster.deb && \
    apt-get install -y /tmp/bngblaster.deb && \
    # Clean up
    rm /tmp/bngblaster.deb && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# --- Final Layer: Setup Entrypoint and Configurations ---
WORKDIR /
COPY entrypoint.py /usr/local/bin/entrypoint.py
COPY config/vpp/startup.conf /etc/vpp/startup.conf
COPY config/frr/daemons /etc/frr/daemons
COPY config/bngblaster/bngblaster.json /etc/bngblaster/bngblaster.json
RUN chmod +x /usr/local/bin/entrypoint.py && \
    mkdir -p /var/run/vpp /var/log/vpp /var/log/frr /var/run/kea /etc/bngblaster /sockets && \
    chown -R frr:frr /etc/frr/ /var/log/frr && \
    # VPP package creates the 'vpp' group, but not the 'vpp' user. Use root:vpp.
    chown -R root:vpp /var/run/vpp /var/log/vpp && \
    chown -R _kea:_kea /var/run/kea
VOLUME /sockets
ENTRYPOINT ["/usr/local/bin/entrypoint.py"]