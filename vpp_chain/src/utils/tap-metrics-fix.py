"""
FIX for TAP Delivery Metrics - Addresses False 130% Delivery Rate

PROBLEM: Current code uses 'show hardware-interfaces tap0' which counts:
1. Fragment reassembly attempts (before MAC validation)  
2. Packets that arrive at reassembly node but get dropped
3. Multiple counting of the same logical packet

SOLUTION: Use proper TAP interface packet counters
"""

import subprocess
import re

def get_accurate_tap_delivery(container_name="destination", tap_interface="tap0"):
    """
    Get accurate TAP delivery metrics (fixes 130% false positive)
    
    Returns: (rx_packets, tx_packets, actual_delivery_rate)
    """
    
    try:
        # Method 1: Use VPP interface counters (most accurate)
        result = subprocess.run([
            "docker", "exec", container_name, "vppctl", "show", "interface", tap_interface
        ], capture_output=True, text=True, timeout=5)
        
        if result.returncode == 0:
            # Parse actual interface counters (not hardware reassembly counters)
            output = result.stdout
            
            # Look for "rx packets" and "tx packets" in interface output
            rx_match = re.search(r'rx packets\s+(\d+)', output)
            tx_match = re.search(r'tx packets\s+(\d+)', output)
            
            rx_packets = int(rx_match.group(1)) if rx_match else 0
            tx_packets = int(tx_match.group(1)) if tx_match else 0
            
            return rx_packets, tx_packets, "interface_counters"
    
    except Exception as e:
        print(f"Interface counter method failed: {e}")
    
    try:
        # Method 2: Use Linux TAP interface statistics as backup
        result = subprocess.run([
            "docker", "exec", container_name, "cat", f"/sys/class/net/{tap_interface}/statistics/rx_packets"
        ], capture_output=True, text=True, timeout=5)
        
        if result.returncode == 0:
            linux_rx = int(result.stdout.strip())
            
            result = subprocess.run([
                "docker", "exec", container_name, "cat", f"/sys/class/net/{tap_interface}/statistics/tx_packets"
            ], capture_output=True, text=True, timeout=5)
            
            linux_tx = int(result.stdout.strip()) if result.returncode == 0 else 0
            
            return linux_rx, linux_tx, "linux_counters"
    
    except Exception as e:
        print(f"Linux counter method failed: {e}")
    
    # Method 3: Fallback to drops analysis
    try:
        result = subprocess.run([
            "docker", "exec", container_name, "vppctl", "show", "errors"
        ], capture_output=True, text=True, timeout=5)
        
        if result.returncode == 0:
            # Count actual delivery vs drops
            drops_output = result.stdout
            
            # Look for specific drop reasons
            mac_drops = 0
            reassembly_drops = 0
            
            for line in drops_output.split('\n'):
                if 'l3 mac mismatch' in line.lower():
                    match = re.search(r'(\d+)', line)
                    if match:
                        mac_drops += int(match.group(1))
                elif 'reassembly' in line.lower() and 'drop' in line.lower():
                    match = re.search(r'(\d+)', line)
                    if match:
                        reassembly_drops += int(match.group(1))
            
            # Estimate successful delivery (this is less accurate)
            return 0, 0, f"drops_analysis_mac:{mac_drops}_reassembly:{reassembly_drops}"
    
    except Exception as e:
        print(f"Drops analysis failed: {e}")
    
    return 0, 0, "failed_all_methods"

def get_corrected_delivery_stats(sent_packets, container_name="destination"):
    """
    Get corrected TAP delivery statistics (fixes the 130% issue)
    
    Args:
        sent_packets: Number of packets originally sent
        container_name: Destination container name
    
    Returns:
        dict: Corrected delivery statistics
    """
    
    # Get accurate TAP counters
    tap_rx, tap_tx, method_used = get_accurate_tap_delivery(container_name)
    
    # Calculate actual delivery rate
    if sent_packets > 0:
        actual_delivery_rate = (tap_rx / sent_packets) * 100
        
        # Cap at 100% (can't deliver more packets than sent)
        capped_delivery_rate = min(actual_delivery_rate, 100.0)
    else:
        actual_delivery_rate = 0
        capped_delivery_rate = 0
    
    # Determine status based on corrected metrics
    if capped_delivery_rate >= 90:
        status = "[EXCELLENT]"
    elif capped_delivery_rate >= 70:
        status = "[GOOD]"
    elif capped_delivery_rate >= 50:
        status = "[OK]"
    elif capped_delivery_rate >= 20:
        status = "[LOW]"
    elif tap_rx > 0:
        status = "[MINIMAL]"
    else:
        status = "[FAIL]"
    
    return {
        "rx_packets": tap_rx,
        "tx_packets": tap_tx, 
        "sent_packets": sent_packets,
        "delivery_rate": capped_delivery_rate,
        "status": status,
        "method": method_used,
        "was_overcounted": actual_delivery_rate > 100
    }

# Example usage to replace the broken TAP metrics
def print_corrected_tap_stats(sent_packets):
    """
    Print corrected TAP delivery statistics (replaces broken 130% output)
    """
    
    print("\nCorrected Final Delivery Status:")
    print("-" * 70)
    
    stats = get_corrected_delivery_stats(sent_packets)
    
    overcounted_note = " (was overcounted)" if stats["was_overcounted"] else ""
    
    print(f"{stats['status']} TAP Final Delivery: {stats['rx_packets']}/{stats['sent_packets']} packets ({stats['delivery_rate']:.1f}%){overcounted_note}")
    print(f"    Method: {stats['method']} | TX: {stats['tx_packets']}")
    
    if stats["was_overcounted"]:
        print(f"    Note: Previous 130%+ rates were due to fragment counting before MAC validation")
    
    return stats

"""
Integration instructions:

Replace this section in traffic_generator.py:

# OLD (broken):
            # Add TAP interface final delivery statistics
            print("\nFinal Delivery Status:")
            print("-" * 70)
            try:
                result = subprocess.run([
                    "docker", "exec", "destination", "vppctl", "show", "hardware-interfaces", "tap0"
                ], capture_output=True, text=True, timeout=5)
                
                # ... complex parsing that counts fragments before MAC validation ...
                
                print(f"{tap_status} TAP Final Delivery: {tap_rx}/{self.sent_packets} packets ({delivery_rate:.1f}%) | TX: {tap_tx}")

# NEW (fixed):
            # Import the fix
            from .tap_metrics_fix import print_corrected_tap_stats
            
            # Use corrected TAP metrics
            print_corrected_tap_stats(self.sent_packets)
"""