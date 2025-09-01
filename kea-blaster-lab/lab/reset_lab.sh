#!/bin/bash
#
# Lightweight Inter-Test State Reset Script
#
# This script performs a targeted reset of application-level state, leaving
# the stable network topology and bngblaster-controller untouched.
#
set -e

echo "--> [Test Reset] Performing lightweight state reset..."

# 1. Stop only the Kea services
echo "    - Stopping Kea services..."
DAEMONS=("kea-dhcp4" "kea-dhcp6" "kea-ctrl-agent")
for daemon in "${DAEMONS[@]}"; do
    if pgrep -f "$daemon" > /dev/null; then
        pkill -f "$daemon" || true
    fi
done
sleep 1

# 2. Clean BNG Blaster and Kea state
echo "    - Cleaning filesystem state and IPC resources..."
rm -f /run/lock/bngblaster_* /var/run/kea/* 2>/dev/null || true
ipcs -q | grep root | awk '{print $2}' | xargs -r -I {} ipcrm -q {} >/dev/null 2>&1 || true
ipcs -m | grep root | awk '{print $2}' | xargs -r -I {} ipcrm -m {} >/dev/null 2>&1 || true
ipcs -s | grep root | awk '{print $2}' | xargs -r -I {} ipcrm -s {} >/dev/null 2>&1 || true

# 3. Restore pristine Kea configurations
echo "    - Restoring original Kea configurations..."
cp /etc/kea/original/*.conf /etc/kea/

# 4. Restart Kea services
echo "    - Restarting Kea services..."
/usr/sbin/kea-dhcp4 -c /etc/kea/kea-dhcp4.conf > /tmp/kea-dhcp4-reset.log 2>&1 &
/usr/sbin/kea-dhcp6 -c /etc/kea/kea-dhcp6.conf > /tmp/kea-dhcp6-reset.log 2>&1 &
/usr/sbin/kea-ctrl-agent -c /etc/kea/kea-ctrl-agent.conf > /tmp/kea-ctrl-agent-reset.log 2>&1 &
sleep 2 # Give them time to start

# 5. Final Validation
for daemon in "${DAEMONS[@]}"; do
    if ! pgrep -f "$daemon" > /dev/null; then
        echo "Reset failed: $daemon did not restart." >&2
        cat "/tmp/$daemon-reset.log" >&2
        exit 1
    fi
done

echo "--> [Test Reset] Reset complete. Kea services restarted."
exit 0