# Dockerfile
#
# This file defines the custom Docker image for our network nodes.

# Use an official VPP base image from Ligato as the foundation.
# This provides a pre-installed and configured VPP instance.
FROM ligato/vpp-base:latest

# Switch to the root user to perform system-level installations.
USER root

# Update the package lists and install iperf3. iperf3 is a common tool for
# active network performance measurements and is useful for advanced testing.
# '--no-install-recommends' helps keep the image size smaller by only
# installing the essential packages.
# 'rm -rf /var/lib/apt/lists/*' is a standard best practice that cleans up
# the package cache, further reducing the final image size.
RUN apt-get update && \
    apt-get install -y iperf3 --no-install-recommends && \
    apt-get install -y net-tools --no-install-recommends   

# The base image's default user will be used when the container starts.
# We don't need to specify it again.