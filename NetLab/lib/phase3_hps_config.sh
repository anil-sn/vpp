#!/bin/bash
#
# VPP NetLab: Phase 3 - HPS Configuration (Absolutely Final Version)

print_header "Phase 3: Configuring VPP High-Perf Server (${HPS_VPP_NAME})"

echo -e "\n--- Creating the 'slave' side of the memif connection via command line ---"
# FIX: Use the full, explicit command line version, which we know works.
# This bypasses any startup.conf file parsing issues.
vpp_hps_cmd create interface memif id 0 slave filename ${TOR_SOCKET_DIR}/memif.sock

vpp_hps_cmd create host-interface name xdp-veth-p0

echo -e "\n--- Setting interface states to 'up' ---"
vpp_hps_cmd set interface state memif0/0 up
vpp_hps_cmd set interface state host-xdp-veth-p0 up

print_header "3.2: Configuring L2 Cross-Connect on HPS"
vpp_hps_cmd set interface l2 xconnect memif0/0 host-xdp-veth-p0
vpp_hps_cmd set interface l2 xconnect host-xdp-veth-p0 memif0/0

print_header "3.3: Starting Packet Captures on HPS"
start_pcap ${HPS_VPP_NAME} host-xdp-veth-p0 captures/hps_xdp_link.pcap

print_header "HPS Final Configuration Review"
vpp_hps_cmd show interface
vpp_hps_cmd show l2fib verbose

echo -e "\n${GREEN}====== Phase 3: VPP High-Perf Server Configuration Complete ======${NC}\n"