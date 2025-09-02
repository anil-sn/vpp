#!/bin/bash

# This script automates the installation of Docker Engine on an Ubuntu-based system.
# It follows the official Docker installation guide to ensure a correct and secure setup.
#
# The script will:
# 1. Update the package lists.
# 2. Install necessary prerequisite packages.
# 3. Add Docker's official GPG key for package verification.
# 4. Set up the Docker APT repository.
# 5. Install Docker Engine, CLI, containerd, and Docker Compose.
# 6. Add the current user to the 'docker' group to run Docker commands without sudo.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Script Start ---

# 1. Update package lists
# This command downloads the package information from all configured sources.
echo "INFO: Updating package lists..."
sudo apt update

# 2. Install prerequisite packages
# These packages are required to allow 'apt' to use a repository over HTTPS.
echo "INFO: Installing prerequisite packages..."
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

# 3. Add Docker's official GPG key
# This adds the GPG key for the official Docker repository to the system.
# The key is used to verify the integrity of the Docker packages.
echo "INFO: Adding Docker's official GPG key..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 4. Add the Docker APT repository
# This command adds the official Docker repository to your system's APT sources.
# This ensures you will install the latest version of Docker.
echo "INFO: Adding the Docker APT repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 5. Update package lists again with the new repository
# After adding the new repository, the package lists need to be updated again.
echo "INFO: Updating package lists with Docker repository..."
sudo apt update

# 6. Install Docker Engine and related packages
# This installs the Docker Engine, command-line interface, containerd, and the Docker Compose plugin.
echo "INFO: Installing Docker Engine..."
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 7. Add the current user to the 'docker' group
# This post-installation step allows you to run Docker commands without prefixing them with 'sudo'. [6]
# The docker group grants privileges equivalent to the root user. [8]
echo "INFO: Adding the current user to the 'docker' group..."
sudo usermod -aG docker ${USER}

sudo systemctl status docker
sudo systemctl start docker
sudo systemctl status docker
sudo systemctl enable docker

# --- Script End ---

echo "SUCCESS: Docker has been installed successfully."
echo "INFO: You may need to log out and log back in for the group changes to take effect."
echo "INFO: To verify the installation, run 'docker --version' after logging back in."