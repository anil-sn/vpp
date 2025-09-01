#!/bin/bash
#
# =================================================================
# VPP NetLab: A Multi-Interface Networking Lab
# =================================================================
#
# Main orchestration script.

set -e

LIB_DIR="$(dirname "$0")/lib"

source "${LIB_DIR}/common.sh"

# Initial cleanup to ensure a fresh environment
print_header "Phase 0: Initial Cleanup"
if [ -f ./cleanup.sh ]; then
    echo "--- Running cleanup script to ensure a fresh environment ---"
    # Run the cleanup script, but hide its output for a cleaner start
    sudo ./cleanup.sh > /dev/null
fi

source "${LIB_DIR}/phase1_setup.sh"
source "${LIB_DIR}/phase2_tor_config.sh"
#source "${LIB_DIR}/phase3_hps_config.sh"
source "${LIB_DIR}/phase4_validation.sh"

print_header "VPP NetLab Setup and Verification Complete!"
echo -e "${GREEN}=================================================================${NC}"
echo -e "${GREEN}# All tests passed. To explore the environment, use commands   #"
echo -e "${GREEN}# like 'sudo docker exec -it vpp-tor-switch bash' or           #"
echo -e "${GREEN}# 'sudo ip netns exec ns-server1 ping 10.0.0.2'.               #"
echo -e "${GREEN}#                                                              #"
echo -e "${GREEN}# To tear down, run: sudo ./cleanup.sh                         #"
echo -e "${GREEN}=================================================================${NC}"

# FIX: Add a final echo to prevent a scrambled prompt
echo ""

trap - ERR