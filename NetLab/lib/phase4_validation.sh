#!/bin/bash
#
# VPP NetLab: Phase 4 - Validation (Pure L3 Router)

print_header "Phase 4: Validating Network Connectivity"

print_header "4.1: Configuring Clients with Static IPs"
# No more VLAN sub-interfaces needed
run_cmd sudo ip netns exec ns-server1 ip addr add 192.168.10.101/24 dev veth-srv1-p1
run_cmd sudo ip netns exec ns-server1 ip route add default via 192.168.10.1
run_cmd sudo ip netns exec ns-server2 ip addr add 192.168.10.102/24 dev veth-srv2-p1
run_cmd sudo ip netns exec ns-server2 ip route add default via 192.168.10.1

echo -e "\n--- Pausing for 2 seconds for ARP to resolve... ---"
sleep 2

print_header "4.2: Running Connectivity Tests"
# NOTE: Intra-VLAN test is now just a standard L2 test on the Linux bridge
echo -e "\n${GREEN}---> Test 1: L2 Connectivity on Server Bridge (ns-server1 -> ns-server2)${NC}"
run_cmd sudo ip netns exec ns-server1 ping -c 4 192.168.10.102

echo -e "\n${GREEN}---> Test 2: L3 Routing via VPP (ns-server1 -> ns-external)${NC}"
run_cmd sudo ip netns exec ns-server1 ping -c 4 10.0.0.2

print_header "4.3: Final VPP State Dump"
echo "--- VPP ToR Switch Neighbor Table ---"
vpp_tor_cmd show ip neighbor

echo -e "\n"