#!/bin/bash
#
# VPP NetLab: Common Library
#
# Contains all shared variables and helper functions used by the
# main orchestration scripts.
#

# --- Configuration ---
VPP_IMAGE="vpp-netlab-img:latest"
TOR_VPP_NAME="vpp-tor-switch"
HPS_VPP_NAME="vpp-hps-server"
TOR_SOCKET_DIR="/var/run/vpp-tor"
HPS_SOCKET_DIR="/var/run/vpp-hps"

# --- Color Definitions ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

# --- Helper Functions ---

function print_header() {
    echo -e "\n${PURPLE}=================================================================${NC}"
    echo -e "${PURPLE}# $1${NC}"
    echo -e "${PURPLE}=================================================================${NC}"
}

function run_cmd() {
    echo -e "${CYAN}# CMD: $*${NC}"
    "$@"
}

function docker_exec() {
    sudo docker exec "$@"
}

function vpp_tor_cmd() {
    echo -e "${GREEN}# VPP_TOR_CMD: $*${NC}"
    docker_exec ${TOR_VPP_NAME} vppctl "$@"
}

function vpp_hps_cmd() {
    echo -e "${YELLOW}# VPP_HPS_CMD: $*${NC}"
    docker_exec ${HPS_VPP_NAME} vppctl "$@"
}

function start_pcap() {
    local target=$1
    local interface=$2
    local file=$3
    echo -e "${YELLOW}# PCAP: Starting capture on ${target}:${interface} -> ${file}${NC}"
    # Ensure capture directory exists
    run_cmd sudo mkdir -p "$(dirname "${file}")"
    if [[ "${target}" == "host" ]]; then
        sudo tshark -i "${interface}" -w "${file}" >/dev/null 2>&1 &
    elif [[ "${target}" == ns-* ]]; then
        sudo ip netns exec "${target}" tshark -i "${interface}" -w "${file}" >/dev/null 2>&1 &
    else
        docker_exec "${target}" tshark -i "${interface}" -w "${file}" >/dev/null 2>&1 &
    fi
}

function debug_vpp_startup() {
    echo -e "\n${RED}====== VPP STARTUP FAILED: DUMPING LOGS FOR DEBUGGING ======${NC}"
    echo -e "${YELLOW}--- LOGS FOR ${TOR_VPP_NAME} ---${NC}"
    docker_exec ${TOR_VPP_NAME} cat /var/log/vpp/vpp.log 2>/dev/null || sudo docker logs ${TOR_VPP_NAME}
    echo -e "\n${YELLOW}--- LOGS FOR ${HPS_VPP_NAME} ---${NC}"
    docker_exec ${HPS_VPP_NAME} cat /var/log/vpp/vpp.log 2>/dev/null || sudo docker logs ${HPS_VPP_NAME}
    echo -e "\n${RED}==================== END OF STARTUP DUMP ====================${NC}"
    echo -e "${RED}Exiting due to VPP startup failure. Please check logs above.${NC}"
    # Run cleanup to avoid leaving orphaned resources
    if [ -f ./cleanup.sh ]; then
        echo "--- Running cleanup script... ---"
        sudo ./cleanup.sh > /dev/null 2>&1
    fi
    exit 1
}