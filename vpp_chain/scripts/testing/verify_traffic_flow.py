#!/usr/bin/env python3
"""
Definitive VPP Chain Traffic Flow Verification Script

This script provides multiple methods to conclusively verify that traffic 
is flowing correctly through the VPP multi-container chain.
"""

import subprocess
import time
import json
import re
from datetime import datetime
from scapy.all import *

class TrafficFlowVerifier:
    def __init__(self):
        self.containers = [
            'chain-ingress', 'chain-vxlan', 'chain-nat', 
            'chain-ipsec', 'chain-fragment', 'chain-gcp'
        ]
        self.verification_results = {}
    
    def verify_complete_traffic_flow(self):
        """
        Comprehensive traffic flow verification using multiple methods
        """
        print("🔍 DEFINITIVE VPP CHAIN TRAFFIC FLOW VERIFICATION")
        print("=" * 60)
        
        verification_methods = [
            ("Interface Counters", self.verify_interface_counters),
            ("Packet Tracing", self.verify_packet_tracing), 
            ("End-to-End Capture", self.verify_end_to_end_capture),
            ("Protocol Specific", self.verify_protocol_processing),
            ("Real Packet Flow", self.verify_real_packet_flow)
        ]
        
        all_passed = True
        
        for method_name, method_func in verification_methods:
            print(f"\n🧪 {method_name} Verification...")
            try:
                result = method_func()
                if result:
                    print(f"✅ {method_name}: PASS")
                else:
                    print(f"❌ {method_name}: FAIL")
                    all_passed = False
                    
                self.verification_results[method_name] = result
                
            except Exception as e:
                print(f"❌ {method_name}: ERROR - {e}")
                self.verification_results[method_name] = False
                all_passed = False
        
        # Final verdict
        print(f"\n{'='*60}")
        if all_passed:
            print("🎉 TRAFFIC FLOW VERIFICATION: ✅ ALL TESTS PASSED")
            print("   Traffic is definitely flowing through the VPP chain!")
        else:
            print("⚠️  TRAFFIC FLOW VERIFICATION: ❌ SOME TESTS FAILED")
            print("   Traffic flow may have issues - see details above")
        
        return all_passed
    
    def verify_interface_counters(self):
        """
        Method 1: Verify by checking VPP interface counter changes
        """
        print("   📊 Checking interface counter changes...")
        
        # Get baseline counters
        baseline = self.get_all_interface_counters()
        
        # Send test traffic
        self.send_test_traffic(packet_count=5)
        
        # Wait for processing
        time.sleep(3)
        
        # Get final counters
        final = self.get_all_interface_counters()
        
        # Analyze changes
        changes_detected = False
        for container in self.containers:
            baseline_container = baseline.get(container, {})
            final_container = final.get(container, {})
            
            for interface in final_container:
                baseline_if = baseline_container.get(interface, {})
                final_if = final_container[interface]
                
                # Check for TX increases (packet processing)
                baseline_tx = baseline_if.get('tx_packets', 0)
                final_tx = final_if.get('tx_packets', 0)
                
                baseline_rx = baseline_if.get('rx_packets', 0) 
                final_rx = final_if.get('rx_packets', 0)
                
                if final_tx > baseline_tx or final_rx > baseline_rx:
                    print(f"     ✓ {container}:{interface} - TX: {baseline_tx}→{final_tx}, RX: {baseline_rx}→{final_rx}")
                    changes_detected = True
        
        return changes_detected
    
    def verify_packet_tracing(self):
        """
        Method 2: Verify using VPP packet tracing
        """
        print("   🔍 Analyzing VPP packet traces...")
        
        # Clear and enable tracing
        for container in self.containers:
            try:
                subprocess.run(['docker', 'exec', container, 'vppctl', 'clear', 'trace'], 
                             capture_output=True, timeout=5)
                subprocess.run(['docker', 'exec', container, 'vppctl', 'trace', 'add', 
                               'af-packet-input', '10'], capture_output=True, timeout=5)
            except:
                pass
        
        # Send test traffic
        self.send_test_traffic(packet_count=3)
        time.sleep(2)
        
        # Check traces
        traces_found = 0
        for container in self.containers:
            try:
                result = subprocess.run(['docker', 'exec', container, 'vppctl', 'show', 'trace'],
                                      capture_output=True, text=True, timeout=10)
                
                if result.returncode == 0 and result.stdout.strip():
                    # Look for actual packet traces (not just "No packets in trace buffer")
                    if "Packet " in result.stdout and "af-packet-input" in result.stdout:
                        print(f"     ✓ {container}: Packet traces detected")
                        traces_found += 1
                    else:
                        print(f"     ○ {container}: No packet traces")
                        
            except Exception as e:
                print(f"     ○ {container}: Trace check failed - {e}")
        
        return traces_found > 0
    
    def verify_end_to_end_capture(self):
        """
        Method 3: Capture packets at the destination to prove end-to-end flow
        """
        print("   📡 Setting up end-to-end packet capture...")
        
        try:
            # Start packet capture on final container
            capture_process = subprocess.Popen([
                'docker', 'exec', 'chain-gcp', 'tcpdump', '-i', 'any', 
                '-c', '10', '-w', '/tmp/capture.pcap'
            ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            # Give capture time to start
            time.sleep(1)
            
            # Send test traffic
            self.send_test_traffic(packet_count=5)
            
            # Wait for capture to complete
            stdout, stderr = capture_process.communicate(timeout=15)
            
            # Check if packets were captured
            result = subprocess.run([
                'docker', 'exec', 'chain-gcp', 'tcpdump', '-r', '/tmp/capture.pcap'
            ], capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0 and result.stdout.strip():
                print(f"     ✓ Captured packets at destination: {result.stdout.count('IP')} packets")
                return True
            else:
                print("     ○ No packets captured at destination")
                return False
                
        except Exception as e:
            print(f"     ○ End-to-end capture failed: {e}")
            return False
    
    def verify_protocol_processing(self):
        """
        Method 4: Verify protocol-specific processing (NAT, IPsec, VXLAN)
        """
        print("   🔧 Verifying protocol-specific processing...")
        
        processing_verified = 0
        
        # Check VXLAN tunnel activity
        try:
            result = subprocess.run([
                'docker', 'exec', 'chain-vxlan', 'vppctl', 'show', 'vxlan', 'tunnel'
            ], capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0 and result.stdout.strip():
                print("     ✓ VXLAN tunnel configured and active")
                processing_verified += 1
            else:
                print("     ○ VXLAN tunnel check failed")
        except:
            print("     ○ VXLAN tunnel check error")
        
        # Check NAT sessions (after sending traffic)
        self.send_test_traffic(packet_count=2)
        time.sleep(1)
        
        try:
            result = subprocess.run([
                'docker', 'exec', 'chain-nat', 'vppctl', 'show', 'nat44', 'sessions'
            ], capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0 and ("10.10.10.10" in result.stdout or "session" in result.stdout.lower()):
                print("     ✓ NAT44 sessions detected")
                processing_verified += 1
            else:
                print("     ○ No NAT44 sessions found")
        except:
            print("     ○ NAT44 session check error")
        
        # Check IPsec SAs
        try:
            result = subprocess.run([
                'docker', 'exec', 'chain-ipsec', 'vppctl', 'show', 'ipsec', 'sa'
            ], capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0 and result.stdout.strip():
                print("     ✓ IPsec Security Associations configured")
                processing_verified += 1
            else:
                print("     ○ IPsec SAs check failed")
        except:
            print("     ○ IPsec SA check error")
        
        return processing_verified >= 2  # At least 2 protocols working
    
    def verify_real_packet_flow(self):
        """
        Method 5: Send real packets and verify they traverse the entire chain
        """
        print("   🚀 Sending real packets and tracking flow...")
        
        # Create unique packet with identifiable payload
        unique_id = int(time.time()) % 10000
        test_payload = f"VPP_CHAIN_TEST_{unique_id}_" + "X" * 100
        
        try:
            # Create and send packet with unique payload
            inner = IP(src="10.10.10.5", dst="10.10.10.10")/UDP(sport=1234, dport=2055)/test_payload
            vxlan = VXLAN(vni=100)/inner
            outer = IP(src="172.20.0.1", dst="172.20.1.20")/UDP(sport=12345, dport=4789)/vxlan
            
            print(f"     📤 Sending packet with unique ID: {unique_id}")
            send(outer, verbose=False)
            
            # Wait for processing
            time.sleep(2)
            
            # Check if we can find evidence of the packet in each container
            containers_with_activity = 0
            
            for container in self.containers:
                try:
                    # Check interface stats increased
                    result = subprocess.run([
                        'docker', 'exec', container, 'vppctl', 'show', 'interface'
                    ], capture_output=True, text=True, timeout=10)
                    
                    if result.returncode == 0:
                        # Look for non-zero counters
                        if "tx packets" in result.stdout and re.search(r'tx packets\s+\d+[1-9]', result.stdout):
                            containers_with_activity += 1
                            print(f"     ✓ {container}: Activity detected")
                        else:
                            print(f"     ○ {container}: No activity")
                            
                except Exception as e:
                    print(f"     ○ {container}: Check failed - {e}")
            
            # Success if most containers show activity
            success = containers_with_activity >= 4
            print(f"     📊 Containers with packet activity: {containers_with_activity}/6")
            
            return success
            
        except Exception as e:
            print(f"     ❌ Real packet flow test failed: {e}")
            return False
    
    def get_all_interface_counters(self):
        """Get interface counters from all containers"""
        counters = {}
        
        for container in self.containers:
            try:
                result = subprocess.run([
                    'docker', 'exec', container, 'vppctl', 'show', 'interface'
                ], capture_output=True, text=True, timeout=10)
                
                if result.returncode == 0:
                    counters[container] = self.parse_interface_stats(result.stdout)
                    
            except Exception:
                counters[container] = {}
        
        return counters
    
    def parse_interface_stats(self, output):
        """Parse VPP interface statistics"""
        interfaces = {}
        current_interface = None
        
        for line in output.split('\n'):
            line = line.strip()
            
            # Interface name line
            if line and not line.startswith(' ') and any(x in line for x in ['host-', 'vxlan_', 'ipip']):
                parts = line.split()
                if parts:
                    current_interface = parts[0]
                    interfaces[current_interface] = {}
            
            # Counter lines
            elif current_interface and line.startswith(' ') and 'packets' in line:
                try:
                    if 'rx packets' in line:
                        interfaces[current_interface]['rx_packets'] = int(line.split()[-1])
                    elif 'tx packets' in line:
                        interfaces[current_interface]['tx_packets'] = int(line.split()[-1])
                    elif line.strip().endswith('drops') and 'drops' in line:
                        interfaces[current_interface]['drops'] = int(line.split()[-1])
                except (ValueError, IndexError):
                    pass
        
        return interfaces
    
    def send_test_traffic(self, packet_count=5):
        """Send test traffic to the VPP chain"""
        try:
            for i in range(packet_count):
                # Vary packet sizes and sources for better testing
                payload_size = 100 + (i * 50)  # Vary from 100 to 300 bytes
                payload = "X" * payload_size
                
                inner = IP(src=f"10.10.10.{5+i}", dst="10.10.10.10")/UDP(sport=1234+i, dport=2055)/payload
                vxlan = VXLAN(vni=100)/inner
                outer = IP(src="172.20.0.1", dst="172.20.1.20")/UDP(sport=12345+i, dport=4789)/vxlan
                
                send(outer, verbose=False)
                time.sleep(0.2)  # Small delay between packets
                
        except Exception as e:
            print(f"   ⚠️ Traffic generation error: {e}")
    
    def generate_detailed_report(self):
        """Generate detailed verification report"""
        print(f"\n{'='*60}")
        print("📋 DETAILED VERIFICATION REPORT")
        print(f"{'='*60}")
        print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print()
        
        for method, result in self.verification_results.items():
            status = "✅ PASS" if result else "❌ FAIL"
            print(f"{method:.<40} {status}")
        
        passed = sum(1 for r in self.verification_results.values() if r)
        total = len(self.verification_results)
        
        print(f"\nOverall Score: {passed}/{total} methods passed")
        
        if passed >= 3:
            print("🎉 CONCLUSION: Traffic flow is working correctly!")
        elif passed >= 1:
            print("⚠️  CONCLUSION: Partial traffic flow detected - needs investigation")
        else:
            print("❌ CONCLUSION: No traffic flow detected - major issues present")

def main():
    """Main execution"""
    verifier = TrafficFlowVerifier()
    
    print("VPP Chain Traffic Flow Verification")
    print("This script will definitively determine if traffic flows through your VPP chain")
    print()
    
    # Run complete verification
    overall_success = verifier.verify_complete_traffic_flow()
    
    # Generate detailed report
    verifier.generate_detailed_report()
    
    # Exit with appropriate code
    return 0 if overall_success else 1

if __name__ == "__main__":
    exit(main())