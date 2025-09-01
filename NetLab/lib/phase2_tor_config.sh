#!/bin/bash
#
# VPP NetLab: Phase 2 - ToR Switch Configuration (Pure L3 Router)

print_header "Phase 2: Configuring VPP ToR Switch as a Pure L3 Router"

echo -e "\n--- Configuring server-facing interface ---"
vpp_tor_cmd create host-interface name veth-vpp-srv-p1
vpp_tor_cmd set interface ip address host-veth-vpp-srv-p1 192.168.10.1/24
vpp_tor_cmd set interface state host-veth-vpp-srv-p1 up

echo -e "\n--- Configuring external-facing interface ---"
vpp_tor_cmd create host-interface name veth-vpp-ext-p1
vpp_tor_cmd set interface ip address host-veth-vpp-ext-p1 10.0.0.1/24
vpp_tor_cmd set interface state host-veth-vpp-ext-p1 up

echo "--- VPP is now routing between 192.168.10.0/24 and 10.0.0.0/24 ---"

print_header "ToR Switch Final Configuration Review"
vpp_tor_cmd show interface
vpp_tor_cmd show ip fib

echo -e "\n${GREEN}====== Phase 2: VPP ToR Switch Configuration Complete ======${NC}\n"