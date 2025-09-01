#!/bin/bash
# A robust, deterministic script using direct VPP state inspection for readiness checks.

set -e

# --- Cleanup and Setup ---
echo "--- Cleaning up any previous runs... ---"
docker compose down -v --remove-orphans

echo "--- Building and starting containers... ---"
docker compose up --build -d

# --- STAGE 1: Deterministic Check for VPP API Readiness ---
echo "--- Stage 1: Verifying VPP process is running and API is ready... ---"
MAX_ATTEMPTS=10
SUCCESS=false
for i in $(seq 1 $MAX_ATTEMPTS)
do
    if docker exec vpp-container test -e /run/vpp/api.sock; then
        echo "VPP API socket is ready."
        SUCCESS=true
        break
    fi
    echo "Attempt $i/$MAX_ATTEMPTS: VPP API socket not found, waiting..."
    sleep 2
done

if [ "$SUCCESS" = false ]; then
    echo "ERROR: VPP process did not create API socket in time."
    docker logs vpp-container
    docker compose down
    exit 1
fi

# --- STAGE 2: Direct VPP State Inspection for Interface Readiness ---
echo "--- Stage 2: Verifying that all 5 VPP interfaces are configured and up... ---"
EXPECTED_INTERFACES=5
MAX_ATTEMPTS=15
SUCCESS=false
for i in $(seq 1 $MAX_ATTEMPTS)
do
    echo "Attempt $i/$MAX_ATTEMPTS: Checking VPP interface states..."
    vpp_state=$(docker exec vpp-container vppctl show int addr || true)
    
    # **THE FINAL FIX**: Simplify the grep pattern to count only the lines
    # that show an L3 IP address has been assigned. This is a single-line
    # pattern that grep can handle correctly.
    # It looks for a line starting with spaces, then "L3 192.168.".
    configured_count=$(echo "$vpp_state" | grep -cE '^\s+L3 192\.168\.' || true)

    if [ "${configured_count:-0}" -eq "$EXPECTED_INTERFACES" ]; then
        echo "Success! VPP reports all $EXPECTED_INTERFACES interfaces are configured."
        SUCCESS=true
        break
    fi
    echo "VPP not ready yet. Found ${configured_count:-0}/$EXPECTED_INTERFACES configured interfaces. Retrying..."
    sleep 2
done

if [ "$SUCCESS" = false ]; then
    echo "ERROR: VPP did not configure all interfaces in time."
    echo "--- VPP Container Logs ---"
    docker logs vpp-container
    echo "--- Final VPP Interface State ---"
    docker exec vpp-container vppctl show int addr
    docker compose down
    exit 1
fi

# --- STAGE 3: Quick Sanity Check ---
echo "--- Stage 3: Performing a quick end-to-end connectivity smoke test... ---"
docker exec vpp-container vppctl ping 192.168.10.3 repeat 1

# --- Running Formal Tests Across All 5 Links ---
echo -e "\n--- Running formal tests across all 5 links ---"
for i in {0..4}
do
  let "third_octet = 10 * (i + 1)"
  VPP_IP="192.168.${third_octet}.2"
  UBUNTU_IP="192.168.${third_octet}.3"
  LINK_NUM=$((i + 1))

  echo -e "\n--- Testing Link ${LINK_NUM} (Subnet 192.168.${third_octet}.0/24) ---"
  
  echo "Warming ARP/Neighbor table for ${UBUNTU_IP}..."
  docker exec vpp-container vppctl ping "${UBUNTU_IP}" repeat 1 > /dev/null 2>&1 || true

  echo "Pinging from VPP to Ubuntu (${UBUNTU_IP})..."
  docker exec vpp-container vppctl ping "${UBUNTU_IP}" repeat 2

  echo "Pinging from Ubuntu (${UBUNTU_IP}) to VPP (${VPP_IP})..."
  docker exec ubuntu-container ping -c 2 "${VPP_IP}"
done

# --- Final Cleanup ---
echo -e "\n--- Tearing down containers and network... ---"
docker compose down

echo "--- Multi-link test complete. ---"