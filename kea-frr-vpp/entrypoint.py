#!/usr/bin/env python3

import os
import sys
import subprocess
import signal
import time
import shutil

# --- Global Variables ---
# List to keep track of all running child processes
processes = []
ROLE = os.environ.get("ROLE")

# --- Graceful Shutdown Handler ---
def signal_handler(signum, frame):
    """
    Handles SIGTERM and SIGINT to gracefully shut down all child processes.
    """
    print(f"\nReceived signal {signum}, shutting down services...")
    # Terminate all processes in reverse order of startup
    for p in reversed(processes):
        if p.poll() is None:  # Check if the process is still running
            print(f" - Terminating process {p.pid} ({p.args[0]})...")
            p.terminate()
            try:
                p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                print(f"   - Process {p.pid} did not terminate, killing.")
                p.kill()
    print("All services stopped.")
    sys.exit(0)

# --- Helper Functions ---
def start_process(command, name):
    """Starts a process and adds it to the global list."""
    print(f"Starting {name}...")
    try:
        proc = subprocess.Popen(command, shell=False)
        processes.append(proc)
        print(f" - {name} started with PID {proc.pid}")
        return proc
    except FileNotFoundError:
        print(f"ERROR: Command not found for {name}: {command[0]}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: Failed to start {name}: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    """
    Main orchestration function.
    """
    # 1. Validate Role
    if not ROLE or ROLE not in ["bng", "r1", "r2"]:
        print(f"ERROR: Invalid or missing ROLE environment variable. Must be 'bng', 'r1', or 'r2'.", file=sys.stderr)
        sys.exit(1)
    print(f"--- Initializing container for ROLE: {ROLE} ---")

    # 2. Copy Role-Specific Configs
    print("Configuring role-specific files...")
    # FRR Config
    src_frr = f"/frr_configs/{ROLE}.conf"
    dest_frr = "/etc/frr/frr.conf"
    try:
        shutil.copy(src_frr, dest_frr)
        print(f" - Copied {src_frr} to {dest_frr}")
    except FileNotFoundError:
        print(f"ERROR: FRR config not found for role {ROLE} at {src_frr}", file=sys.stderr)
        sys.exit(1)
        
    # Kea Configs
    for service in ["kea-dhcp4", "kea-dhcp6"]:
        src_kea = f"/kea_configs/{ROLE}/{service}.conf"
        dest_kea = f"/etc/kea/{service}.conf"
        try:
            shutil.copy(src_kea, dest_kea)
            print(f" - Copied {src_kea} to {dest_kea}")
        except FileNotFoundError:
            print(f"ERROR: Kea config not found for role {ROLE} at {src_kea}", file=sys.stderr)
            sys.exit(1)

    # 3. Start Core Daemons
    start_process(["/usr/lib/frr/frrinit.sh", "start"], "FRR")
    start_process(["/usr/bin/vpp", "-c", "/etc/vpp/startup.conf"], "VPP")
    
    # 4. Wait for VPP and Apply Config
    vpp_api_socket = "/run/vpp/cli.sock"
    print(f"Waiting for VPP API socket at {vpp_api_socket}...")
    for _ in range(10): # Wait up to 10 seconds
        if os.path.exists(vpp_api_socket):
            print(" - VPP API socket is ready.")
            break
        time.sleep(1)
    else:
        print("ERROR: VPP API socket did not appear in time.", file=sys.stderr)
        sys.exit(1)

    vpp_config_file = f"/vpp_configs/{ROLE}.vpp"
    print(f"Applying VPP configuration from {vpp_config_file}...")
    try:
        # Use vppctl to execute the config file
        subprocess.run(["vppctl", "exec", vpp_config_file], check=True, capture_output=True, text=True)
    except FileNotFoundError:
        print(f"ERROR: VPP config not found for role {ROLE} at {vpp_config_file}", file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"ERROR: Failed to apply VPP configuration.", file=sys.stderr)
        print(f"STDOUT:\n{e.stdout}", file=sys.stderr)
        print(f"STDERR:\n{e.stderr}", file=sys.stderr)
        sys.exit(1)

    # 5. Start Kea Daemons
    start_process(["/usr/sbin/kea-dhcp4", "-c", f"/etc/kea/kea-dhcp4.conf"], "Kea-DHCP4")
    start_process(["/usr/sbin/kea-dhcp6", "-c", f"/etc/kea/kea-dhcp6.conf"], "Kea-DHCP6")
    
    # 6. Monitor Processes
    print("\n--- Startup complete. Monitoring services. ---")
    while True:
        try:
            # Wait for any child process to exit
            pid, exit_status = os.wait()
            print(f"\n!!! Service with PID {pid} has exited with status {exit_status} !!!", file=sys.stderr)
            # Find which process it was
            for p in processes:
                if p.pid == pid:
                    print(f" - The failed service was: {p.args[0]}", file=sys.stderr)
                    break
            # A service has failed, trigger shutdown of the container
            print("Shutting down container due to service failure.", file=sys.stderr)
            # The signal_handler will take care of the rest
            os.kill(os.getpid(), signal.SIGTERM)

        except KeyboardInterrupt:
            # This handles Ctrl+C in an interactive session
            os.kill(os.getpid(), signal.SIGINT)
        except Exception as e:
            print(f"An unexpected error occurred in monitoring loop: {e}", file=sys.stderr)
            os.kill(os.getpid(), signal.SIGTERM)


if __name__ == "__main__":
    # Register signal handlers
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    main()