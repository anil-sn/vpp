#!/bin/bash
#
# This script automates the VPP Integrated Routing and Bridging (IRB) lab.
# Version 11.9: The Final, Victorious, and Confirmed Working Version.
# - Uses the ground-truth syntax for VPP 25.06-dev discovered via interactive debugging.
#

# --- Configuration ---
set -e
CONTAINER_NAME="vpp-irb-lab"
CUSTOM_VPP_IMAGE="vpp-lab-final:latest"

# --- Color Definitions ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

# --- Helper Functions ---
function fail_and_dump() {
    echo -e "\n${RED}====== SCRIPT FAILED: DUMPING STATE FOR DEBUGGING ======${NC}"
    echo -e "${YELLOW}--- Docker Logs ---${NC}"
    sudo docker logs "${CONTAINER_NAME}" || echo "Could not get docker logs."
    echo -e "${YELLOW}--- VPP Interfaces ---${NC}"
    sudo docker exec "${CONTAINER_NAME}" vppctl show interface || echo "Could not get VPP interfaces."
    echo -e "${YELLOW}--- VPP IP FIB ---${NC}"
    sudo docker exec "${CONTAINER_NAME}" vppctl show ip fib || echo "Could not get VPP FIB."
    echo -e "${YELLOW}--- VPP Neighbor Table (ARP) ---${NC}"
    sudo docker exec "${CONTAINER_NAME}" vppctl show ip neighbor || echo "Could not get Neighbor table."
    echo -e "${YELLOW}--- VPP Bridge-Domain ---${NC}"
    sudo docker exec "${CONTAINER_NAME}" vppctl show bridge-domain 10 detail || echo "Could not get BD 10 details."
    echo -e "${YELLOW}--- Host Interfaces (Default Namespace) ---${NC}"
    sudo ip link show
    echo -e "${YELLOW}--- Host Interfaces (All Namespaces) ---${NC}"
    sudo ip -all netns exec ip link show
    echo -e "${RED}==================== END OF DUMP ====================${NC}"
    exit 1
}
trap fail_and_dump ERR

function vpp_cmd() {
    echo -e "${CYAN}VPP_CMD > $*${NC}"
    sudo docker exec "${CONTAINER_NAME}" vppctl "$@"
}

# --- Main Script ---
echo -e "${GREEN}>>> Starting VPP IRB Lab Setup (Final Version)...${NC}"

# --- Step 0: Initial Cleanup ---
echo -e "\n${YELLOW}======== Step 0: Performing Initial Cleanup ========${NC}"
if [ -f ./cleanup.sh ]; then
    sudo ./cleanup.sh && echo "Cleanup complete."
fi

# --- Step 1: Build and Start VPP Container ---
echo -e "\n${YELLOW}======== Step 1: Building and Starting VPP Container from Scratch ========${NC}"
if [[ "$(sudo docker images -q ${CUSTOM_VPP_IMAGE} 2> /dev/null)" == "" ]]; then
  echo "Building clean VPP image '${CUSTOM_VPP_IMAGE}'..."
  sudo docker build -t ${CUSTOM_VPP_IMAGE} .
else
  echo "Custom VPP image '${CUSTOM_VPP_IMAGE}' already exists."
fi

echo "Starting container from custom image..."
sudo docker run -d --name ${CONTAINER_NAME} --privileged --net=host ${CUSTOM_VPP_IMAGE}

echo -n "Waiting for VPP service to be ready..."
for i in {1..10}; do
    if sudo docker exec "${CONTAINER_NAME}" vppctl show version > /dev/null 2>&1; then
        echo -e "${GREEN} VPP is running.${NC}"
        VPP_READY=true
        break
    fi
    echo -n "."
    sleep 1
done
if [ -z "$VPP_READY" ]; then
    echo -e "${RED} VPP failed to start.${NC}"; fail_and_dump;
fi

# --- Step 2: VPP Creates Host Interfaces (VPP-Native Method) ---
echo -e "\n${YELLOW}======== Step 2: VPP Creates Host Interfaces ========${NC}"
vpp_cmd create tap host-if-name tap0
vpp_cmd create tap host-if-name tap1
vpp_cmd create tap host-if-name tap2
echo -e "${PURPLE}VALIDATING: Pausing for 1 second for interfaces to appear on host...${NC}"
sleep 1
for i in 0 1 2; do
    if sudo ip link show "tap${i}" > /dev/null; then
        echo -e "${GREEN}OK: Host interface tap${i} successfully created.${NC}"
    else
        echo -e "${RED}VALIDATION FAILED: Host interface tap${i} not found!${NC}"; fail_and_dump;
    fi
done

# --- Step 3: Configure Host Network Environment ---
echo -e "\n${YELLOW}======== Step 3: Configuring Host Network Environment ========${NC}"
echo "Creating network namespaces..."
sudo ip netns add ns1
sudo ip netns add ns2
sudo ip netns add ns3
echo "Moving VPP-created interfaces into namespaces..."
sudo ip link set tap0 netns ns1
sudo ip link set tap1 netns ns2
sudo ip link set tap2 netns ns3
echo -e "${PURPLE}VALIDATING: Pausing for 1 second for namespace changes to settle...${NC}"
sleep 1
for i in 0 1 2; do
    if ! sudo ip link show "tap${i}" > /dev/null 2>&1; then
        echo -e "${GREEN}OK: Host interface tap${i} successfully moved from host namespace.${NC}"
    else
        echo -e "${RED}VALIDATION FAILED: Host interface tap${i} still exists on host!${NC}"; fail_and_dump;
    fi
done

echo "Configuring interfaces and routes inside namespaces..."
sudo ip netns exec ns1 ip link set lo up && sudo ip netns exec ns1 ip link set tap0 up && sudo ip netns exec ns1 ip addr add 192.168.10.10/24 dev tap0 && sudo ip netns exec ns1 ip route add default via 192.168.10.1
sudo ip netns exec ns2 ip link set lo up && sudo ip netns exec ns2 ip link set tap1 up && sudo ip netns exec ns2 ip addr add 192.168.10.20/24 dev tap1 && sudo ip netns exec ns2 ip route add default via 192.168.10.1
sudo ip netns exec ns3 ip link set lo up && sudo ip netns exec ns3 ip link set tap2 up && sudo ip netns exec ns3 ip addr add 10.10.10.2/24 dev tap2 && sudo ip netns exec ns3 ip route add 192.168.10.0/24 via 10.10.10.1
echo -e "${GREEN}Host network environment setup is complete.${NC}"

# --- Step 4: Configure VPP Bridging and Routing with Validation ---
echo -e "\n${YELLOW}======== Step 4: Configuring VPP with Validation (Ground-Truth Syntax) ========${NC}"
vpp_cmd set interface state tap0 up
vpp_cmd set interface state tap1 up
vpp_cmd set interface state tap2 up
vpp_cmd create bridge-domain 10
vpp_cmd set interface l2 bridge tap0 10
vpp_cmd set interface l2 bridge tap1 10

# === THE CORRECT, MULTI-STEP BVI CONFIGURATION FOR THIS VPP VERSION ===
vpp_cmd bvi create
vpp_cmd set interface ip address bvi0 192.168.10.1/24
vpp_cmd set interface l2 bridge bvi0 10 bvi
vpp_cmd set interface state bvi0 up

vpp_cmd set interface ip address tap2 10.10.10.1/24
vpp_cmd ip route add 0.0.0.0/0 via 10.10.10.2 tap2
echo "Dumping final VPP configuration for review:"
vpp_cmd show interface
vpp_cmd show bridge-domain 10 detail
vpp_cmd show ip fib
echo -e "${GREEN}VPP configuration is complete.${NC}"

# --- Step 5: Final Verification and Testing ---
echo -e "\n${YELLOW}======== Step 5: Final Verification and Testing ========${NC}"
echo -e "${PURPLE}Warming up ARP table by pinging gateway...${NC}"
# Use a timeout in case ping fails, so script doesn't hang. Typo fixed here.
sudo ip netns exec ns1 ping -c 1 -W 2 192.168.10.1 || echo "Gateway ping may have failed, but continuing test..."
echo "Dumping VPP Neighbor table (ARP) after gateway ping:"
# === THE CORRECT ARP/NEIGHBOR COMMAND FOR THIS VPP VERSION ===
vpp_cmd show ip neighbor

echo -e "\n${PURPLE}Test 1: Intra-Bridge Domain Communication (L2 Path: ns1 -> ns2)${NC}"
sudo ip netns exec ns1 ping -c 4 192.168.10.20

echo -e "\n${PURPLE}Test 2: Communication to the Gateway (ns1 -> BVI)${NC}"
sudo ip netns exec ns1 ping -c 4 192.168.10.1

echo -e "\n${PURPLE}Test 3: Routed Communication through BVI (L2 -> L3 -> L2 Path: ns1 -> WAN)${NC}"
sudo ip netns exec ns1 ping -c 4 10.10.10.2

echo -e "\n${GREEN}=============== LAB SETUP AND VERIFICATION COMPLETE ===============${NC}"
echo -e "To clean up, run: ${CYAN}sudo ./cleanup.sh${NC}"

# Disable the error trap on successful exit
trap - ERR