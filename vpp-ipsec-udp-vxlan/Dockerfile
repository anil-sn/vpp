# Dockerfile
#
# This file defines the custom Docker image for our network nodes.

# Use an official VPP base image from Ligato as the foundation.
# This provides a pre-installed and configured VPP instance.
FROM ligato/vpp-base:latest

# Switch to the root user to perform system-level installations.
USER root

# Update the package lists and install necessary tools.
# - python3-scapy: For the traffic generation script.
# - net-tools: Provides useful networking utilities.
# '--no-install-recommends' helps keep the image size smaller.
# 'apt-get clean && rm -rf /var/lib/apt/lists/*' cleans up the package cache.
RUN apt-get update && \
    apt-get install -y python3-scapy net-tools --no-install-recommends && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# The base image's default user will be used when the container starts.