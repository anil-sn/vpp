#!/usr/bin/env python3
#
# test_fragmentation.py - VPP Fragmentation End-to-End Test Suite
#
# This script automates the process of verifying that VPP is correctly
# fragmenting large IPsec packets when the MTU is exceeded. It incorporates
# traffic generation, multi-point packet capture, and results analysis.
#
# Prerequisites:
#   - Python 3
#   - Scapy library: pip install scapy
#   - Must be run with sudo/root privileges.

import subprocess
import time
import os
import sys
import argparse

# --- Scapy Import ---
try:
    from scapy.all import IP, UDP, VXLAN, Raw, send, rdpcap
except ImportError:
    pass

# --- Configuration ---
AWS_VPP_IP = "192.168.1.2"
GCP_VPP_IP = "192.168.1.3"
AWS_CONTAINER = "aws_vpp"
GCP_CONTAINER = "gcp_vpp"
BRIDGE_IF = "br0"
AWS_BR_IF = "aws-br"
AWS_PHY_IF = "aws-phy"
VXLAN_PORT = 4789
LARGE_PACKET_PAYLOAD_SIZE = 1400

# --- Utility Functions ---
def log_info(msg): print(f"\n\033[1;34m--- {msg} ---\033[0m")
def log_success(msg): print(f"\033[1;32m✓ SUCCESS:\033[0m {msg}")
def log_error(msg): print(f"\033[1;31m✗ FAILURE:\033[0m {msg}")

def check_root():
    if os.geteuid() != 0:
        log_error("This script must be run as root or with sudo.")
        sys.exit(1)

def run_command(command, check=True, capture_output=False, text=False):
    return subprocess.run(command, shell=True, check=check, capture_output=capture_output, text=text)

# --- Test Functions ---

def setup_environment():
    log_info("Resetting VPP test environment")
    print("Running cleanup.sh...")
    run_command("sudo bash ./cleanup.sh", capture_output=True)
    print("Running run_vpp_test.sh...")
    run_command("sudo bash ./run_vpp_test.sh", capture_output=True)
    log_success("Environment is clean and running.")

def configure_mtus():
    log_info("Configuring MTUs to test fragmentation")
    # 1. Enable Jumbo frames on the entire kernel path to VPP
    run_command(f"sudo ip link set {BRIDGE_IF} mtu 9000")
    run_command(f"sudo ip link set {AWS_BR_IF} mtu 9000")
    run_command(f"sudo docker exec {AWS_CONTAINER} ip link set {AWS_PHY_IF} mtu 9000")
    log_success("Jumbo frames enabled on kernel path to VPP.")

    # 2. ** FIX: Sync VPP's PHYSICAL interface MTU to ACCEPT the jumbo frames **
    run_command(f"./debug.sh {AWS_CONTAINER} set interface mtu packet 9000 host-aws-phy", capture_output=True)
    log_success("VPP physical interface MTU synced to accept jumbo frames.")

    # 3. ** FIX: Set the MTU on the LOGICAL tunnel interface to TRIGGER fragmentation **
    run_command(f"./debug.sh {AWS_CONTAINER} set interface mtu packet 1400 ipip0", capture_output=True)
    log_success("VPP IPsec tunnel MTU set to 1400 to trigger fragmentation.")

def build_large_packet():
    large_payload = b'\x41' * LARGE_PACKET_PAYLOAD_SIZE
    netflow_payload = b'\x00\x05' + b'\x00' * 46
    inner_packet = IP(src="10.1.1.1", dst="10.10.10.10") / UDP(sport=12345, dport=2055) / Raw(load=netflow_payload + large_payload)
    vxlan_packet = IP(dst=AWS_VPP_IP) / UDP(sport=12345, dport=VXLAN_PORT) / VXLAN(vni=100, flags=0x08) / inner_packet
    return vxlan_packet

def send_traffic(packet, duration_secs=4):
    log_info(f"Generating large packet traffic for {duration_secs} seconds...")
    end_time = time.time() + duration_secs
    count = 0
    # FIX: Clean output formatting
    sys.stdout.write("Sending packets: ")
    sys.stdout.flush()
    with open(os.devnull, 'w') as devnull:
        original_stderr = sys.stderr
        sys.stderr = devnull
        try:
            while time.time() < end_time:
                send(packet, iface=BRIDGE_IF, verbose=0)
                count += 1
                sys.stdout.write(".")
                sys.stdout.flush()
                time.sleep(0.5)
        finally:
            sys.stderr = original_stderr
    print()
    log_success(f"Traffic generation complete. Sent {count} large packets.")
    return count

def analyze_results(sent_count):
    log_info("Analyzing captured traffic and VPP state")
    all_passed = True

    try:
        packets = rdpcap('/tmp/tcpdump_1_aws_in.pcap')
        pkt_size = len(packets[0]) if packets else 0
        if pkt_size > 1500:
            log_success(f"Large VXLAN packet (size {pkt_size}) was sent to aws_vpp.")
        else:
            log_error(f"Large VXLAN packet was NOT sent. Size: {pkt_size}.")
            all_passed = False
    except Exception:
        log_error("Capture file for aws_vpp ingress is empty or missing.")
        all_passed = False

    try:
        packets = rdpcap('/tmp/tcpdump_2_aws_out.pcap')
        frag_count = sum(1 for p in packets if p.haslayer(IP) and (p[IP].flags == 'MF' or p[IP].frag > 0))
        if frag_count >= sent_count * 2:
            log_success(f"aws_vpp sent {frag_count} fragmented ESP packets.")
        else:
            log_error(f"aws_vpp did NOT send enough fragmented ESP packets. Found {frag_count}.")
            all_passed = False
    except Exception:
        log_error("Capture file for aws_vpp egress is empty or missing.")
        all_passed = False

    try:
        time.sleep(1)
        result = run_command(f"./debug.sh {GCP_CONTAINER} show int", capture_output=True, text=True)
        reassembled_pkts = 0
        lines = result.stdout.splitlines()
        for i, line in enumerate(lines):
            if 'tap0' in line and 'rx packets' in lines[i+1]:
                reassembled_pkts = int(lines[i+1].split()[-1])
                break
        if reassembled_pkts >= sent_count:
            log_success(f"gcp_vpp reassembled the fragments. Final count on tap0: {reassembled_pkts} packets.")
        else:
            log_error(f"gcp_vpp did NOT reassemble fragments correctly. Expected >= {sent_count}, found {reassembled_pkts} on tap0.")
            all_passed = False
    except Exception as e:
        log_error(f"Error getting gcp_vpp reassembly stats: {e}")
        all_passed = False

    return all_passed

def main():
    check_root()
    if 'scapy' not in sys.modules:
        log_error("Scapy is not installed. Please run: sudo pip install scapy")
        sys.exit(1)

    parser = argparse.ArgumentParser(description="VPP Fragmentation End-to-End Test Suite.")
    parser.add_argument('--skip-setup', action='store_true', help='Skip environment cleanup and setup.')
    args = parser.parse_args()

    tcpdump_procs = []
    try:
        if not args.skip_setup:
            setup_environment()
        else:
            log_info("Skipping environment setup as requested.")

        configure_mtus()

        log_info("Starting tcpdump listeners at all key points")
        p1 = subprocess.Popen(f"sudo tcpdump -i {BRIDGE_IF} -n 'dst {AWS_VPP_IP} and udp port {VXLAN_PORT}' -c {5} -w /tmp/tcpdump_1_aws_in.pcap", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        p2 = subprocess.Popen(f"sudo tcpdump -i {AWS_BR_IF} -n 'src {AWS_VPP_IP} and proto esp' -c {10} -w /tmp/tcpdump_2_aws_out.pcap", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        tcpdump_procs = [p1, p2]
        time.sleep(3)

        large_packet = build_large_packet()
        sent_count = send_traffic(large_packet)
        time.sleep(3)

        for p in tcpdump_procs:
            try: p.terminate()
            except ProcessLookupError: pass

        passed = analyze_results(sent_count)

        if passed:
            log_info("\033[1;42m END-TO-END FRAGMENTATION TEST PASSED \033[0m")
        else:
            log_info("\033[1;41m END-TO-END FRAGMENTATION TEST FAILED \033[0m")

    finally:
        log_info("Cleaning up...")
        for p in tcpdump_procs:
            if p.poll() is None: p.kill()
        run_command("rm -f /tmp/tcpdump_*.pcap", check=False)
        print("Cleanup complete.")

if __name__ == "__main__":
    main()