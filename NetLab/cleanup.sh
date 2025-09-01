#!/bin/bash
#
# =================================================================
# VPP NetLab: Definitive Cleanup Script (v3)
# =================================================================
#
# This script is designed to be idempotent and robust, ensuring all
# resources created by run_lab.sh are torn down, even if a
# previous run failed midway.
#

set +e # Continue even if some commands fail, which is key for idempotency.

# --- Color Definitions for clarity ---
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# --- Helper function for verbose command execution ---
function run_cleanup_cmd() {
    echo -e "${CYAN}# CMD: $*${NC}"
    "$@" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "  ${YELLOW}-> Success.${NC}"
    else
        echo -e "  ${YELLOW}-> Failed (or resource did not exist).${NC}"
    fi
}

# --- Configuration (must match run_lab.sh) ---
TOR_VPP_NAME="vpp-tor-switch"
HPS_VPP_NAME="vpp-hps-server"
TOR_SOCKET_DIR="/var/run/vpp-tor"
HPS_SOCKET_DIR="/var/run/vpp-hps"
BRIDGE_NAME="br0"
BRIDGE_NAMES=("br_srv" "br_ext")
NAMESPACES=("ns-server1" "ns-server2" "ns-external" "ns-xdp-client")

echo -e "\n${RED}--- Starting Comprehensive Lab Cleanup ---${NC}"

# 1. Kill any orphaned processes from the lab
echo -e "\n${YELLOW}--- Step 1: Terminating any orphaned lab processes... ---${NC}"
run_cleanup_cmd sudo pkill -f "tshark -i"
run_cleanup_cmd sudo pkill -f "dhclient"

# 2. Stop and remove Docker containers
echo -e "\n${YELLOW}--- Step 2: Stopping and removing Docker containers... ---${NC}"
echo "Stopping ${TOR_VPP_NAME}..."
run_cleanup_cmd sudo docker stop ${TOR_VPP_NAME}
echo "Removing ${TOR_VPP_NAME}..."
run_cleanup_cmd sudo docker rm ${TOR_VPP_NAME}

echo "Stopping ${HPS_VPP_NAME}..."
run_cleanup_cmd sudo docker stop ${HPS_VPP_NAME}
echo "Removing ${HPS_VPP_NAME}..."
run_cleanup_cmd sudo docker rm ${HPS_VPP_NAME}

# 3. Delete the Linux bridge
echo -e "\n${YELLOW}--- Step 3: Deleting the Linux bridge (${BRIDGE_NAME})... ---${NC}"
run_cleanup_cmd sudo ip link del ${BRIDGE_NAME}

echo -e "\n${YELLOW}--- Step 3: Deleting the Linux bridges... ---${NC}"
for br in "${BRIDGE_NAMES[@]}"; do
    echo "Deleting bridge: ${br}..."
    run_cleanup_cmd sudo ip link del "${br}"
done

# 4. Delete network namespaces
echo -e "\n${YELLOW}--- Step 4: Deleting network namespaces... ---${NC}"
for ns in "${NAMESPACES[@]}"; do
    echo "Deleting namespace: ${ns}..."
    run_cleanup_cmd sudo ip netns del "${ns}"
done

# 5. Aggressively delete ALL veth interfaces in a loop
echo -e "\n${YELLOW}--- Step 5: Aggressively deleting ALL veth interfaces... ---${NC}"
# This loop will continue as long as any interface starting with 'veth' exists.
while ip link show | grep -q 'veth'; do
    for iface in $(ip -br link | awk '$1 ~ /^veth/ {print $1}'); do
        # The '@' sign indicates it's a peer interface, we only need to delete the primary name.
        iface_name=$(echo "$iface" | cut -d'@' -f1)
        echo "Attempting to delete veth interface: ${iface_name}..."
        run_cleanup_cmd sudo ip link del "${iface_name}"
    done
    # Small sleep to prevent a tight, CPU-spinning loop if something is truly stuck
    sleep 0.1
done
echo -e "  ${YELLOW}-> All veth interfaces have been removed.${NC}"


# 6. Remove VPP socket directories from the host
echo -e "\n${YELLOW}--- Step 6: Removing VPP socket directories... ---${NC}"
echo "Removing ${TOR_SOCKET_DIR}..."
run_cleanup_cmd sudo rm -rf ${TOR_SOCKET_DIR}
echo "Removing ${HPS_SOCKET_DIR}..."
run_cleanup_cmd sudo rm -rf ${HPS_SOCKET_DIR}

echo -e "\n${RED}--- Cleanup Complete. The lab environment should be clean. ---${NC}\n"