#!/bin/bash
#
# Final Diagnostic Script
# Purpose: To establish ground truth for API responses and test for race conditions.
#
set +e # We want to see all output, even if a command fails.

echo "========================================================================"
echo "                KEA API GROUND TRUTH VERIFICATION"
echo "========================================================================"
echo

# --- Step 1: Establish Ground Truth for 'version-get' ---
echo "--- [DIAGNOSTIC 1/4] Capturing raw JSON for 'version-get dhcp4'..."
RESPONSE=$(kea-shell --auth-user root --auth-password root --service dhcp4 version-get)
echo "EXIT CODE: $?"
echo "RAW RESPONSE:"
echo ">>>>>>>>>>"
echo "$RESPONSE"
echo "<<<<<<<<<<"
echo

# --- Step 2: Establish Ground Truth for 'list-commands' error ---
echo "--- [DIAGNOSTIC 2/4] Capturing raw error for 'list-commands nonexistent-service'..."
ERROR_RESPONSE=$(kea-shell --auth-user root --auth-password root --service nonexistent-service list-commands 2>&1)
echo "EXIT CODE: $?"
echo "RAW RESPONSE:"
echo ">>>>>>>>>>"
echo "$ERROR_RESPONSE"
echo "<<<<<<<<<<"
echo

# --- Step 3: Test the Configuration Race Condition Hypothesis ---
echo "--- [DIAGNOSTIC 3/4] Testing config-set stability and race condition..."
# Save original config
kea-shell --auth-user root --auth-password root --service dhcp4 config-get | jq '.arguments.Dhcp4' > /tmp/before.json
echo "  - Original config saved to /tmp/before.json"

# Create modified config
jq '.["valid-lifetime"] = 5555' /tmp/before.json > /tmp/modified.json
echo "  - Modified config created with valid-lifetime: 5555"

# Apply modified config
echo "  - Applying modified config..."
kea-shell --auth-user root --auth-password root --service dhcp4 config-set file=/tmp/modified.json
echo "  - config-set command sent."
echo "  - WAITING 2 SECONDS for server to stabilize..."
sleep 2

# Restore original config
echo "  - Restoring original config..."
kea-shell --auth-user root --auth-password root --service dhcp4 config-set file=/tmp/before.json
echo "  - config-set command sent."
echo "  - WAITING 2 SECONDS for server to stabilize..."
sleep 2

# Verify restoration
kea-shell --auth-user root --auth-password root --service dhcp4 config-get | jq '.arguments.Dhcp4' > /tmp/after.json
echo "  - Final config saved to /tmp/after.json"

echo "  - Comparing before and after configurations..."
if diff -q /tmp/before.json /tmp/after.json; then
    echo "  - ✅ SUCCESS: Config restored correctly. Server appears stable."
else
    echo "  - ❌ FAILURE: Config was not restored correctly. Diff:"
    diff /tmp/before.json /tmp/after.json
fi
echo

# --- Step 4: Run an Isolated DHCP Lease Test ---
echo "--- [DIAGNOSTIC 4/4] Running isolated BNG Blaster DHCPv4 test..."
# Use a known-good, simple config
/usr/sbin/bngblaster -C /usr/src/keactrl/lab/config/blaster/1_session_dhcpv4.json -l error
B blaster_exit_code=$?
if [ $blaster_exit_code -eq 0 ]; then
    echo "  - ✅ SUCCESS: Isolated BNG Blaster test completed successfully."
else
    echo "  - ❌ FAILURE: Isolated BNG Blaster test failed with exit code $blaster_exit_code."
fi
echo

echo "========================================================================"
echo "                      DIAGNOSTIC RUN COMPLETE"
echo "========================================================================"