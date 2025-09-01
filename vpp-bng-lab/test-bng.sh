#!/bin/bash
# =========================================================================
# VPP BNG Lab - Main Test Script (Final Version with Corrected Validation)
# =========================================================================
set -e

# --- Configuration ---
BLASTER_CONFIG_FILE="dual-stack-400.json"
BLASTER_CTRL_SOCKET="/tmp/bngblaster.sock"

# --- Main Script Execution ---

# 1. Setup Phase
echo "--- (1/7) Cleaning up previous lab runs... ---"
docker compose down -v --remove-orphans 2>/dev/null || true

echo -e "\n--- (2/7) Building and starting BNG and Subscriber containers... ---"
docker compose up --build -d

# 3. BNG Readiness Check Phase
echo -e "\n--- (3/7) Verifying VPP BNG readiness... ---"
EXPECTED_INTERFACES=4
MAX_ATTEMPTS=20
SUCCESS=false
for i in $(seq 1 $MAX_ATTEMPTS); do
    echo "Attempt $i/$MAX_ATTEMPTS: Checking VPP sub-interface states..."
    vpp_state=$(docker exec vpp-bng-node vppctl show int addr || true)
    configured_count=$(echo "$vpp_state" | grep -cE '^\s+L3 192\.10[1-4]\.' || true)
    if [ "${configured_count:-0}" -eq "$EXPECTED_INTERFACES" ]; then
        echo "Success! VPP reports all $EXPECTED_INTERFACES BNG interfaces are configured."
        SUCCESS=true; break
    fi
    echo "BNG not ready yet. Found ${configured_count:-0}/$EXPECTED_INTERFACES interfaces. Retrying..."
    sleep 2
done
if [ "$SUCCESS" = false ]; then echo "ERROR: VPP BNG did not become ready."; docker logs vpp-bng-node; docker compose down; exit 1; fi

# 4. **NEW** BNG Configuration Validation Phase
echo -e "\n--- (4/7) Validating VPP BNG configuration state... ---"
echo "--> Checking DHCP Proxy configuration:"
docker exec vpp-bng-node vppctl show dhcp proxy
echo "--> Checking DHCPv6 Proxy configuration:"
docker exec vpp-bng-node vppctl show dhcpv6 proxy
echo "--> Checking IPv6 ND RA configuration for host-eth0.101:"
# **THE FIX**: Use the correct command 'show ip6 neighbors' to see RA details.
docker exec vpp-bng-node vppctl show ip6 neighbors host-eth0.101

# 5. BNG Blaster Startup Phase
echo -e "\n--- (5/7) Preparing and starting BNG Blaster... ---"
echo "--> Preparing subscriber interfaces for raw BNG Blaster use..."
for i in {0..3}; do
    SUBSCRIBER_IF="eth${i}"
    DOCKER_IP=$(docker exec bng-subscriber-node ip addr show dev "${SUBSCRIBER_IF}" | grep -o 'inet [0-9./]*' | awk '{print $2}' || true)
    if [ -n "$DOCKER_IP" ]; then
        docker exec bng-subscriber-node ip addr del "${DOCKER_IP}" dev "${SUBSCRIBER_IF}"
    fi
    docker exec bng-subscriber-node ip link set "${SUBSCRIBER_IF}" promisc on
done

echo "--> Starting BNG Blaster daemon..."
docker exec -d bng-subscriber-node bngblaster -C "/config/${BLASTER_CONFIG_FILE}" -S "${BLASTER_CTRL_SOCKET}"

echo "--> Verifying BNG Blaster daemon is running..."
MAX_ATTEMPTS=10
SUCCESS=false
for i in $(seq 1 $MAX_ATTEMPTS); do
    if docker exec bng-subscriber-node test -e "${BLASTER_CTRL_SOCKET}"; then
        echo "Success! BNG Blaster daemon is ready."; SUCCESS=true; break
    fi
    sleep 1
done
if [ "$SUCCESS" = false ]; then echo "ERROR: BNG Blaster daemon failed to start."; docker compose down; exit 1; fi

# 6. Session Verification and Traffic Test
echo -e "\n--- (6/7) Verifying all subscriber sessions are established... ---"
TOTAL_SESSIONS=$(jq .sessions.count < subscriber-node/config/${BLASTER_CONFIG_FILE})
MAX_ATTEMPTS=30
SUCCESS=false
for i in $(seq 1 $MAX_ATTEMPTS); do
    counters_json=$(docker exec bng-subscriber-node bngblaster-cli "${BLASTER_CTRL_SOCKET}" session-counters)
    established_count=$(echo "${counters_json}" | jq .established | sed 's/null/0/')
    echo "Attempt $i/$MAX_ATTEMPTS: Waiting for sessions to be established... (${established_count}/${TOTAL_SESSIONS})"
    if [ "${established_count}" -eq "$TOTAL_SESSIONS" ]; then
        echo "Success! All ${TOTAL_SESSIONS} sessions are established."; SUCCESS=true; break
    fi
    sleep 2
done
if [ "$SUCCESS" = false ]; then 
    echo "ERROR: Not all sessions were established in time."; 
    docker exec bng-subscriber-node bngblaster-cli "${BLASTER_CTRL_SOCKET}" session-counters;
    docker compose down; 
    exit 1; 
fi

echo -e "\n--> Running data plane traffic test for 10 seconds..."
docker exec bng-subscriber-node bngblaster-cli "${BLASTER_CTRL_SOCKET}" traffic-start
sleep 10
docker exec bng-subscriber-node bngblaster-cli "${BLASTER_CTRL_SOCKET}" traffic-stop
echo "--> Traffic test complete. Checking final stream counters:"
docker exec bng-subscriber-node bngblaster-cli "${BLASTER_CTRL_SOCKET}" stream-counters

# 7. Graceful Shutdown & Final Results
echo -e "\n--- (7/7) Tearing down sessions and environment... ---"
docker exec bng-subscriber-node bngblaster-cli "${BLASTER_CTRL_SOCKET}" terminate
echo -e "\n--- Final BNG lease state... ---"
docker exec vpp-bng-node vppctl show dhcp client
docker exec vpp-bng-node vppctl show dhcpv6 proxy lease

echo -e "\n--- Tearing down Docker environment. ---"
docker compose down