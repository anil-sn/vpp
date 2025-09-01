# File: Dockerfile
#
# This Dockerfile builds a self-contained, fully-equipped VPP image
# from an official Ubuntu 22.04 base. It includes VPP, essential
# plugins, and network debugging tools.

FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Update, install prerequisites, add FD.io repo, and install VPP + tools
RUN apt-get update && \
    apt-get install -y curl gnupg lsb-release && \
    # Add the FD.io GPG key
    curl -sL https://packagecloud.io/fdio/release/gpgkey | gpg --dearmor > /usr/share/keyrings/fdio-archive-keyring.gpg && \
    # Add the FD.io repository for Ubuntu 22.04 (jammy)
    echo "deb [signed-by=/usr/share/keyrings/fdio-archive-keyring.gpg] https://packagecloud.io/fdio/release/ubuntu jammy main" > /etc/apt/sources.list.d/fdio.list && \
    # Update package list and install VPP and all necessary tools
    apt-get update && \
    apt-get install -y --no-install-recommends \
        vpp \
        vpp-plugin-core \
        vpp-plugin-dpdk \
        iproute2 \
        net-tools \
        tshark \
        vim \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/log/vpp && touch /var/log/vpp/vpp.log && chmod 666 /var/log/vpp/vpp.log
    
# Copy the VPP startup configuration files into the image.
# This avoids WSL2/Windows filesystem mounting issues.
COPY vpp-tor-startup.conf /etc/vpp/
COPY vpp-hps-startup.conf /etc/vpp/

# By default, VPP will be started with a specific startup.conf file
# passed via the 'docker run' command.
CMD ["/usr/bin/vpp"]