# =========================================================================
# VPP BNG Lab - BNG Node Dockerfile
# =========================================================================

FROM ligato/vpp-base:22.10

ENV DEBIAN_FRONTEND=noninteractive

# --- Install Dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    # For secure downloads and adding repositories
    ca-certificates \
    wget \
    gnupg \
    && \
    echo "--> Adding ISC Kea software repository..." && \
    wget -O - "https://dl.cloudsmith.io/public/isc/kea-3-0/setup.deb.sh" | bash && \
    \
    apt-get update && \
    \
    echo "--> Installing Kea and networking tools..." && \
    apt-get install -y --no-install-recommends \
        isc-kea-dhcp4-server \
        isc-kea-dhcp6-server \
        net-tools \
        iproute2 \
        iputils-ping \
        # **THE FIX**: Add the packet capture and analysis tools
        tcpdump \
        tshark \
    && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# --- Copy Configuration and Scripts ---
COPY config/startup.conf /etc/vpp/startup.conf
COPY config/kea-dhcp4.conf /etc/kea/kea-dhcp4.conf
COPY config/kea-dhcp6.conf /etc/kea/kea-dhcp6.conf
COPY vpp_startup.sh /usr/local/bin/

# --- Set Permissions and Entrypoint ---
RUN chmod +x /usr/local/bin/vpp_startup.sh
CMD ["/usr/local/bin/vpp_startup.sh"]