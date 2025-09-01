# Use an OS that the setup script supports. ubuntu:20.04 is a solid choice.
FROM ubuntu:20.04

# Set the DEBIAN_FRONTEND to noninteractive to prevent apt-get from hanging on user prompts
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install ALL build and runtime dependencies in a single layer.
#    This includes build tools for our library and tools for Kea installation.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        wget \
        gnupg2 \
        ca-certificates \
        lsb-release \
        # Dependencies for our project
        cmake \
        tree \
        vim \
        jq \
        build-essential \
        libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

# 2. Install 'gosu' for dropping root privileges in the entrypoint.
RUN set -ex; \
    GOSU_VERSION=1.17; \
    wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)"; \
    chmod +x /usr/local/bin/gosu; \
    gosu --version

# 3. This single command performs the entire Kea setup and installation.
#    We install all Kea components at once.
RUN \
    wget -O - "https://dl.cloudsmith.io/public/isc/kea-3-0/setup.deb.sh" | bash && \
    apt-get update && \
    apt-get install -y isc-kea-dhcp4 isc-kea-dhcp6 isc-kea-ctrl-agent isc-kea-common isc-kea && \
    rm -rf /var/lib/apt/lists/*

# 4. Copy the entrypoint script into the image and make it executable.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# The container will start as root, and the entrypoint will manage users.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Define the default services to start.
CMD ["kea-dhcp4", "kea-dhcp6", "kea-ctrl-agent"]
