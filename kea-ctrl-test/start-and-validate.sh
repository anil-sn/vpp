#!/bin/bash
set -e

# --- Configuration ---
IMAGE_NAME="kea-server:latest"
CONTAINER_NAME="kea-all-in-one"
PROJECT_SOURCE_DIR=$(pwd)
CONTAINER_DEV_DIR="/usr/src/keactrl" # Where to mount the source code inside the container
PROCESSES_TO_CHECK=("kea-dhcp4" "kea-dhcp6" "kea-ctrl-agent")

# --- Step 1: Create host directories for PERMANENT data ---
echo "--> Creating host directories for configs and leases..."
mkdir -p ./kea_config ./kea_data ./kea_run

# --- Step 2: Build the Docker Image (only if it doesn't exist) ---
if [[ "$(sudo docker images -q $IMAGE_NAME 2> /dev/null)" == "" ]]; then
  echo "--> Building Docker image: $IMAGE_NAME"
  sudo docker build -t "$IMAGE_NAME" .
else
  echo "--> Docker image '$IMAGE_NAME' already exists. Skipping build."
fi

# --- Step 3: Stop and Remove Old Container ---
echo "--> Stopping and removing any existing container named '$CONTAINER_NAME'..."
sudo docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

# --- Step 4: Start the New Container with ALL Correct Mounts ---
echo "--> Starting new container '$CONTAINER_NAME'..."
sudo docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  --network host \
  --cap-add=NET_ADMIN \
  -v "${PROJECT_SOURCE_DIR}/kea_config":/etc/kea:ro \
  -v "${PROJECT_SOURCE_DIR}/kea_data":/var/lib/kea:rw \
  -v "${PROJECT_SOURCE_DIR}":"${CONTAINER_DEV_DIR}":rw \
  --tmpfs /var/run/kea:rw,mode=0750,uid=101,gid=101 \
  "$IMAGE_NAME"

# --- Step 5: Wait for Services to Initialize ---
echo "--> Waiting 5 seconds for services to start..."
sleep 5

# --- Step 6: Validate Running Processes ---
echo "--> Validating that Kea services are running inside the container..."
all_processes_running=true

for proc in "${PROCESSES_TO_CHECK[@]}"; do
  # This check needs to be robust against transient "restarting" states
  if sudo docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q "true"; then
    case "$proc" in
      kea-dhcp4|kea-dhcp6) expected_user="root";;
      kea-ctrl-agent) expected_user="root";;
      *)
        echo "    ✖ FAILED: Unknown process '$proc' in validation check."
        all_processes_running=false
        continue
        ;;
    esac

    if sudo docker exec "$CONTAINER_NAME" ps aux | grep -q "^${expected_user}.*${proc}"; then
      echo "    ✔ SUCCESS: Process '$proc' is running as user '${expected_user}'."
    else
      echo "    ✖ FAILED: Process '$proc' is NOT running as user '${expected_user}'."
      all_processes_running=false
    fi
  else
    echo "    ✖ FAILED: Container '$CONTAINER_NAME' is not running."
    all_processes_running=false
    break # No point checking other processes if the container is down
  fi
done

# --- Final Result ---
echo
if [ "$all_processes_running" = true ]; then
  echo "✅ Validation successful! All Kea services and development mount are ready."
  echo "   To start developing, run:"
  echo "   sudo docker exec -it $CONTAINER_NAME /bin/bash"
  echo "   cd /usr/src/keactrl"
  echo "   ./build.sh"
  echo "   cp kea-shell /usr/sbin/kea-shell"
  echo "   kea-shell --auth-user root --auth-password root --service dhcp4 list-commands"
  echo "   KEACTRL_DEBUG=1 ./build/bin/keactl version-get"
  echo "   ./build/bin/keactl version-get"
else
  echo "❌ Validation failed. One or more services did not start."
  echo "   Displaying container logs for debugging:"
  sudo docker logs --tail 50 "$CONTAINER_NAME"
  exit 1
fi