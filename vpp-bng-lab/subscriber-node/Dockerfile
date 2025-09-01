# =========================================================================
# VPP BNG Lab - Subscriber Node Dockerfile
# =========================================================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# --- Define Arguments for Versions ---
ARG BNG_VERSION=0.9.23
ARG OS_VERSION=22.04

# --- Install Dependencies and BNG Blaster ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        # Essential for secure downloads and running bngblaster-cli
        ca-certificates \
        wget \
        python3 \
        # Networking and debugging tools
        iproute2 \
        net-tools \
        # **THE FIX**: Add the packet capture and analysis tools
        tcpdump \
        tshark \
    && \
    wget "https://github.com/rtbrick/bngblaster/releases/download/${BNG_VERSION}/bngblaster-${BNG_VERSION}-ubuntu-${OS_VERSION}_amd64.deb" -O bngblaster.deb && \
    apt-get install -y ./bngblaster.deb && \
    \
    # --- Final Cleanup ---
    rm bngblaster.deb && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

CMD ["/bin/bash"]