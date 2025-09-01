#!/bin/bash
set -e

# --- 0. Network Configuration (Done by Docker) ---
echo "--> [Lab Setup] IPv6 forwarding should be enabled by Docker."

# --- 1. Create the Multi-Interface VLAN Network using Bridges ---
echo "--> [Lab Setup] Creating 4 dual-stack (IPv4/IPv6) bridged VLAN networks..."

for i in {1..4}; do
    srv_if="srv-eth${i}"
    cli_if="cli-eth${i}"
    vlan_id=$((100 + i))
    sub_if="${srv_if}.${vlan_id}"
    bridge_if="br${vlan_id}"

    ip link del ${srv_if} 2>/dev/null || true
    ip link del ${bridge_if} 2>/dev/null || true

    ip link add ${srv_if} type veth peer name ${cli_if}
    ip link set ${srv_if} up
    ip link set ${cli_if} up
    ip link add link ${srv_if} name ${sub_if} type vlan id ${vlan_id}
    ip link set ${sub_if} up
    ip link add name ${bridge_if} type bridge
    ip link set ${bridge_if} up
    ip link set ${sub_if} master ${bridge_if}
    ip addr add 192.10${i}.1.1/16 dev ${bridge_if}
    ip -6 addr add 2001:db8:10${i}::1/64 dev ${bridge_if}
    sysctl -w net.ipv6.conf.${cli_if}.disable_ipv6=0 > /dev/null 2>&1

    echo "    - Link ${i}: [Bridge: ${bridge_if}] [IPv4: 192.10${i}.1.1/16] [IPv6: 2001:db8:10${i}::1/64]"
done

# --- 2. Wait for Network Initialization ---
echo "--> [Lab Setup] Waiting for network interfaces to stabilize (DAD completion)..."
while ip addr show | grep -q "scope global tentative"; do
    echo "    - DAD in progress, waiting..."
    sleep 1
done
echo "    - All IPv6 addresses are ready."

# --- 3. Create Runtime Directories & Set Permissions ---
echo "--> [Lab Setup] Creating runtime directories and setting permissions..."
mkdir -p /var/run/kea /var/lib/kea /var/log/kea /var/run/radvd
chown radvd:nogroup /var/run/radvd /var/log/radvd.log
# radvd.conf permissions are set in the Dockerfile
chown root:root /var/run/kea /var/lib/kea /var/log/kea
chmod 750 /var/run/kea
chmod 775 /var/log/kea
touch /var/log/kea/kea-dhcp4.log /var/log/kea/kea-dhcp6.log /var/log/kea/kea-ctrl-agent.log
chown root:root /var/log/kea/*.log
chmod 664 /var/log/kea/*.log
echo "    - Permissions set."

# --- 4. Pre-Start Configuration Validation ---
echo "--> [Lab Setup] Validating configuration files..."
echo "    - radvd.conf: Skipping pre-validation, will be verified after startup."

if ! /usr/sbin/kea-dhcp4 -t /etc/kea/kea-dhcp4.conf; then
    echo "    - ✖ ERROR: kea-dhcp4.conf is invalid. Aborting." >&2
    exit 1
fi
echo "    - kea-dhcp4.conf: OK"

if ! /usr/sbin/kea-dhcp6 -t /etc/kea/kea-dhcp6.conf; then
    echo "    - ✖ ERROR: kea-dhcp6.conf is invalid. Aborting." >&2
    exit 1
fi
echo "    - kea-dhcp6.conf: OK"

if ! /usr/sbin/kea-ctrl-agent -t /etc/kea/kea-ctrl-agent.conf; then
    echo "    - ✖ ERROR: kea-ctrl-agent.conf is invalid. Aborting." >&2
    exit 1
fi
echo "    - kea-ctrl-agent.conf: OK"
echo "    - All configurations are valid."

# --- 5. Start Services ---
echo "--> [Lab Setup] Starting services in the background..."

echo "    - Starting Bng Controller ..."
/usr/local/bin/bngblasterctrl > /tmp/bngblasterctrl-startup.log 2>&1 &

echo "    - Starting radvd (as root, will drop privileges to 'radvd' user)..."
# Start as root and use the -u flag to have the daemon drop privileges itself.
# This is the standard, secure way to run radvd and allows it to open privileged sockets.
/usr/sbin/radvd --nodaemon -C /etc/radvd.conf -u radvd > /tmp/radvd-startup.log 2>&1 &

echo "    - Starting kea-dhcp4..."
/usr/sbin/kea-dhcp4 -c /etc/kea/kea-dhcp4.conf > /tmp/kea-dhcp4-startup.log 2>&1 &

echo "    - Starting kea-dhcp6..."
/usr/sbin/kea-dhcp6 -c /etc/kea/kea-dhcp6.conf > /tmp/kea-dhcp6-startup.log 2>&1 &

echo "    - Starting kea-ctrl-agent..."
/usr/sbin/kea-ctrl-agent -c /etc/kea/kea-ctrl-agent.conf > /tmp/kea-ctrl-agent-startup.log 2>&1 &

echo "--> [Lab Setup] Waiting 5 seconds for services to initialize..."
sleep 5

# --- 4. Validate Service Startup ---
echo "--> [Lab Setup] Verifying that all services have started..."
pgrep -f bngblasterctrl > /dev/null || (echo "   - ✖ FAILURE: bngblasterctrl did not start." && exit 1)
pgrep -f radvd > /dev/null || (echo "   - ✖ FAILURE: radvd did not start." && exit 1)
pgrep -f kea-dhcp4 > /dev/null || (echo "   - ✖ FAILURE: kea-dhcp4 did not start." && exit 1)
pgrep -f kea-dhcp6 > /dev/null || (echo "   - ✖ FAILURE: kea-dhcp6 did not start." && exit 1)
pgrep -f kea-ctrl-agent > /dev/null || (echo "   - ✖ FAILURE: kea-ctrl-agent did not start." && exit 1)
echo "    - ✔ SUCCESS: All services are running."

# --- 5. Hand Over to the User ---
echo
echo "✅ Kea + BNG Blaster Lab Environment is Ready."
echo "========================================================================"
echo " You are now inside the lab container. The network and all Kea"
echo " services are running in the background."
echo "========================================================================"
echo

# --- 6. Validate Service Startup ---
validate_services() {
    echo "--> [Lab Setup] Verifying that all services have started..."
    local services=("radvd" "kea-dhcp4" "kea-dhcp6" "kea-ctrl-agent" "bngblasterctrl")
    local all_ok=true

    for service in "${services[@]}"; do
        if pgrep -f "$service" > /dev/null; then
            local pid=$(pgrep -f "$service" | head -n 1)
            echo "    - ✔ SUCCESS: Service '$service' is running (PID $pid)."
        else
            echo "    - ✖ FAILURE: Service '$service' did not start."
            all_ok=false
            local startup_log="/tmp/${service}-startup.log"
            local main_log="/var/log/kea/${service}.log"
            if [[ "$service" == "radvd" ]]; then
                main_log="/var/log/radvd.log"
            fi
            echo "      --- Startup Log (${startup_log}) ---"
            if [ -f "$startup_log" ]; then
                cat "$startup_log" | sed 's/^/      | /'
            else
                echo "      | Startup log not found."
            fi
            echo "      --- Main Log (${main_log}) ---"
            if [ -f "$main_log" ]; then
                tail -n 20 "$main_log" | sed 's/^/      | /'
            else
                echo "      | Main log not found."
            fi
            echo "      --------------------------------------------------"
        fi
    done

    if [ "$all_ok" = false ]; then
        echo "--> [Lab Setup] One or more services failed to start. Aborting." >&2
        #exit 1
    fi
}

validate_services

# --- 7. Hand Over to the User ---
echo
echo "✅ Kea + BNG Blaster Lab Environment is Ready."
echo
echo "sudo docker exec -it keactrl-dev-lab /bin/bash"
echo "You can now run commands inside the lab container."
echo "To stop the lab, run: docker stop keactrl-dev-lab"
echo
echo "========================================================================"
echo
echo "   You are now inside the lab container. The network and all Kea"
echo "   services are running in the background."
echo
echo "   COMMON WORKFLOW:"
echo "   1. Navigate to the project directory:"
echo "      cd /usr/src/keactrl"
echo
echo "   2. Compile the library and CLI tool:"
echo "      ./build.sh"
echo
echo "   3. Run the integration test suite:"
echo "      ./build/bin/test_runner"
echo "      BNG_HELPER_DEBUG=1 ./build/bin/test_runner"
echo
echo "   4. Run the commands through standard way :"
echo 
echo "      cp ./lab/kea-shell /usr/sbin/kea-shell"
echo "      kea-shell --auth-user root --auth-password root --service dhcp4 list-commands"
echo
echo "      curl -X POST -H \"Content-Type: application/json\" -d '{ \"command\": \"config-get\", \"service\": [ \"dhcp4\" ] }' --user \"root:root\" http://localhost:8000/ | jq ."
echo "      echo '{ \"command\": \"config-get\", \"service\": [ \"dhcp4\" ] }' | socat UNIX:/var/run/kea/kea-dhcp4-ctrl.sock - | jq ."
echo
echo "------------------------------------------------------------------------"
echo "   BNG BLASTER TESTING TIP:"
echo
echo "   Kea sanity test."
echo "   To run a dual-stack test, execute:"
echo "   /usr/sbin/bngblaster -C /usr/src/keactrl/lab/config/blaster/dualstack.json -I -l dhcp -l debug -l error -l info -l packet -I -J report.json -j sessions -L report.log -P report.pcap -c 2"
echo
echo "   Kea configs are optimized for performance (in-memory DB, INFO logs)."
echo "   To run a high-rate dual-stack test, execute:"
echo "   /usr/sbin/bngblaster -C /usr/src/keactrl/lab/config/blaster/high_rate_dual_stack.json"
echo
echo "========================================================================"
echo
exec "$@"
# End of entrypoint.sh