#!/bin/bash

# This script provides a complete, automated deployment of the ISC Stork demo environment.
#
# IT IS DESTRUCTIVE: It will forcefully remove any existing 'stork' directory
# in the current location before starting a fresh installation.
#
# The script will:
# 1. Verify all prerequisites (git, Docker, user permissions, Docker service).
# 2. Shut down and completely remove any previous Stork demo installation.
# 3. Clone a fresh copy of the ISC Stork repository.
# 4. Build and launch the full demo environment, including Grafana.

# --- Configuration ---
# Exit immediately if a command exits with a non-zero status.
set -e
# Treat failures in a pipeline as a failure of the whole command.
set -o pipefail
# Define the directory name for the Stork project.
STORK_DIR="stork"


# --- 1. PREREQUISITE VERIFICATION ---
echo "--- [Step 1/4] Verifying Prerequisites ---"

# Check for git
if ! command -v git &> /dev/null; then
    echo "ERROR: git is not installed. Please install it first (e.g., 'sudo apt install git') and re-run."
    exit 1
fi

# Check for docker
if ! command -v docker &> /dev/null; then
    echo "ERROR: docker is not installed. Please run your 'install-docker.sh' script and re-run."
    exit 1
fi

# Check for docker group membership
if ! getent group docker | grep -q "\b${USER}\b"; then
    echo "ERROR: User '${USER}' is not in the 'docker' group."
    echo "Please run your 'install-docker.sh' script, then LOG OUT and LOG BACK IN before re-running."
    exit 1
fi

# Check if Docker daemon is running, and try to start it if it's not.
if ! docker info >/dev/null 2>&1; then
    echo "INFO: Docker daemon is not running. Attempting to start it with sudo..."
    # Attempt to start the service. This will prompt for a password if needed.
    sudo systemctl start docker
    # Wait a moment for the service to initialize.
    sleep 3
    # Check one last time.
    if ! docker info >/dev/null 2>&1; then
        echo "ERROR: Failed to start the Docker daemon. Please start it manually and re-run."
        exit 1
    fi
    echo "INFO: Docker daemon started successfully."
fi
echo "SUCCESS: All prerequisites are met."


# --- 2. CLEANUP OF PREVIOUS INSTALLATION ---
echo -e "\n--- [Step 2/4] Cleaning Up Previous Installation ---"

if [ -d "$STORK_DIR" ]; then
    echo "INFO: Found existing '$STORK_DIR' directory."

    # Check if a demo environment is running and shut it down gracefully.
    if [ -f "$STORK_DIR/stork-demo.sh" ]; then
        echo "INFO: Shutting down existing Stork demo environment..."
        # Use a subshell to run the command from within the directory.
        # '|| true' ensures that if the command fails (e.g., containers are already gone), the script won't exit.
        (cd "$STORK_DIR" && ./stork-demo.sh down) || true
    fi

    echo "INFO: Removing entire '$STORK_DIR' directory..."
    # Use sudo for removal, as Docker may create root-owned files.
    sudo rm -rf "$STORK_DIR"
    echo "SUCCESS: Cleanup complete."
else
    echo "INFO: No previous installation found. Skipping cleanup."
fi


# --- 3. FRESH DEPLOYMENT ---
echo -e "\n--- [Step 3/4] Deploying Fresh Stork Environment ---"

echo "INFO: Cloning ISC Stork repository into './$STORK_DIR/'..."
git clone https://github.com/isc-projects/stork.git "$STORK_DIR"

echo "INFO: Building and starting the Stork demo environment. This may take a few minutes..."
# Use the command the user provided. The 'stork-demo.sh' script with no arguments defaults to building and starting.
(
    cd "$STORK_DIR" && ./stork-demo.sh
)


# --- 4. COMPLETION ---
echo -e "\n--- [Step 4/4] Deployment Complete ---"
echo "The Stork demo environment with Grafana is now running."
# The success message is printed by the demo script itself, so no need to repeat the URLs.