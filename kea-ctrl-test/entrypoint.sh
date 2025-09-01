#!/bin/bash
#
# Robust entrypoint for running multiple Kea services.
# We explicitly use /bin/bash because this script uses 'wait -n',
# a bash-specific feature not available in /bin/sh (dash).
#
set -e

# --- Graceful Shutdown Handler ---
# This function will be called when the script receives SIGTERM or SIGINT.
term_handler() {
  echo "Receiving signal, shutting down all Kea services..."
  # Sending SIGTERM to process group 0 sends the signal to all processes
  # in the script's process group, including all backgrounded children.
  kill -SIGTERM 0
  # Wait for all background processes to complete.
  wait
  echo "All services stopped."
  exit 0
}

# Trap SIGTERM (sent by `docker stop`) and SIGINT (sent by Ctrl+C)
trap 'term_handler' INT TERM

# --- Runtime Directory Setup ---
# Create the runtime directory for sockets and set its permissions.
# This is crucial because the directory is on a tmpfs and needs to be
# created every time the container starts.
mkdir -p /var/run/kea
chown _kea:_kea /var/run/kea

# --- Service Startup ---
echo "Starting Kea services..."

# Start each service passed as an argument in the background.
# The `&` is crucial.
for service in "$@"
do
    case "$service" in
        kea-dhcp4|kea-dhcp6)
            echo " - Starting $service as root"
            /usr/sbin/$service -c /etc/kea/$service.conf &
            ;;
        kea-ctrl-agent)
            echo " - Starting $service as root"
            /usr/sbin/$service -c /etc/kea/$service.conf &
            ;;
        *)
            echo "ERROR: Unknown service specified: $service"
            exit 1
            ;;
    esac
done

# --- Wait for services ---
# The `wait -n` command waits for the *next* background job to exit.
# The loop ensures the script stays alive as long as any service is running.
# When a service dies, the loop exits, and the script terminates,
# which in turn stops the container.
echo "All Kea services started. Monitoring processes..."
while true; do
  wait -n
  # When a process exits, check the exit code.
  EXIT_CODE=$?
  echo "A Kea service has exited with code ${EXIT_CODE}. Shutting down container."
  # Trigger the shutdown handler to clean up other processes.
  term_handler
done