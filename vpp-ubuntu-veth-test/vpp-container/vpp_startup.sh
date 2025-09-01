#!/bin/bash

# Start VPP in the background using the custom startup configuration
/usr/bin/vpp -c /etc/vpp/startup.conf &

# Wait for VPP to initialize its API socket.
sleep 5

echo "--- Dynamically Configuring 5 VPP host interfaces ---"

# **THE FIX**: Use a robust method to list kernel interfaces.
# This avoids parsing the messy output of ifconfig.
for INTERFACE_NAME in $(ls /sys/class/net | grep '^eth[0-9]*')
do
  # Discover the IP address assigned by Docker to this kernel interface
  DISCOVERED_IP=$(ip addr show dev "${INTERFACE_NAME}" | grep -o 'inet [0-9./]*' | awk '{print $2}')

  if [ -z "$DISCOVERED_IP" ]; then
    echo "Could not find IP for ${INTERFACE_NAME}, skipping."
    continue
  fi

  echo "Discovered ${INTERFACE_NAME} has IP ${DISCOVERED_IP}. Capturing and configuring in VPP..."

  # Use vppctl to take over the interface and apply the discovered IP address
  vppctl create host-interface name "${INTERFACE_NAME}"
  vppctl set interface state "host-${INTERFACE_NAME}" up
  vppctl set interface ip address "host-${INTERFACE_NAME}" "${DISCOVERED_IP}"
done

echo "--- VPP dynamic configuration complete ---"
vppctl show int addr

# Keep the container running
tail -f /dev/null