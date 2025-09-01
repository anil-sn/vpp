#!/bin/bash

# ====================================================================================
# Kea API Master Command Tester (Complete)
#
# This script is a comprehensive template for testing EVERY Kea Control Channel API
# command via the kea-ctrl-agent. It is designed to be informative and safe.
#
# !!! --- CRITICAL WARNING --- !!!
# This script is a TEMPLATE. DO NOT RUN IT BLINDLY ON A PRODUCTION SERVER.
#
# 1.  DESTRUCTIVE COMMANDS ARE COMMENTED OUT by default. These commands can
#     delete leases, modify configuration, wipe data, or shut down the server.
# 2.  YOU MUST EDIT PLACEHOLDERS like 'YOUR_SUBNET_ID' with values from your
#     environment before uncommenting and running a command.
# 3.  Test commands ONE AT A TIME.
#
# Prerequisites:
# - A running Kea server with the `kea-ctrl-agent` configured for HTTP access.
# - `curl` and `jq` command-line tools must be installed on the machine running this script.
# ====================================================================================

# --- Configuration ---
KEA_HOST="localhost"
KEA_PORT="8000"
KEA_USER="root"
KEA_PASS="root"

# --- Remote DB Args (for remote-* commands) ---
# Edit this JSON snippet with your remote database connection details.
# This is required for all commands prefixed with 'remote-'.
DB_ARGS='"remote": { "type": "mysql", "host": "db.example.com", "user": "kea", "password": "keapassword", "name": "kea" }'

# --- Helper Function ---
# This function sends a JSON payload to the Kea Control Agent and provides detailed output.
execute_kea_command() {
    local cmd_name="$1"
    local payload="$2"
    local description="$3"
    local service_target="$4"

    echo "################################################################################"
    echo "### Testing Command: $cmd_name"
    echo "################################################################################"
    echo
    echo "DESCRIPTION: $description"
    echo "TARGETS: $service_target"
    echo
    echo "--> INPUT (JSON Payload):"
    echo "$payload" | jq .
    echo

    # Construct the full curl command string for display
    local curl_command="curl -s -X POST -H \"Content-Type: application/json\" --user \"$KEA_USER:$KEA_PASS\" -d '$payload' \"http://$KEA_HOST:$KEA_PORT/\" | jq ."

    echo "--> EXECUTING (cURL Command):"
    echo "$curl_command"
    echo

    echo "<-- RESPONSE (from Kea Server):"
    # Execute the actual command
    curl -s -X POST -H "Content-Type: application/json" \
         --user "$KEA_USER:$KEA_PASS" \
         -d "$payload" \
         "http://$KEA_HOST:$KEA_PORT/" | jq .

    echo
    echo "### End of Test for: $cmd_name"
    echo "################################################################################"
    echo -e "\n\n"
    sleep 1 # Pause between commands
}

# ====================================================================================
# --- API COMMANDS (Systematically listed as per documentation) ---
# ====================================================================================

# --- build-report ---
CMD_NAME="build-report"
DESCRIPTION="Returns the list of compilation options that this particular binary was built with."
SERVICE="ctrl-agent, dhcp-ddns, dhcp4, dhcp6"
PAYLOAD='{ "command": "build-report", "service": [ "dhcp4" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- cache-clear ---
CMD_NAME="cache-clear"
DESCRIPTION="[host_cache hook] Removes all cached host reservations."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "cache-clear", "service": [ "dhcp4" ] }'
# !!! DANGEROUS: Wipes the host cache !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- cache-flush ---
CMD_NAME="cache-flush"
DESCRIPTION="[host_cache hook] Removes up to a given number or all cached host reservations."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "cache-flush", "service": [ "dhcp4" ], "arguments": 5 }'
# !!! DANGEROUS: Modifies the host cache !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- cache-get ---
CMD_NAME="cache-get"
DESCRIPTION="[host_cache hook] Returns the full content of the host cache."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "cache-get", "service": [ "dhcp4" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- cache-get-by-id ---
CMD_NAME="cache-get-by-id"
DESCRIPTION="[host_cache hook] Returns entries matching the given identifier from the host cache."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "cache-get-by-id", "service": [ "dhcp4" ], "arguments": { "hw-address": "01:02:03:04:05:06" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- cache-insert ---
CMD_NAME="cache-insert"
DESCRIPTION="[host_cache hook] Inserts a host into the cache."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "cache-insert", "service": [ "dhcp4" ], "arguments": { "hw-address": "aa:bb:cc:dd:ee:ff", "subnet-id": 1, "ip-address": "192.168.1.99" } }'
# !!! DANGEROUS: Modifies the host cache !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- cache-load ---
CMD_NAME="cache-load"
DESCRIPTION="[host_cache hook] Allows the contents of a file on disk to be loaded into an in-memory cache."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "cache-load", "service": [ "dhcp4" ], "arguments": "/path/on/server/to/kea-host-cache.json" }'
# !!! DANGEROUS: Wipes and reloads the host cache !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- cache-remove ---
CMD_NAME="cache-remove"
DESCRIPTION="[host_cache hook] Removes entries from the host cache."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "cache-remove", "service": [ "dhcp4" ], "arguments": { "ip-address": "192.168.1.99", "subnet-id": 1 } }'
# !!! DANGEROUS: Modifies the host cache !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- cache-size ---
CMD_NAME="cache-size"
DESCRIPTION="[host_cache hook] Returns the number of entries in the host cache."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "cache-size", "service": [ "dhcp4" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- cache-write ---
CMD_NAME="cache-write"
DESCRIPTION="[host_cache hook] Instructs Kea to write its host cache content to disk."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "cache-write", "service": [ "dhcp4" ], "arguments": "/tmp/host-cache-dump.json" }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- class-add ---
CMD_NAME="class-add"
DESCRIPTION="[class_cmds hook] Adds a new class to the existing server configuration."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "class-add", "service": [ "dhcp4" ], "arguments": { "client-classes": [ { "name": "new-test-class", "test": "vendor-class-identifier == '\''MSFT 5.0'\''" } ] } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- class-del ---
CMD_NAME="class-del"
DESCRIPTION="[class_cmds hook] Removes a client class from the server configuration."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "class-del", "service": [ "dhcp4" ], "arguments": { "name": "new-test-class" } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- class-get ---
CMD_NAME="class-get"
DESCRIPTION="[class_cmds hook] Returns detailed information about an existing client class."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "class-get", "service": [ "dhcp4" ], "arguments": { "name": "YOUR_CLASS_NAME" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- class-list ---
CMD_NAME="class-list"
DESCRIPTION="[class_cmds hook] Retrieves a list of all client classes from the server configuration."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "class-list", "service": [ "dhcp4" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- class-update ---
CMD_NAME="class-update"
DESCRIPTION="[class_cmds hook] Updates an existing client class in the server configuration."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "class-update", "service": [ "dhcp4" ], "arguments": { "client-classes": [ { "name": "YOUR_CLASS_NAME", "test": "vendor-class-identifier == '\''NEW_VALUE'\''" } ] } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- config-backend-pull ---
CMD_NAME="config-backend-pull"
DESCRIPTION="Forces an immediate update of the server using Config Backends."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "config-backend-pull", "service": [ "dhcp4" ] }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- config-get ---
CMD_NAME="config-get"
DESCRIPTION="Retrieves the current configuration used by the server."
SERVICE="ctrl-agent, dhcp-ddns, dhcp4, dhcp6"
PAYLOAD='{ "command": "config-get", "service": [ "dhcp4" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- config-hash-get ---
CMD_NAME="config-hash-get"
DESCRIPTION="Retrieves the hash of the current configuration used by the server."
SERVICE="ctrl-agent, dhcp-ddns, dhcp4, dhcp6"
PAYLOAD='{ "command": "config-hash-get", "service": [ "dhcp4" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- config-reload ---
CMD_NAME="config-reload"
DESCRIPTION="Instructs Kea to reload the configuration file that was used previously."
SERVICE="ctrl-agent, dhcp-ddns, dhcp4, dhcp6"
PAYLOAD='{ "command": "config-reload", "service": [ "dhcp4" ] }'
# !!! DANGEROUS: Overwrites any runtime configuration changes !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- config-set ---
CMD_NAME="config-set"
DESCRIPTION="Replaces the server's current configuration with the new one supplied in the arguments."
SERVICE="ctrl-agent, dhcp-ddns, dhcp4, dhcp6"
# You need to create a valid config file first, e.g., /tmp/new_kea_config.json
# CONFIG_TO_SET=$(cat /tmp/new_kea_config.json)
PAYLOAD="{ \"command\": \"config-set\", \"service\": [\"dhcp4\"], \"arguments\": $CONFIG_TO_SET }"
# !!! EXTREMELY DANGEROUS: Replaces entire server configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- config-test ---
CMD_NAME="config-test"
DESCRIPTION="Checks whether a new configuration is valid without applying it."
SERVICE="ctrl-agent, dhcp-ddns, dhcp4, dhcp6"
# You need to create a valid config file first, e.g., /tmp/test_kea_config.json
# CONFIG_TO_TEST=$(cat /tmp/test_kea_config.json)
PAYLOAD="{ \"command\": \"config-test\", \"service\": [\"dhcp4\"], \"arguments\": $CONFIG_TO_TEST }"
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- config-write ---
CMD_NAME="config-write"
DESCRIPTION="Writes the current in-memory configuration to a file on the server."
SERVICE="ctrl-agent, dhcp-ddns, dhcp4, dhcp6"
PAYLOAD='{ "command": "config-write", "service": [ "dhcp4" ], "arguments": { "filename": "/tmp/kea-runtime-config.json" } }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- dhcp-disable ---
CMD_NAME="dhcp-disable"
DESCRIPTION="Disables the DHCP service, making the server stop responding to DHCP queries."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "dhcp-disable", "service": [ "dhcp4" ] }'
# !!! DANGEROUS: Stops DHCP service !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- dhcp-enable ---
CMD_NAME="dhcp-enable"
DESCRIPTION="Enables the DHCP service."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "dhcp-enable", "service": [ "dhcp4" ] }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- extended-info4-upgrade ---
CMD_NAME="extended-info4-upgrade"
DESCRIPTION="[lease_query hook] Sanitizes and upgrades lease information in SQL databases for DHCPv4."
SERVICE="dhcp4"
PAYLOAD='{ "command": "extended-info4-upgrade", "service": [ "dhcp4" ] }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- extended-info6-upgrade ---
CMD_NAME="extended-info6-upgrade"
DESCRIPTION="[lease_query hook] Sanitizes and upgrades lease information in SQL databases for DHCPv6."
SERVICE="dhcp6"
PAYLOAD='{ "command": "extended-info6-upgrade", "service": [ "dhcp6" ] }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- gss-tsig-get ---
CMD_NAME="gss-tsig-get"
DESCRIPTION="[gss_tsig hook] Retrieves information about the specified GSS-TSIG server."
SERVICE="dhcp-ddns"
PAYLOAD='{ "command": "gss-tsig-get", "service": [ "dhcp-ddns" ], "arguments": { "server-id": "YOUR_SERVER_ID" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- gss-tsig-get-all ---
CMD_NAME="gss-tsig-get-all"
DESCRIPTION="[gss_tsig hook] Lists GSS-TSIG servers and keys."
SERVICE="dhcp-ddns"
PAYLOAD='{ "command": "gss-tsig-get-all", "service": [ "dhcp-ddns" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- gss-tsig-key-del ---
CMD_NAME="gss-tsig-key-del"
DESCRIPTION="[gss_tsig hook] Deletes the specified GSS-TSIG key."
SERVICE="dhcp-ddns"
PAYLOAD='{ "command": "gss-tsig-key-del", "service": [ "dhcp-ddns" ], "arguments": { "key-name": "YOUR_KEY_NAME" } }'
# !!! DANGEROUS: Modifies GSS-TSIG keys !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- gss-tsig-key-expire ---
CMD_NAME="gss-tsig-key-expire"
DESCRIPTION="[gss_tsig hook] Expires the specified GSS-TSIG key."
SERVICE="dhcp-ddns"
PAYLOAD='{ "command": "gss-tsig-key-expire", "service": [ "dhcp-ddns" ], "arguments": { "key-name": "YOUR_KEY_NAME" } }'
# !!! DANGEROUS: Modifies GSS-TSIG keys !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- gss-tsig-key-get ---
CMD_NAME="gss-tsig-key-get"
DESCRIPTION="[gss_tsig hook] Retrieves information about the specified GSS-TSIG key."
SERVICE="dhcp-ddns"
PAYLOAD='{ "command": "gss-tsig-key-get", "service": [ "dhcp-ddns" ], "arguments": { "key-name": "YOUR_KEY_NAME" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- gss-tsig-list ---
CMD_NAME="gss-tsig-list"
DESCRIPTION="[gss_tsig hook] Lists GSS-TSIG server IDs and key names."
SERVICE="dhcp-ddns"
PAYLOAD='{ "command": "gss-tsig-list", "service": [ "dhcp-ddns" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- gss-tsig-purge ---
CMD_NAME="gss-tsig-purge"
DESCRIPTION="[gss_tsig hook] Removes not usable GSS-TSIG keys for the specified server."
SERVICE="dhcp-ddns"
PAYLOAD='{ "command": "gss-tsig-purge", "service": [ "dhcp-ddns" ], "arguments": { "server-id": "YOUR_SERVER_ID" } }'
# !!! DANGEROUS: Modifies GSS-TSIG keys !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- gss-tsig-purge-all ---
CMD_NAME="gss-tsig-purge-all"
DESCRIPTION="[gss_tsig hook] Removes not usable GSS-TSIG keys."
SERVICE="dhcp-ddns"
PAYLOAD='{ "command": "gss-tsig-purge-all", "service": [ "dhcp-ddns" ] }'
# !!! DANGEROUS: Modifies GSS-TSIG keys !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- gss-tsig-rekey ---
CMD_NAME="gss-tsig-rekey"
DESCRIPTION="[gss_tsig hook] Unconditionally creates new GSS-TSIG keys for a specified DNS server."
SERVICE="dhcp-ddns"
PAYLOAD='{ "command": "gss-tsig-rekey", "service": [ "dhcp-ddns" ], "arguments": { "server-id": "YOUR_SERVER_ID" } }'
# !!! DANGEROUS: Modifies GSS-TSIG keys !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- gss-tsig-rekey-all ---
CMD_NAME="gss-tsig-rekey-all"
DESCRIPTION="[gss_tsig hook] Unconditionally creates new GSS-TSIG keys for all DNS servers."
SERVICE="dhcp-ddns"
PAYLOAD='{ "command": "gss-tsig-rekey-all", "service": [ "dhcp-ddns" ] }'
# !!! DANGEROUS: Modifies GSS-TSIG keys !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- ha-continue ---
CMD_NAME="ha-continue"
DESCRIPTION="[high_availability hook] Resumes the operation of a paused HA state machine."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "ha-continue", "service": [ "dhcp4" ], "arguments": { "server-name": "YOUR_SERVER_NAME" } }'
# !!! DANGEROUS: Modifies HA state !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- ha-heartbeat ---
CMD_NAME="ha-heartbeat"
DESCRIPTION="[high_availability hook] Retrieves the server's High Availability state and clock value."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "ha-heartbeat", "service": [ "dhcp4" ], "arguments": { "server-name": "YOUR_SERVER_NAME" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- ha-maintenance-cancel ---
CMD_NAME="ha-maintenance-cancel"
DESCRIPTION="[high_availability hook] Instructs a server in partner-in-maintenance to transition back to the previous state."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "ha-maintenance-cancel", "service": [ "dhcp4" ] }'
# !!! DANGEROUS: Modifies HA state !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- ha-maintenance-notify ---
CMD_NAME="ha-maintenance-notify"
DESCRIPTION="[high_availability hook] Internal command for HA partners to notify each other of maintenance state changes."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "ha-maintenance-notify", "service": [ "dhcp4" ], "arguments": { "cancel": true, "state": "ready" } }'
# !!! DANGEROUS: Modifies HA state !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- ha-maintenance-start ---
CMD_NAME="ha-maintenance-start"
DESCRIPTION="[high_availability hook] Instructs a server to enter maintenance mode, causing its partner to take over."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "ha-maintenance-start", "service": [ "dhcp4" ] }'
# !!! DANGEROUS: Modifies HA state !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- ha-reset ---
CMD_NAME="ha-reset"
DESCRIPTION="[high_availability hook] Resets the HA state machine of the server by transitioning it to the waiting state."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "ha-reset", "service": [ "dhcp4" ], "arguments": { "server-name": "YOUR_SERVER_NAME" } }'
# !!! DANGEROUS: Modifies HA state !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- ha-scopes ---
CMD_NAME="ha-scopes"
DESCRIPTION="[high_availability hook] Modifies the scope that the server is responsible for serving in HA mode."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "ha-scopes", "service": [ "dhcp4" ], "arguments": { "scopes": [ "HA_server1", "HA_server2" ], "server-name": "YOUR_SERVER_NAME" } }'
# !!! DANGEROUS: Modifies HA state !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- ha-sync ---
CMD_NAME="ha-sync"
DESCRIPTION="[high_availability hook] Instructs the server to synchronize its local lease database with the selected peer."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "ha-sync", "service": [ "dhcp4" ], "arguments": { "server-name": "YOUR_SERVER_NAME", "max-period": 60 } }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- ha-sync-complete-notify ---
CMD_NAME="ha-sync-complete-notify"
DESCRIPTION="[high_availability hook] Internal command for a server to notify its partner that lease sync is complete."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "ha-sync-complete-notify", "service": [ "dhcp4" ], "arguments": { "server-name": "YOUR_SERVER_NAME" } }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease4-add ---
CMD_NAME="lease4-add"
DESCRIPTION="[lease_cmds hook] Administratively adds a new IPv4 lease."
SERVICE="dhcp4"
PAYLOAD='{ "command": "lease4-add", "service": [ "dhcp4" ], "arguments": { "ip-address": "192.168.1.250", "hw-address": "0a:0b:0c:0d:0e:0f", "subnet-id": 1 } }'
# !!! DANGEROUS: Modifies lease database !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease4-del ---
CMD_NAME="lease4-del"
DESCRIPTION="[lease_cmds hook] Deletes a lease from the lease database."
SERVICE="dhcp4"
PAYLOAD='{ "command": "lease4-del", "service": [ "dhcp4" ], "arguments": { "ip-address": "192.168.1.250" } }'
# !!! DANGEROUS: Modifies lease database !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease4-get ---
CMD_NAME="lease4-get"
DESCRIPTION="[lease_cmds hook] Queries the lease database and retrieves an existing IPv4 lease."
SERVICE="dhcp4"
PAYLOAD='{ "command": "lease4-get", "service": [ "dhcp4" ], "arguments": { "ip-address": "YOUR_LEASED_IP" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease4-get-all ---
CMD_NAME="lease4-get-all"
DESCRIPTION="[lease_cmds hook] Retrieves all IPv4 leases or all leases for the specified set of subnets."
SERVICE="dhcp4"
PAYLOAD='{ "command": "lease4-get-all", "service": [ "dhcp4" ], "arguments": { "subnets": [ 1 ] } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease4-get-by-client-id ---
CMD_NAME="lease4-get-by-client-id"
DESCRIPTION="[lease_cmds hook] Retrieves all IPv4 leases with the specified client id."
SERVICE="dhcp4"
PAYLOAD='{ "command": "lease4-get-by-client-id", "service": [ "dhcp4" ], "arguments": { "client-id": "YOUR_CLIENT_ID" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease4-get-by-hostname ---
CMD_NAME="lease4-get-by-hostname"
DESCRIPTION="[lease_cmds hook] Retrieves all IPv4 leases with the specified hostname."
SERVICE="dhcp4"
PAYLOAD='{ "command": "lease4-get-by-hostname", "service": [ "dhcp4" ], "arguments": { "hostname": "your-hostname.example.com" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease4-get-by-hw-address ---
CMD_NAME="lease4-get-by-hw-address"
DESCRIPTION="[lease_cmds hook] Retrieves all IPv4 leases with the specified hardware address."
SERVICE="dhcp4"
PAYLOAD='{ "command": "lease4-get-by-hw-address", "service": [ "dhcp4" ], "arguments": { "hw-address": "YOUR_HW_ADDRESS" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease4-get-page ---
CMD_NAME="lease4-get-page"
DESCRIPTION="[lease_cmds hook] Retrieves all IPv4 leases by page."
SERVICE="dhcp4"
PAYLOAD='{ "command": "lease4-get-page", "service": [ "dhcp4" ], "arguments": { "limit": 100, "from": "start" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease4-resend-ddns ---
CMD_NAME="lease4-resend-ddns"
DESCRIPTION="[lease_cmds hook] Resends a request to kea-dhcp-ddns to update DNS for an existing lease."
SERVICE="dhcp4"
PAYLOAD='{ "command": "lease4-resend-ddns", "service": [ "dhcp4" ], "arguments": { "ip-address": "YOUR_LEASED_IP" } }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease4-update ---
CMD_NAME="lease4-update"
DESCRIPTION="[lease_cmds hook] Updates existing leases."
SERVICE="dhcp4"
PAYLOAD='{ "command": "lease4-update", "service": [ "dhcp4" ], "arguments": { "ip-address": "YOUR_LEASED_IP", "hostname": "new-hostname.example.org", "subnet-id": 1 } }'
# !!! DANGEROUS: Modifies lease database !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease4-wipe ---
CMD_NAME="lease4-wipe"
DESCRIPTION="[lease_cmds hook] Removes all leases associated with a given subnet."
SERVICE="dhcp4"
PAYLOAD='{ "command": "lease4-wipe", "service": [ "dhcp4" ], "arguments": { "subnet-id": 1 } }'
# !!! DANGEROUS: Wipes all leases in a subnet !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease4-write ---
CMD_NAME="lease4-write"
DESCRIPTION="[lease_cmds hook] Writes the IPv4 memfile lease database into a CSV file on the server."
SERVICE="dhcp4"
PAYLOAD='{ "command": "lease4-write", "service": [ "dhcp4" ], "arguments": { "filename": "/tmp/leases4.csv" } }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease6-add ---
CMD_NAME="lease6-add"
DESCRIPTION="[lease_cmds hook] Administratively creates a new IPv6 lease."
SERVICE="dhcp6"
PAYLOAD='{ "command": "lease6-add", "service": [ "dhcp6" ], "arguments": { "subnet-id": 1, "ip-address": "2001:db8::100", "duid": "00:01:00:01:ab:cd:ef:12:34:56", "iaid": 1234 } }'
# !!! DANGEROUS: Modifies lease database !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease6-bulk-apply ---
CMD_NAME="lease6-bulk-apply"
DESCRIPTION="[lease_cmds hook] Creates, updates, or deletes multiple IPv6 leases in a single transaction."
SERVICE="dhcp6"
PAYLOAD='{ "command": "lease6-bulk-apply", "service": [ "dhcp6" ], "arguments": { "deleted-leases": [ { "ip-address": "2001:db8::dead" } ], "leases": [ { "subnet-id": 1, "ip-address": "2001:db8::beef" } ] } }'
# !!! DANGEROUS: Modifies lease database !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease6-del ---
CMD_NAME="lease6-del"
DESCRIPTION="[lease_cmds hook] Deletes a lease from the lease database."
SERVICE="dhcp6"
PAYLOAD='{ "command": "lease6-del", "service": [ "dhcp6" ], "arguments": { "ip-address": "2001:db8::100" } }'
# !!! DANGEROUS: Modifies lease database !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease6-get ---
CMD_NAME="lease6-get"
DESCRIPTION="[lease_cmds hook] Queries the lease database and retrieves existing IPv6 leases."
SERVICE="dhcp6"
PAYLOAD='{ "command": "lease6-get", "service": [ "dhcp6" ], "arguments": { "ip-address": "YOUR_LEASED_IPV6", "type": "IA_NA" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease6-get-all ---
CMD_NAME="lease6-get-all"
DESCRIPTION="[lease_cmds hook] Retrieves all IPv6 leases or all leases for the specified set of subnets."
SERVICE="dhcp6"
PAYLOAD='{ "command": "lease6-get-all", "service": [ "dhcp6" ], "arguments": { "subnets": [ 1 ] } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease6-get-by-duid ---
CMD_NAME="lease6-get-by-duid"
DESCRIPTION="[lease_cmds hook] Retrieves all IPv6 leases with the specified DUID."
SERVICE="dhcp6"
PAYLOAD='{ "command": "lease6-get-by-duid", "service": [ "dhcp6" ], "arguments": { "duid": "YOUR_DUID" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease6-get-by-hostname ---
CMD_NAME="lease6-get-by-hostname"
DESCRIPTION="[lease_cmds hook] Retrieves all IPv6 leases with the specified hostname."
SERVICE="dhcp6"
PAYLOAD='{ "command": "lease6-get-by-hostname", "service": [ "dhcp6" ], "arguments": { "hostname": "your-ipv6-host.example.com" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease6-get-page ---
CMD_NAME="lease6-get-page"
DESCRIPTION="[lease_cmds hook] Retrieves all IPv6 leases by page."
SERVICE="dhcp6"
PAYLOAD='{ "command": "lease6-get-page", "service": [ "dhcp6" ], "arguments": { "limit": 100, "from": "start" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease6-resend-ddns ---
CMD_NAME="lease6-resend-ddns"
DESCRIPTION="[lease_cmds hook] Resends a request to kea-dhcp-ddns to update DNS for an existing IPv6 lease."
SERVICE="dhcp6"
PAYLOAD='{ "command": "lease6-resend-ddns", "service": [ "dhcp6" ], "arguments": { "ip-address": "YOUR_LEASED_IPV6" } }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease6-update ---
CMD_NAME="lease6-update"
DESCRIPTION="[lease_cmds hook] Updates existing IPv6 leases."
SERVICE="dhcp6"
PAYLOAD='{ "command": "lease6-update", "service": [ "dhcp6" ], "arguments": { "ip-address": "YOUR_LEASED_IPV6", "hostname": "new-hostname-ipv6.example.org", "subnet-id": 1 } }'
# !!! DANGEROUS: Modifies lease database !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease6-wipe ---
CMD_NAME="lease6-wipe"
DESCRIPTION="[lease_cmds hook] Removes all leases associated with a given IPv6 subnet."
SERVICE="dhcp6"
PAYLOAD='{ "command": "lease6-wipe", "service": [ "dhcp6" ], "arguments": { "subnet-id": 1 } }'
# !!! DANGEROUS: Wipes all leases in a subnet !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- lease6-write ---
CMD_NAME="lease6-write"
DESCRIPTION="[lease_cmds hook] Writes the IPv6 memfile lease database into a CSV file on the server."
SERVICE="dhcp6"
PAYLOAD='{ "command": "lease6-write", "service": [ "dhcp6" ], "arguments": { "filename": "/tmp/leases6.csv" } }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- leases-reclaim ---
CMD_NAME="leases-reclaim"
DESCRIPTION="Instructs the server to reclaim all expired leases immediately."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "leases-reclaim", "service": [ "dhcp4" ], "arguments": { "remove": true } }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- list-commands ---
CMD_NAME="list-commands"
DESCRIPTION="Retrieves a list of all commands supported by the server."
SERVICE="ctrl-agent, dhcp-ddns, dhcp4, dhcp6"
PAYLOAD='{ "command": "list-commands", "service": [ "dhcp4" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- network4-add ---
CMD_NAME="network4-add"
DESCRIPTION="[subnet_cmds hook] Adds a new shared network."
SERVICE="dhcp4"
PAYLOAD='{ "command": "network4-add", "service": [ "dhcp4" ], "arguments": { "shared-networks": [ { "name": "new-shared-net", "subnet4": [ { "id": 100, "subnet": "192.168.100.0/24", "pools": [{"pool": "192.168.100.10-192.168.100.200"}] } ] } ] } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- network4-del ---
CMD_NAME="network4-del"
DESCRIPTION="[subnet_cmds hook] Deletes existing shared networks."
SERVICE="dhcp4"
PAYLOAD='{ "command": "network4-del", "service": [ "dhcp4" ], "arguments": { "name": "new-shared-net" } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- network4-get ---
CMD_NAME="network4-get"
DESCRIPTION="[subnet_cmds hook] Retrieves detailed information about shared networks."
SERVICE="dhcp4"
PAYLOAD='{ "command": "network4-get", "service": [ "dhcp4" ], "arguments": { "name": "YOUR_SHARED_NETWORK_NAME" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- network4-list ---
CMD_NAME="network4-list"
DESCRIPTION="[subnet_cmds hook] Retrieves the full list of currently configured shared networks."
SERVICE="dhcp4"
PAYLOAD='{ "command": "network4-list", "service": [ "dhcp4" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- network4-subnet-add ---
CMD_NAME="network4-subnet-add"
DESCRIPTION="[subnet_cmds hook] Adds existing subnets to existing shared networks."
SERVICE="dhcp4"
PAYLOAD='{ "command": "network4-subnet-add", "service": [ "dhcp4" ], "arguments": { "name": "YOUR_SHARED_NETWORK_NAME", "id": 1 } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- network4-subnet-del ---
CMD_NAME="network4-subnet-del"
DESCRIPTION="[subnet_cmds hook] Removes a subnet from an existing shared network."
SERVICE="dhcp4"
PAYLOAD='{ "command": "network4-subnet-del", "service": [ "dhcp4" ], "arguments": { "name": "YOUR_SHARED_NETWORK_NAME", "id": 1 } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- network6-add ---
CMD_NAME="network6-add"
DESCRIPTION="[subnet_cmds hook] Adds a new IPv6 shared network."
SERVICE="dhcp6"
PAYLOAD='{ "command": "network6-add", "service": [ "dhcp6" ], "arguments": { "shared-networks": [ { "name": "new-ipv6-shared-net", "subnet6": [ { "id": 100, "subnet": "2001:db8:100::/64", "pools": [{"pool": "2001:db8:100::1-2001:db8:100::ff"}] } ] } ] } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- network6-del ---
CMD_NAME="network6-del"
DESCRIPTION="[subnet_cmds hook] Deletes existing IPv6 shared networks."
SERVICE="dhcp6"
PAYLOAD='{ "command": "network6-del", "service": [ "dhcp6" ], "arguments": { "name": "new-ipv6-shared-net" } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- network6-get ---
CMD_NAME="network6-get"
DESCRIPTION="[subnet_cmds hook] Retrieves detailed information about IPv6 shared networks."
SERVICE="dhcp6"
PAYLOAD='{ "command": "network6-get", "service": [ "dhcp6" ], "arguments": { "name": "YOUR_IPV6_SHARED_NETWORK_NAME" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- network6-list ---
CMD_NAME="network6-list"
DESCRIPTION="[subnet_cmds hook] Retrieves the full list of currently configured IPv6 shared networks."
SERVICE="dhcp6"
PAYLOAD='{ "command": "network6-list", "service": [ "dhcp6" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- network6-subnet-add ---
CMD_NAME="network6-subnet-add"
DESCRIPTION="[subnet_cmds hook] Adds existing IPv6 subnets to existing shared networks."
SERVICE="dhcp6"
PAYLOAD='{ "command": "network6-subnet-add", "service": [ "dhcp6" ], "arguments": { "name": "YOUR_IPV6_SHARED_NETWORK_NAME", "id": 1 } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- network6-subnet-del ---
CMD_NAME="network6-subnet-del"
DESCRIPTION="[subnet_cmds hook] Removes a subnet from an existing IPv6 shared network."
SERVICE="dhcp6"
PAYLOAD='{ "command": "network6-subnet-del", "service": [ "dhcp6" ], "arguments": { "name": "YOUR_IPV6_SHARED_NETWORK_NAME", "id": 1 } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- perfmon-control ---
CMD_NAME="perfmon-control"
DESCRIPTION="[perfmon hook] Enables/disables active monitoring and statistics reporting."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "perfmon-control", "service": [ "dhcp4" ], "arguments": { "enable-monitoring": true, "stats-mgr-reporting": false } }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- perfmon-get-all-durations ---
CMD_NAME="perfmon-get-all-durations"
DESCRIPTION="[perfmon hook] Fetches all monitored duration data currently held by Perfmon."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "perfmon-get-all-durations", "service": [ "dhcp4" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- All remote-* commands are skipped by default. They require DB_ARGS to be set correctly. ---
# --- You must uncomment them and ensure your DB_ARGS are valid. ---

# --- reservation-add ---
CMD_NAME="reservation-add"
DESCRIPTION="[host_cmds hook] Adds a new host reservation."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "reservation-add", "service": [ "dhcp4" ], "arguments": { "reservation": { "subnet-id": 1, "hw-address": "1a:2b:3c:4d:5e:6f", "ip-address": "192.168.1.150" } } }'
# !!! DANGEROUS: Modifies reservations !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- reservation-del ---
CMD_NAME="reservation-del"
DESCRIPTION="[host_cmds hook] Deletes an existing host reservation."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "reservation-del", "service": [ "dhcp4" ], "arguments": { "subnet-id": 1, "identifier-type": "hw-address", "identifier": "1a:2b:3c:4d:5e:6f" } }'
# !!! DANGEROUS: Modifies reservations !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- reservation-get ---
CMD_NAME="reservation-get"
DESCRIPTION="[host_cmds hook] Retrieves an existing host reservation."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "reservation-get", "service": [ "dhcp4" ], "arguments": { "subnet-id": 1, "identifier-type": "hw-address", "identifier": "1a:2b:3c:4d:5e:6f" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- reservation-get-all ---
CMD_NAME="reservation-get-all"
DESCRIPTION="[host_cmds hook] Retrieves all host reservations for a specified subnet."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "reservation-get-all", "service": [ "dhcp4" ], "arguments": { "subnet-id": 1 } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- reservation-get-by-address ---
CMD_NAME="reservation-get-by-address"
DESCRIPTION="[host_cmds hook] Retrieves all host reservations for a given IP address."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "reservation-get-by-address", "service": [ "dhcp4" ], "arguments": { "ip-address": "192.168.1.150" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- reservation-get-by-hostname ---
CMD_NAME="reservation-get-by-hostname"
DESCRIPTION="[host_cmds hook] Retrieves all host reservations for a specified hostname."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "reservation-get-by-hostname", "service": [ "dhcp4" ], "arguments": { "hostname": "my-reserved-host" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- reservation-get-by-id ---
CMD_NAME="reservation-get-by-id"
DESCRIPTION="[host_cmds hook] Retrieves all host reservations for a specified identifier."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "reservation-get-by-id", "service": [ "dhcp4" ], "arguments": { "identifier-type": "hw-address", "identifier": "YOUR_HW_ADDRESS" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- reservation-get-page ---
CMD_NAME="reservation-get-page"
DESCRIPTION="[host_cmds hook] Retrieves host reservations by page."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "reservation-get-page", "service": [ "dhcp4" ], "arguments": { "limit": 100 } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- reservation-update ---
CMD_NAME="reservation-update"
DESCRIPTION="[host_cmds hook] Updates an existing host reservation."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "reservation-update", "service": [ "dhcp4" ], "arguments": { "reservation": { "subnet-id": 1, "hw-address": "1a:2b:3c:4d:5e:6f", "ip-address": "192.168.1.150", "hostname": "updated-host" } } }'
# !!! DANGEROUS: Modifies reservations !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- server-tag-get ---
CMD_NAME="server-tag-get"
DESCRIPTION="Returns the server tag used by the server, essential for Config Backend."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "server-tag-get", "service": [ "dhcp4" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- shutdown ---
CMD_NAME="shutdown"
DESCRIPTION="Instructs the server to initiate its shutdown procedure."
SERVICE="ctrl-agent, dhcp-ddns, dhcp4, dhcp6"
PAYLOAD='{ "command": "shutdown", "service": [ "dhcp4" ] }'
# !!! EXTREMELY DANGEROUS: STOPS THE SERVER !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- stat-lease4-get ---
CMD_NAME="stat-lease4-get"
DESCRIPTION="[stat_cmds hook] Fetches lease statistics for a range of known IPv4 subnets."
SERVICE="dhcp4"
PAYLOAD='{ "command": "stat-lease4-get", "service": [ "dhcp4" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- stat-lease6-get ---
CMD_NAME="stat-lease6-get"
DESCRIPTION="[stat_cmds hook] Fetches lease statistics for a range of known IPv6 subnets."
SERVICE="dhcp6"
PAYLOAD='{ "command": "stat-lease6-get", "service": [ "dhcp6" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- statistic-get ---
CMD_NAME="statistic-get"
DESCRIPTION="Retrieves a single statistic."
SERVICE="dhcp-ddns, dhcp4, dhcp6"
PAYLOAD='{ "command": "statistic-get", "service": [ "dhcp4" ], "arguments": { "name": "pkt4-received" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- statistic-get-all ---
CMD_NAME="statistic-get-all"
DESCRIPTION="Retrieves all recorded statistics."
SERVICE="dhcp-ddns, dhcp4, dhcp6"
PAYLOAD='{ "command": "statistic-get-all", "service": [ "dhcp4" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- statistic-remove ---
CMD_NAME="statistic-remove"
DESCRIPTION="Deletes a single statistic."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "statistic-remove", "service": [ "dhcp4" ], "arguments": { "name": "pkt4-received" } }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- statistic-remove-all ---
CMD_NAME="statistic-remove-all"
DESCRIPTION="(Deprecated) This command deletes all statistics."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "statistic-remove-all", "service": [ "dhcp4" ] }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- statistic-reset ---
CMD_NAME="statistic-reset"
DESCRIPTION="Sets the specified statistic to its neutral value."
SERVICE="dhcp-ddns, dhcp4, dhcp6"
PAYLOAD='{ "command": "statistic-reset", "service": [ "dhcp4" ], "arguments": { "name": "pkt4-received" } }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- statistic-reset-all ---
CMD_NAME="statistic-reset-all"
DESCRIPTION="Sets all statistics to their neutral values."
SERVICE="dhcp-ddns, dhcp4, dhcp6"
PAYLOAD='{ "command": "statistic-reset-all", "service": [ "dhcp4" ] }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- statistic-sample-age-set ---
CMD_NAME="statistic-sample-age-set"
DESCRIPTION="Sets a time-based limit for a single statistic."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "statistic-sample-age-set", "service": [ "dhcp4" ], "arguments": { "name": "pkt4-received", "duration": 3600 } }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- statistic-sample-age-set-all ---
CMD_NAME="statistic-sample-age-set-all"
DESCRIPTION="Sets a time-based limit for all statistics."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "statistic-sample-age-set-all", "service": [ "dhcp4" ], "arguments": { "duration": 3600 } }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- statistic-sample-count-set ---
CMD_NAME="statistic-sample-count-set"
DESCRIPTION="Sets a size-based limit for a single statistic."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "statistic-sample-count-set", "service": [ "dhcp4" ], "arguments": { "name": "pkt4-received", "max-samples": 1000 } }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- statistic-sample-count-set-all ---
CMD_NAME="statistic-sample-count-set-all"
DESCRIPTION="Sets a size-based limit for all statistics."
SERVICE="dhcp4, dhcp6"
PAYLOAD='{ "command": "statistic-sample-count-set-all", "service": [ "dhcp4" ], "arguments": { "max-samples": 1000 } }'
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- status-get ---
CMD_NAME="status-get"
DESCRIPTION="Returns server's runtime information."
SERVICE="ctrl-agent, dhcp-ddns, dhcp4, dhcp6"
PAYLOAD='{ "command": "status-get", "service": [ "dhcp4" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet4-add ---
CMD_NAME="subnet4-add"
DESCRIPTION="[subnet_cmds hook] Creates and adds a new IPv4 subnet to the existing server configuration."
SERVICE="dhcp4"
PAYLOAD='{ "command": "subnet4-add", "service": [ "dhcp4" ], "arguments": { "subnet4": [ { "id": 99, "subnet": "192.168.99.0/24", "pools": [{"pool": "192.168.99.10-192.168.99.200"}] } ] } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet4-del ---
CMD_NAME="subnet4-del"
DESCRIPTION="[subnet_cmds hook] Removes an IPv4 subnet from the server's configuration."
SERVICE="dhcp4"
PAYLOAD='{ "command": "subnet4-del", "service": [ "dhcp4" ], "arguments": { "id": 99 } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet4-delta-add ---
CMD_NAME="subnet4-delta-add"
DESCRIPTION="[subnet_cmds hook] Updates (adds or overwrites) parts of a single IPv4 subnet."
SERVICE="dhcp4"
PAYLOAD='{ "command": "subnet4-delta-add", "service": [ "dhcp4" ], "arguments": { "subnet4": [ { "id": 1, "valid-lifetime": 86400 } ] } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet4-delta-del ---
CMD_NAME="subnet4-delta-del"
DESCRIPTION="[subnet_cmds hook] Updates (removes) parts of a single IPv4 subnet."
SERVICE="dhcp4"
PAYLOAD='{ "command": "subnet4-delta-del", "service": [ "dhcp4" ], "arguments": { "subnet4": [ { "id": 1, "valid-lifetime": null } ] } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet4-get ---
CMD_NAME="subnet4-get"
DESCRIPTION="[subnet_cmds hook] Retrieves detailed information about the specified IPv4 subnet."
SERVICE="dhcp4"
PAYLOAD='{ "command": "subnet4-get", "service": [ "dhcp4" ], "arguments": { "id": 1 } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet4-list ---
CMD_NAME="subnet4-list"
DESCRIPTION="[subnet_cmds hook] Lists all currently configured IPv4 subnets."
SERVICE="dhcp4"
PAYLOAD='{ "command": "subnet4-list", "service": [ "dhcp4" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet4-select-test ---
CMD_NAME="subnet4-select-test"
DESCRIPTION="Returns the result of DHCPv4 subnet selection for given parameters."
SERVICE="dhcp4"
PAYLOAD='{ "command": "subnet4-select-test", "service": [ "dhcp4" ], "arguments": { "remote": "192.168.1.1" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet4-update ---
CMD_NAME="subnet4-update"
DESCRIPTION="[subnet_cmds hook] Updates (overwrites) a single IPv4 subnet."
SERVICE="dhcp4"
PAYLOAD='{ "command": "subnet4-update", "service": [ "dhcp4" ], "arguments": { "subnet4": [ { "id": 1, "subnet": "192.168.1.0/24", "pools": [{"pool": "192.168.1.100-192.168.1.200"}] } ] } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet4o6-select-test ---
CMD_NAME="subnet4o6-select-test"
DESCRIPTION="Returns the result of DHCPv4o6 subnet selection for given parameters."
SERVICE="dhcp4"
PAYLOAD='{ "command": "subnet4o6-select-test", "service": [ "dhcp4" ], "arguments": { "remote": "2001:db8::1" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet6-add ---
CMD_NAME="subnet6-add"
DESCRIPTION="[subnet_cmds hook] Creates and adds a new IPv6 subnet."
SERVICE="dhcp6"
PAYLOAD='{ "command": "subnet6-add", "service": [ "dhcp6" ], "arguments": { "subnet6": [ { "id": 99, "subnet": "2001:db8:99::/64", "pools": [{"pool": "2001:db8:99::1-2001:db8:99::ff"}] } ] } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet6-del ---
CMD_NAME="subnet6-del"
DESCRIPTION="[subnet_cmds hook] Removes an IPv6 subnet from the server's configuration."
SERVICE="dhcp6"
PAYLOAD='{ "command": "subnet6-del", "service": [ "dhcp6" ], "arguments": { "id": 99 } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet6-delta-add ---
CMD_NAME="subnet6-delta-add"
DESCRIPTION="[subnet_cmds hook] Updates (adds or overwrites) parts of a single IPv6 subnet."
SERVICE="dhcp6"
PAYLOAD='{ "command": "subnet6-delta-add", "service": [ "dhcp6" ], "arguments": { "subnet6": [ { "id": 1, "valid-lifetime": 86400 } ] } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet6-delta-del ---
CMD_NAME="subnet6-delta-del"
DESCRIPTION="[subnet_cmds hook] Updates (removes) parts of a single IPv6 subnet."
SERVICE="dhcp6"
PAYLOAD='{ "command": "subnet6-delta-del", "service": [ "dhcp6" ], "arguments": { "subnet6": [ { "id": 1, "valid-lifetime": null } ] } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet6-get ---
CMD_NAME="subnet6-get"
DESCRIPTION="[subnet_cmds hook] Retrieves detailed information about the specified IPv6 subnet."
SERVICE="dhcp6"
PAYLOAD='{ "command": "subnet6-get", "service": [ "dhcp6" ], "arguments": { "id": 1 } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet6-list ---
CMD_NAME="subnet6-list"
DESCRIPTION="[subnet_cmds hook] Lists all currently configured IPv6 subnets."
SERVICE="dhcp6"
PAYLOAD='{ "command": "subnet6-list", "service": [ "dhcp6" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet6-select-test ---
CMD_NAME="subnet6-select-test"
DESCRIPTION="Returns the result of DHCPv6 subnet selection for given parameters."
SERVICE="dhcp6"
PAYLOAD='{ "command": "subnet6-select-test", "service": [ "dhcp6" ], "arguments": { "remote": "fe80::1" } }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- subnet6-update ---
CMD_NAME="subnet6-update"
DESCRIPTION="[subnet_cmds hook] Updates (overwrites) a single IPv6 subnet."
SERVICE="dhcp6"
PAYLOAD='{ "command": "subnet6-update", "service": [ "dhcp6" ], "arguments": { "subnet6": [ { "id": 1, "subnet": "2001:db8:1::/64", "pools": [{"pool": "2001:db8:1::100-2001:db8:1::200"}] } ] } }'
# !!! DANGEROUS: Modifies configuration !!!
# execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"

# --- version-get ---
CMD_NAME="version-get"
DESCRIPTION="Returns extended information about the Kea version that is running."
SERVICE="ctrl-agent, dhcp-ddns, dhcp4, dhcp6"
PAYLOAD='{ "command": "version-get", "service": [ "dhcp4" ] }'
execute_kea_command "$CMD_NAME" "$PAYLOAD" "$DESCRIPTION" "$SERVICE"


echo
echo "===================================================================================="
echo "      Master Script Execution Finished"
echo "      All command templates are present in this script."
echo "      Uncomment and edit them carefully one by one to test."
echo "===================================================================================="

exit 0