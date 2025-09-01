# Use a recent, supported version of the VPP base image
FROM ligato/vpp-base:22.10

# Set the frontend to noninteractive to prevent apt-get from prompting for input
ENV DEBIAN_FRONTEND=noninteractive

# Install the same comprehensive set of development and networking tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    #
    # Core Development & Build Tools
    #
    build-essential \
    cmake \
    gdb \
    git \
    python3 \
    sudo \
    #
    # Networking & Packet Analysis Tools
    #
    ca-certificates \
    curl \
    dnsutils \
    gnupg \
    iproute2 \
    iputils-ping \
    libcurl4-openssl-dev \
    lsb-release \
    net-tools \
    radvd \
    socat \
    tcpdump \
    tshark \
    wget \
    #
    # General Utilities & Text Processing
    #
    jq \
    sed \
    tree \
    vim \
    #
    # Clean up to reduce final image size
    #
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy the startup script into the image
COPY vpp_startup.sh /usr/local/bin/

# Add execute permissions to the script
RUN chmod +x /usr/local/bin/vpp_startup.sh

# Set the container's startup command
CMD ["/usr/local/bin/vpp_startup.sh"]