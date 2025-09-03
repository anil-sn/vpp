"""
Traffic Generation and Testing for VPP Multi-Container Chain

Handles VXLAN packet generation, traffic injection, and end-to-end testing.
"""

import subprocess
import time
import threading
import socket
from scapy.all import *
from .logger import get_logger, log_success, log_error, log_warning, log_info

class TrafficGenerator:
    """Generates and manages test traffic for the VPP chain"""
    
    # Traffic configuration
    CONFIG = {
        "bridge_ip": "192.168.1.1",
        "ingress_ip": "192.168.1.2", 
        "gcp_ip": "192.168.1.3",
        "vxlan_port": 4789,
        "vxlan_vni": 100,
        "inner_src_ip": "10.10.10.5",
        "inner_dst_ip": "10.10.10.10",
        "inner_dst_port": 2055,
        "packet_count": 10,
        "packet_size": 1200,  # Large enough to test fragmentation
        "test_duration": 10
    }
    
    def __init__(self):
        self.logger = get_logger()
        self.interface = None
        self.sent_packets = 0
        self.received_packets = 0
        self.capturing = False
        self.capture_thread = None
        
    def check_environment(self):
        """Verify that the environment is ready for traffic testing"""
        try:
            log_info("Checking environment readiness...")
            
            # Check containers are running
            containers = ["chain-ingress", "chain-vxlan", "chain-nat", "chain-ipsec", "chain-fragment", "chain-gcp"]
            for container in containers:
                result = subprocess.run([
                    "docker", "ps", "--format", "table {{.Names}}"
                ], capture_output=True, text=True, check=True)
                
                if container not in result.stdout:
                    log_error(f"Container {container} is not running")
                    return False
                
            log_success("All containers are running")
            
            # Check bridge connectivity
            result = subprocess.run([
                "ping", "-c", "1", "-W", "2", self.CONFIG["ingress_ip"]
            ], capture_output=True, text=True)
            
            if result.returncode != 0:
                log_error(f"Cannot reach ingress container ({self.CONFIG['ingress_ip']})")
                return False
                
            log_success("Bridge connectivity verified")
            return True
            
        except Exception as e:
            log_error(f"Environment check failed: {e}")
            return False
    
    def find_interface(self):
        """Find the best interface for packet injection"""
        try:
            log_info("Finding suitable network interface...")
            
            # Try to find the interface that can reach the ingress
            result = subprocess.run([
                "ip", "route", "get", self.CONFIG["ingress_ip"]
            ], capture_output=True, text=True, check=True)
            
            for line in result.stdout.split('\n'):
                if 'dev' in line:
                    parts = line.split()
                    if 'dev' in parts:
                        dev_index = parts.index('dev')
                        if dev_index + 1 < len(parts):
                            self.interface = parts[dev_index + 1]
                            log_success(f"Using interface: {self.interface}")
                            return True
            
            # Fallback interfaces
            fallback_interfaces = ['br0', 'docker0', 'veth0', 'eth0']
            for iface in fallback_interfaces:
                if self._interface_exists(iface):
                    self.interface = iface
                    log_success(f"Using fallback interface: {self.interface}")
                    return True
            
            log_error("No suitable interface found")
            return False
            
        except Exception as e:
            log_error(f"Interface detection failed: {e}")
            return False
    
    def _interface_exists(self, interface_name):
        """Check if a network interface exists"""
        try:
            result = subprocess.run([
                "ip", "link", "show", interface_name
            ], capture_output=True, text=True)
            return result.returncode == 0
        except:
            return False
    
    def generate_vxlan_packet(self, seq_num):
        """Generate a VXLAN-encapsulated packet"""
        try:
            # Inner payload (large to test fragmentation)
            payload = "X" * self.CONFIG["packet_size"]
            
            # Inner IP packet (processed by the chain)
            inner_packet = (
                IP(src=self.CONFIG["inner_src_ip"], dst=self.CONFIG["inner_dst_ip"]) /
                UDP(sport=1234 + seq_num, dport=self.CONFIG["inner_dst_port"]) /
                payload
            )
            
            # VXLAN encapsulation
            vxlan_packet = (
                IP(src=self.CONFIG["bridge_ip"], dst=self.CONFIG["ingress_ip"]) /
                UDP(sport=12345 + seq_num, dport=self.CONFIG["vxlan_port"]) /
                VXLAN(vni=self.CONFIG["vxlan_vni"], flags=0x08) /
                inner_packet
            )
            
            return vxlan_packet
            
        except Exception as e:
            log_error(f"Packet generation failed: {e}")
            return None
    
    def start_packet_capture(self):
        """Start capturing packets at the GCP endpoint"""
        try:
            log_info("Starting packet capture...")
            self.capturing = True
            self.received_packets = 0
            self.capture_thread = threading.Thread(target=self._capture_worker)
            self.capture_thread.daemon = True
            self.capture_thread.start()
            return True
        except Exception as e:
            log_error(f"Failed to start packet capture: {e}")
            return False
    
    def _capture_worker(self):
        """Worker thread for packet capture"""
        try:
            def packet_handler(packet):
                if self.capturing and packet.haslayer(IP):
                    # Check if this looks like our test traffic
                    if packet[IP].dst == self.CONFIG["gcp_ip"] or packet[IP].src.startswith("10.0.3"):
                        self.received_packets += 1
                        log_info(f"Captured packet {self.received_packets}")
            
            # Start packet capture
            sniff(
                filter="ip", 
                prn=packet_handler, 
                timeout=self.CONFIG["test_duration"] + 10,
                store=0
            )
            
        except Exception as e:
            log_warning(f"Packet capture issue: {e}")
    
    def send_test_traffic(self):
        """Send test traffic through the chain"""
        try:
            log_info(f"Generating {self.CONFIG['packet_count']} VXLAN packets...")
            log_info(f"Traffic: {self.CONFIG['inner_src_ip']} → {self.CONFIG['inner_dst_ip']}:{self.CONFIG['inner_dst_port']}")
            log_info(f"Packet size: {self.CONFIG['packet_size']} bytes (triggers fragmentation)")
            log_info(f"VXLAN VNI: {self.CONFIG['vxlan_vni']}")
            
            self.sent_packets = 0
            
            for i in range(self.CONFIG["packet_count"]):
                packet = self.generate_vxlan_packet(i)
                if packet is None:
                    continue
                
                try:
                    send(packet, iface=self.interface, verbose=0)
                    self.sent_packets += 1
                    log_info(f"Sent packet {i+1}/{self.CONFIG['packet_count']}")
                    time.sleep(0.2)  # Small delay between packets
                    
                except Exception as e:
                    log_error(f"Failed to send packet {i+1}: {e}")
            
            log_success(f"Sent {self.sent_packets} packets successfully")
            return self.sent_packets > 0
            
        except Exception as e:
            log_error(f"Traffic generation failed: {e}")
            return False
    
    def stop_capture(self):
        """Stop packet capture"""
        try:
            log_info("Stopping packet capture...")
            self.capturing = False
            if self.capture_thread and self.capture_thread.is_alive():
                self.capture_thread.join(timeout=5)
            return True
        except Exception as e:
            log_error(f"Failed to stop capture: {e}")
            return False
    
    def analyze_chain_statistics(self):
        """Analyze VPP statistics from each container"""
        try:
            log_info("Analyzing chain processing statistics...")
            
            containers_info = [
                ("chain-ingress", "Ingress reception"),
                ("chain-vxlan", "VXLAN decapsulation"), 
                ("chain-nat", "NAT translation"),
                ("chain-ipsec", "IPsec encryption"),
                ("chain-fragment", "Fragmentation"),
                ("chain-gcp", "GCP delivery")
            ]
            
            print("\n📊 Chain Processing Statistics:")
            print("-" * 70)
            
            chain_success = True
            
            for container, description in containers_info:
                try:
                    # Get interface statistics
                    result = subprocess.run([
                        "docker", "exec", container, "vppctl", "show", "interface"
                    ], capture_output=True, text=True, timeout=10)
                    
                    if result.returncode == 0:
                        # Parse packet counts
                        rx_packets = 0
                        tx_packets = 0
                        drops = 0
                        
                        for line in result.stdout.split('\n'):
                            if 'rx packets' in line and line.strip():
                                try:
                                    rx_packets = int(line.split()[-1])
                                except:
                                    pass
                            if 'tx packets' in line and line.strip():
                                try:
                                    tx_packets = int(line.split()[-1])
                                except:
                                    pass
                            if 'drops' in line and line.strip():
                                try:
                                    drops = int(line.split()[-1])
                                except:
                                    pass
                        
                        status = "✅" if rx_packets > 0 or tx_packets > 0 else "❌"
                        print(f"{status} {container:15} ({description:20}): RX={rx_packets:3}, TX={tx_packets:3}, Drops={drops:3}")
                        
                        if rx_packets == 0 and tx_packets == 0 and container != "chain-gcp":
                            chain_success = False
                            
                    else:
                        print(f"❌ {container:15}: VPP not responding")
                        chain_success = False
                        
                except Exception as e:
                    print(f"⚠️ {container:15}: Error getting stats: {e}")
            
            return chain_success
            
        except Exception as e:
            log_error(f"Statistics analysis failed: {e}")
            return False
    
    def run_traffic_test(self):
        """Run complete traffic generation and analysis test"""
        try:
            log_info("🧪 Starting VPP Multi-Container Chain Traffic Test")
            print("=" * 60)
            
            # Environment check
            if not self.check_environment():
                return False
            
            # Find interface
            if not self.find_interface():
                return False
            
            # Start capture
            if not self.start_packet_capture():
                return False
            
            # Send traffic
            if not self.send_test_traffic():
                self.stop_capture()
                return False
            
            # Wait for processing
            log_info(f"Waiting {self.CONFIG['test_duration']} seconds for processing...")
            time.sleep(self.CONFIG["test_duration"])
            
            # Stop capture
            self.stop_capture()
            
            # Analyze results
            chain_success = self.analyze_chain_statistics()
            
            # Summary
            print(f"\n📈 Test Summary:")
            print(f"  Packets sent: {self.sent_packets}")
            print(f"  Packets captured: {self.received_packets}")
            
            if self.sent_packets > 0:
                success_rate = (self.received_packets / self.sent_packets) * 100 if self.sent_packets > 0 else 0
                print(f"  End-to-end success rate: {success_rate:.1f}%")
                
                if success_rate >= 80 and chain_success:
                    log_success("🎉 CHAIN TEST SUCCESSFUL: End-to-end processing verified!")
                    return True
                elif success_rate >= 50 or chain_success:
                    log_warning("⚠️ PARTIAL SUCCESS: Some processing detected, check individual containers")
                    return True
                else:
                    log_error("❌ CHAIN TEST FAILED: Low success rate")
                    return False
            else:
                log_error("❌ TRAFFIC GENERATION FAILED: No packets sent")
                return False
                
        except KeyboardInterrupt:
            log_info("🛑 Test interrupted by user")
            self.stop_capture()
            return False
        except Exception as e:
            log_error(f"Traffic test failed: {e}")
            self.stop_capture()
            return False