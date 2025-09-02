#!/bin/bash
#
# debug.sh
#
# This script is a flexible debugging tool to run any vppctl command inside
# one of the running containers. It simplifies the process of inspecting
# the VPP state.

# Exit immediately if any command fails.
set -e

# The first argument is the container name, the rest are the vppctl command.
CONTAINER=$1
shift

# Check if the user provided the necessary arguments.
if [ -z "$CONTAINER" ] || [ -z "$1" ]; then
  echo "Usage: $0 <container_name> <vppctl_command_with_args>"
  echo
  echo "Example Verifications:"
  echo "  $0 aws_vpp show nat44 sessions"
  echo "  $0 gcp_vpp show ipsec sa"
  echo "  $0 aws_vpp show vxlan tunnel"
  echo "  $0 gcp_vpp show int"
  echo "  $0 gcp_vpp trace add af-packet-input 10"
  echo "  $0 gcp_vpp show trace"
  exit 1
fi

echo "--- Running 'vppctl $@' in container '$CONTAINER' ---"
# Execute the vppctl command inside the specified container.
docker exec "$CONTAINER" vppctl "$@"