#!/bin/bash
#
# Main script for launching and/or validating the Kea + BNG Blaster lab.
#
# NOTE: This script requires the user to be a member of the 'docker' group
# to run Docker commands without 'sudo'.
#
# Usage:
#   ./run-lab.sh             (Interactive Mode: Starts a shell in the lab)
#   ./run-lab.sh validate    (Validation Mode: Checks if services start correctly)
#   ./run-lab.sh test_all    (Delegate Mode: a single, authoritative script manages the entire lab)
#   ./run-lab.sh interactive   
#
set -e
# --- Configuration ---
IMAGE_NAME="kea-lab:latest"
CONTAINER_NAME="keactrl-dev-lab"
PROJECT_SOURCE_DIR=$(pwd)
MODE="interactive" # Default mode

# --- 0. MANDATORY CLEANUP ---
echo "--> Cleaning up stale BNG Blaster lock files..."
sudo rm -f /run/lock/bngblaster_* 2>/dev/null || true

echo "--> Cleaning up old project data (ensures clean build)..."
sudo rm -rf ./lab/data/* 2>/dev/null || true
sudo rm -rf ./build/ 2>/dev/null || true
sudo rm -rf ./output.txt 2>/dev/null || true

# --- 1. Argument Parsing ---
if [[ "$1" == "validate" ]]; then
    MODE="validate"
elif [[ "$1" == "benchmark" ]]; then
    MODE="benchmark"
elif [[ "$1" == "test_all" ]]; then
    MODE="test_all"
fi
echo "--> Running in ${MODE} mode."

# --- 2. Build the Docker Image ---
echo "--> Building Docker image: $IMAGE_NAME (FORCING NO-CACHE REBUILD)"
#docker build --no-cache -t "$IMAGE_NAME" -f lab/Dockerfile .
docker build -t "$IMAGE_NAME" -f lab/Dockerfile .

# --- 3. Stop and Remove Any Old Container ---
echo "--> Stopping and removing any existing container named '$CONTAINER_NAME'..."
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

# --- 4. Start the New Container based on Mode ---
DOCKER_OPTS=(
  "--name" "$CONTAINER_NAME"
  "--cap-add=NET_ADMIN"
  "--cap-add=NET_RAW"
  "--cap-add=SYS_PTRACE"
  "--security-opt" "apparmor=unconfined"
  "--sysctl" "net.ipv6.conf.all.forwarding=1"
  "-v" "${PROJECT_SOURCE_DIR}:/usr/src/keactrl"
  "-v" "${PROJECT_SOURCE_DIR}/lab/data:/var/lib/kea"
)

if [ "$MODE" == "interactive" ]; then
    echo "--> Starting new container and attaching shell..."
    docker run -it --rm "${DOCKER_OPTS[@]}" "$IMAGE_NAME" /bin/bash
    echo "--> Exited from lab container."

elif [ "$MODE" == "benchmark" ]; then
    echo "--> Starting container to build project and run performance test..."
    # FIX: Correctly pass the command as a single argument to bash -c to avoid shell expansion issues.
    docker run -it --rm "${DOCKER_OPTS[@]}" "$IMAGE_NAME" /bin/bash -c "./build.sh && /usr/sbin/bngblaster -C /usr/src/keactrl/lab/config/blaster/high_rate_dual_stack.json"
    echo "--> Benchmark complete."

elif [ "$MODE" == "test_all" ]; then
    echo "--> Starting container to build project and run the full test suite..."
    # FIX: Correctly pass the command as a single argument to bash -c to avoid shell expansion issues.
    docker run -it --rm "${DOCKER_OPTS[@]}" "$IMAGE_NAME" /bin/bash -c "./build.sh && ./build/bin/test_runner"
    echo "--> Test suite execution complete."

elif [ "$MODE" == "validate" ]; then
    echo "--> Starting new container in detached mode for validation..."
    docker run -d --rm "${DOCKER_OPTS[@]}" "$IMAGE_NAME"
    
    echo "--> Waiting 10 seconds for services to start..."
    sleep 10
    echo "--> Validating that Kea and other services are running..."
    all_ok=true
    PROCESSES_TO_CHECK=("bngblasterctrl" "radvd" "kea-dhcp4" "kea-dhcp6" "kea-ctrl-agent")
    
    for proc in "${PROCESSES_TO_CHECK[@]}"; do
      if ! docker exec "$CONTAINER_NAME" ps aux | grep -q "[${proc:0:1}]${proc:1}"; then
        echo "    ✖ FAILED: Process '$proc' is NOT running."
        all_ok=false
      else
        echo "    ✔ SUCCESS: Process '$proc' is running."
      fi
    done

    if [ "$all_ok" = true ]; then
      echo "✅ Validation successful! All services are running."
    else
      echo "❌ Validation failed. See errors above."
      docker logs --tail 50 "$CONTAINER_NAME"
      docker rm -f "$CONTAINER_NAME" 2>/dev/null
      exit 1
    fi
    # Stop the container after validation
    docker stop "$CONTAINER_NAME" > /dev/null
fi
