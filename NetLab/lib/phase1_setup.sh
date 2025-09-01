#!/bin/bash
#
# VPP NetLab: Phase 1 - Environment Setup (Dual-Homed Router)

print_header "Phase 1.0: Prerequisite Check"
HUGEPAGES=$(cat /proc/meminfo | grep HugePages_Total | awk '{print $2}')
[ "$HUGEPAGES" -lt "1024" ] && { echo "Hugepages not configured."; sudo sysctl -w vm.nr_hugepages=1024; echo "Hugepages configured Now."; }

print_header "Phase 1.1: Build VPP Docker Image"
run_cmd sudo docker build -t ${VPP_IMAGE} .

print_header "Phase 1.2: Create VPP Socket Directory"
run_cmd sudo mkdir -p ${TOR_SOCKET_DIR} && run_cmd sudo chmod -R 777 ${TOR_SOCKET_DIR}

print_header "Phase 1.3: Starting VPP Container"
run_cmd sudo docker run -d --name ${TOR_VPP_NAME} --hostname ${TOR_VPP_NAME} \
            --privileged --net=host --ulimit memlock=-1:-1 -v ${TOR_SOCKET_DIR}:/run/vpp/ -v /dev/hugepages:/dev/hugepages \
            ${VPP_IMAGE} /bin/bash -c "/usr/bin/vpp -c /etc/vpp/vpp-tor-startup.conf"

echo -n "--- Waiting for VPP service to be ready..."
# (Wait loop is fine)
VPP_READY=false
for i in {1..15}; do
    if sudo docker ps -f "name=${TOR_VPP_NAME}" -f "status=running" | grep -q . && \
       docker_exec "${TOR_VPP_NAME}" vppctl show version > /dev/null 2>&1; then
        echo -e " ${GREEN}VPP container is running and responsive.${NC}"
        VPP_READY=true
        break
    fi
    echo -n "."
    sleep 1
done
[ "$VPP_READY" = true ] || debug_vpp_startup

print_header "Phase 1.4: Creating Linux Network Plumbing"
run_cmd sudo ip netns add ns-server1 && run_cmd sudo ip netns add ns-server2 && run_cmd sudo ip netns add ns-external

# Create a bridge for the server network
echo "--- Creating server bridge: br_srv ---"
run_cmd sudo ip link add br_srv type bridge && run_cmd sudo ip link set br_srv up
run_cmd sudo ip link add veth-srv1-p0 type veth peer name veth-srv1-p1
run_cmd sudo ip link set veth-srv1-p0 master br_srv && run_cmd sudo ip link set veth-srv1-p0 up && run_cmd sudo ip link set veth-srv1-p1 netns ns-server1
run_cmd sudo ip link add veth-srv2-p0 type veth peer name veth-srv2-p1
run_cmd sudo ip link set veth-srv2-p0 master br_srv && run_cmd sudo ip link set veth-srv2-p0 up && run_cmd sudo ip link set veth-srv2-p1 netns ns-server2

# Create a bridge for the external network
echo "--- Creating external bridge: br_ext ---"
run_cmd sudo ip link add br_ext type bridge && run_cmd sudo ip link set br_ext up
run_cmd sudo ip link add veth-ext-p0 type veth peer name veth-ext-p1
run_cmd sudo ip link set veth-ext-p0 master br_ext && run_cmd sudo ip link set veth-ext-p0 up && run_cmd sudo ip link set veth-ext-p1 netns ns-external

# Create two uplinks for VPP, one to each bridge
echo "--- Creating VPP uplinks ---"
TOR_NS_PID=$(sudo docker inspect -f '{{.State.Pid}}' ${TOR_VPP_NAME})
run_cmd sudo ip link add veth-vpp-srv type veth peer name veth-vpp-srv-p1
run_cmd sudo ip link set veth-vpp-srv master br_srv && run_cmd sudo ip link set veth-vpp-srv up && run_cmd sudo ip link set veth-vpp-srv-p1 netns ${TOR_NS_PID}
run_cmd sudo ip link add veth-vpp-ext type veth peer name veth-vpp-ext-p1
run_cmd sudo ip link set veth-vpp-ext master br_ext && run_cmd sudo ip link set veth-vpp-ext up && run_cmd sudo ip link set veth-vpp-ext-p1 netns ${TOR_NS_PID}

print_header "Phase 1.5: Configuring Interfaces inside Namespaces"
run_cmd sudo ip netns exec ns-server1 ip link set lo up && run_cmd sudo ip netns exec ns-server1 ip link set veth-srv1-p1 up
run_cmd sudo ip netns exec ns-server2 ip link set lo up && run_cmd sudo ip netns exec ns-server2 ip link set veth-srv2-p1 up
run_cmd sudo ip netns exec ns-external ip link set lo up && run_cmd sudo ip netns exec ns-external ip link set veth-ext-p1 up
run_cmd sudo ip netns exec ns-external ip addr add 10.0.0.2/24 dev veth-ext-p1 && run_cmd sudo ip netns exec ns-external ip route add default via 10.0.0.1

echo -e "\n${GREEN}====== Phase 1: Environment Setup Complete ======${NC}\n"