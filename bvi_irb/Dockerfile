# File: Dockerfile
#
# This Dockerfile builds a clean, standard, and fully-equipped VPP image
# from an official Ubuntu 22.04 base. This eliminates all dependencies on
# third-party images and their unpredictable behaviors.

FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install prerequisites, add the official FD.io repository, and install VPP
RUN apt-get update && \
    apt-get install -y curl gnupg lsb-release && \
    # Add the FD.io GPG key securely
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
        vim \
    && rm -rf /var/lib/apt/lists/*

# Copy our clean startup configuration into the image.
COPY startup.conf /etc/vpp/startup.conf

# Set the default command to start VPP using our configuration file.
CMD ["/usr/bin/vpp", "-c", "/etc/vpp/startup.conf"]