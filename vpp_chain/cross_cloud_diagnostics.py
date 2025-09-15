#!/usr/bin/env python3
"""
Cross-Cloud VPP Chain Diagnostics and Testing

This script validates and tests the multi-cloud VPP chain deployment:
- AWS: VXLAN-PROCESSOR + SECURITY-PROCESSOR
- GCP: DESTINATION
- Cross-cloud connectivity and packet flow

Features:
- Environment detection (AWS/GCP)
- Container health checks
- VPP configuration validation  
- Cross-cloud connectivity testing
- End-to-end packet flow simulation
- Performance monitoring
"""

import json
import subprocess
import socket
import time
import sys
import os
from datetime import datetime
import ipaddress

class CrossCloudDiagnostics:
    def __init__(self):
        self.environment = self.detect_environment()
        self.config = self.load_config()
        self.metadata = self.load_metadata()
        self.results = {
            'timestamp': datetime.now().isoformat(),
            'environment': self.environment,
            'tests': {}
        }
        
    def detect_environment(self):
        """Detect if running on AWS, GCP, or other"""
        try:
            # Try AWS metadata
            result = subprocess.run(['curl', '-s', '--max-time', '3', 
                                   'http://169.254.169.254/latest/meta-data/instance-id'], 
                                  capture_output=True, text=True)
            if result.returncode == 0 and result.stdout.strip():
                return 'aws'
        except:
            pass
            
        try:
            # Try GCP metadata  
            result = subprocess.run(['curl', '-s', '--max-time', '3',
                                   '-H', 'Metadata-Flavor: Google',
                                   'http://metadata.google.internal/computeMetadata/v1/instance/id'],
                                  capture_output=True, text=True)
            if result.returncode == 0 and result.stdout.strip():
                return 'gcp'
        except:
            pass
            
        return 'unknown'
    
    def load_config(self):
        """Load the appropriate configuration file"""
        if self.environment == 'aws':
            config_file = 'production_aws_config.json'
        elif self.environment == 'gcp':
            config_file = 'production_gcp_config.json'
        else:
            # Try to find any config file
            for f in ['production_aws_config.json', 'production_gcp_config.json']:
                if os.path.exists(f):
                    config_file = f
                    break
            else:
                return None
                
        try:
            with open(config_file, 'r') as f:
                return json.load(f)
        except:
            return None
    
    def load_metadata(self):
        """Load deployment metadata if available"""
        try:
            with open('multicloud_deployment_metadata.json', 'r') as f:
                return json.load(f)
        except:
            return {}
    
    def print_header(self):
        print("=" * 80)
        print(" Cross-Cloud VPP Chain Diagnostics")
        print("=" * 80)
        print(f"Environment: {self.environment.upper()}")
        print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print()
        
        if self.environment == 'aws':
            print(" AWS Side Diagnostics:")
            print("   Testing: VXLAN-PROCESSOR + SECURITY-PROCESSOR")
        elif self.environment == 'gcp':
            print(" GCP Side Diagnostics:")
            print("   Testing: DESTINATION processor")
        else:
            print(" Unknown Environment - Generic diagnostics")
            
        print()
    
    def test_docker_environment(self):
        """Test Docker installation and VPP containers"""
        print("  Docker Environment Test")
        print("-" * 40)
        
        try:
            # Check Docker
            result = subprocess.run(['docker', '--version'], capture_output=True, text=True)
            if result.returncode == 0:
                print(f" Docker: {result.stdout.strip()}")
            else:
                print(" Docker not available")
                return False
                
            # Check VPP containers based on environment
            if self.environment == 'aws':
                containers = ['vxlan-processor', 'security-processor']
            elif self.environment == 'gcp':
                containers = ['destination']
            else:
                containers = ['vxlan-processor', 'security-processor', 'destination']
                
            print(f"\nContainer Status:")
            all_containers_ok = True
            
            for container in containers:
                result = subprocess.run(['docker', 'ps', '--filter', f'name={container}', 
                                       '--format', '{{.Status}}'], capture_output=True, text=True)
                if result.returncode == 0 and 'Up' in result.stdout:
                    print(f" {container}: Running")
                else:
                    print(f" {container}: Not running or not found")
                    all_containers_ok = False
                    
            self.results['tests']['docker'] = {
                'status': 'pass' if all_containers_ok else 'fail',
                'containers': containers,
                'all_running': all_containers_ok
            }
            
            return all_containers_ok
            
        except Exception as e:
            print(f" Docker test failed: {e}")
            self.results['tests']['docker'] = {'status': 'fail', 'error': str(e)}
            return False
    
    def test_vpp_status(self):
        """Test VPP status in containers"""
        print("\n  VPP Status Test") 
        print("-" * 40)
        
        if self.environment == 'aws':
            containers = ['vxlan-processor', 'security-processor']
        elif self.environment == 'gcp':
            containers = ['destination']
        else:
            containers = ['vxlan-processor', 'security-processor', 'destination']
            
        vpp_results = {}
        all_vpp_ok = True
        
        for container in containers:
            print(f"\n {container} VPP Status:")
            try:
                # Check VPP version
                result = subprocess.run(['docker', 'exec', container, 'vppctl', 'show', 'version'],
                                      capture_output=True, text=True, timeout=10)
                if result.returncode == 0:
                    version_line = result.stdout.split('\n')[0]
                    print(f"    VPP Version: {version_line}")
                    
                    # Check interfaces
                    result = subprocess.run(['docker', 'exec', container, 'vppctl', 'show', 'interface'],
                                          capture_output=True, text=True, timeout=10)
                    if result.returncode == 0:
                        interface_count = len([line for line in result.stdout.split('\n') if 'host-' in line or 'tap' in line])
                        print(f"    Interfaces: {interface_count} active")
                        
                        vpp_results[container] = {'status': 'running', 'interfaces': interface_count}
                    else:
                        print(f"     Could not query interfaces")
                        vpp_results[container] = {'status': 'partial'}
                        all_vpp_ok = False
                else:
                    print(f"    VPP not responding")
                    vpp_results[container] = {'status': 'not_running'}
                    all_vpp_ok = False
                    
            except subprocess.TimeoutExpired:
                print(f"    VPP command timeout")
                vpp_results[container] = {'status': 'timeout'}
                all_vpp_ok = False
            except Exception as e:
                print(f"    VPP test error: {e}")
                vpp_results[container] = {'status': 'error', 'error': str(e)}
                all_vpp_ok = False
        
        self.results['tests']['vpp'] = {
            'status': 'pass' if all_vpp_ok else 'fail',
            'containers': vpp_results
        }
        
        return all_vpp_ok
    
    def test_network_configuration(self):
        """Test network configuration and connectivity"""
        print("\n  Network Configuration Test")
        print("-" * 40)
        
        # Host network info
        print(" Host Network Configuration:")
        try:
            result = subprocess.run(['ip', 'addr', 'show'], capture_output=True, text=True)
            if result.returncode == 0:
                # Count interfaces
                interface_count = len([line for line in result.stdout.split('\n') if line.startswith(('1:', '2:', '3:', '4:', '5:'))])
                print(f"    Host Interfaces: {interface_count}")
                
                # Check for specific interfaces based on environment
                if self.environment == 'aws':
                    if 'ens5' in result.stdout:
                        print("    AWS ens5 interface detected")
                    if 'br0' in result.stdout:
                        print("    Bridge br0 detected")
                    if 'vxlan1' in result.stdout:
                        print("    VXLAN interface detected")
        except Exception as e:
            print(f"    Host network check failed: {e}")
        
        # Docker network info
        print(f"\n Docker Networks:")
        try:
            result = subprocess.run(['docker', 'network', 'ls'], capture_output=True, text=True)
            if result.returncode == 0:
                vpp_networks = [line for line in result.stdout.split('\n') 
                               if any(keyword in line.lower() for keyword in ['vxlan', 'security', 'cross', 'cloud'])]
                print(f"    VPP Networks: {len(vpp_networks)}")
                for network in vpp_networks[:3]:  # Show first 3
                    network_name = network.split()[1] if len(network.split()) > 1 else 'unknown'
                    print(f"   • {network_name}")
        except Exception as e:
            print(f"    Docker network check failed: {e}")
            
        self.results['tests']['network'] = {'status': 'partial'}
        return True
    
    def test_cross_cloud_connectivity(self):
        """Test cross-cloud connectivity"""
        print("\n  Cross-Cloud Connectivity Test")
        print("-" * 40)
        
        if not self.metadata:
            print("  No metadata available for cross-cloud testing")
            return False
            
        cross_cloud = self.metadata.get('cross_cloud', {})
        
        if self.environment == 'aws':
            target_ip = cross_cloud.get('gcp_from_aws_ip')
            print(f" Testing connectivity to GCP: {target_ip}")
        elif self.environment == 'gcp':
            target_ip = cross_cloud.get('aws_to_gcp_ip') 
            print(f" Testing connectivity to AWS: {target_ip}")
        else:
            print("Unknown environment - skipping connectivity test")
            return True
            
        if not target_ip:
            print("  Target IP not configured")
            return False
            
        # Basic ping test
        print(f"\n Ping Test to {target_ip}:")
        try:
            result = subprocess.run(['ping', '-c', '3', '-W', '5', target_ip], 
                                  capture_output=True, text=True, timeout=20)
            if result.returncode == 0:
                print("    Ping successful")
                connectivity_ok = True
            else:
                print("    Ping failed - this may be expected if VPN/firewall blocks ICMP")
                connectivity_ok = False
        except subprocess.TimeoutExpired:
            print("    Ping timeout")
            connectivity_ok = False
        except Exception as e:
            print(f"    Ping error: {e}")
            connectivity_ok = False
            
        # Port connectivity test (if IPsec/UDP)
        print(f"\n Port Connectivity Test:")
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.settimeout(5)
            # Try to connect to common VPP/IPsec ports
            test_ports = [500, 4500, 4789]  # IKE, IPsec NAT-T, VXLAN
            
            port_results = []
            for port in test_ports:
                try:
                    sock.connect((target_ip, port))
                    print(f"    Port {port}: Reachable")
                    port_results.append((port, True))
                except:
                    print(f"     Port {port}: Not reachable (may be filtered)")
                    port_results.append((port, False))
            sock.close()
            
        except Exception as e:
            print(f"    Port test error: {e}")
            port_results = []
        
        self.results['tests']['cross_cloud'] = {
            'status': 'pass' if connectivity_ok else 'partial',
            'target_ip': target_ip,
            'ping_success': connectivity_ok,
            'port_results': port_results
        }
        
        return connectivity_ok
    
    def test_vpp_specific_config(self):
        """Test VPP-specific configuration based on container role"""
        print("\n  VPP Configuration Validation")
        print("-" * 40)
        
        if self.environment == 'aws':
            self._test_aws_vpp_config()
        elif self.environment == 'gcp':
            self._test_gcp_vpp_config()
        else:
            print("Unknown environment - skipping VPP config tests")
            
        return True
    
    def _test_aws_vpp_config(self):
        """Test AWS-specific VPP configuration"""
        print(" AWS VPP Configuration Tests:")
        
        # Test VXLAN processor
        print(f"\n VXLAN Processor Configuration:")
        try:
            # Check VXLAN tunnel
            result = subprocess.run(['docker', 'exec', 'vxlan-processor', 'vppctl', 'show', 'vxlan', 'tunnel'],
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and 'vxlan_tunnel0' in result.stdout:
                print("    VXLAN tunnel configured")
            else:
                print("    VXLAN tunnel not found")
                
            # Check BVI interface
            result = subprocess.run(['docker', 'exec', 'vxlan-processor', 'vppctl', 'show', 'bridge-domain', '10', 'detail'],
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and 'BVI' in result.stdout:
                print("    BVI interface configured")
            else:
                print("    BVI interface not found")
                
        except Exception as e:
            print(f"    VXLAN processor test error: {e}")
        
        # Test Security processor
        print(f"\nSecurity Processor Configuration:")
        try:
            # Check NAT44
            result = subprocess.run(['docker', 'exec', 'security-processor', 'vppctl', 'show', 'nat44', 'static', 'mappings'],
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and result.stdout.strip():
                print("    NAT44 mappings configured")
            else:
                print("     NAT44 mappings not found")
                
            # Check IPsec SA
            result = subprocess.run(['docker', 'exec', 'security-processor', 'vppctl', 'show', 'ipsec', 'sa'],
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and 'spi' in result.stdout.lower():
                print("    IPsec SA configured")
            else:
                print("     IPsec SA not found")
                
        except Exception as e:
            print(f"    Security processor test error: {e}")
    
    def _test_gcp_vpp_config(self):
        """Test GCP-specific VPP configuration"""
        print(" GCP VPP Configuration Tests:")
        
        print(f"\n Destination Processor Configuration:")
        try:
            # Check TAP interface
            result = subprocess.run(['docker', 'exec', 'destination', 'vppctl', 'show', 'interface', 'tap0'],
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                print("    TAP interface configured")
            else:
                print("    TAP interface not found")
                
            # Check IPsec decryption SA
            result = subprocess.run(['docker', 'exec', 'destination', 'vppctl', 'show', 'ipsec', 'sa'],
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and result.stdout.strip():
                print("    IPsec decryption configured") 
            else:
                print("     IPsec decryption not found")
                
        except Exception as e:
            print(f"    Destination processor test error: {e}")
    
    def simulate_traffic_flow(self):
        """Simulate and test packet flow"""
        print("\n  Traffic Flow Simulation")
        print("-" * 40)
        
        if self.environment == 'aws':
            print(" AWS Traffic Simulation:")
            print("   Simulating: Host traffic → VXLAN processor → Security processor")
            
            # Enable VPP tracing  
            containers = ['vxlan-processor', 'security-processor']
            for container in containers:
                try:
                    subprocess.run(['docker', 'exec', container, 'vppctl', 'clear', 'trace'], 
                                 capture_output=True, timeout=5)
                    subprocess.run(['docker', 'exec', container, 'vppctl', 'trace', 'add', 'af-packet-input', '10'],
                                 capture_output=True, timeout=5)
                    print(f"    Tracing enabled on {container}")
                except:
                    print(f"     Could not enable tracing on {container}")
            
        elif self.environment == 'gcp':
            print(" GCP Traffic Simulation:")
            print("   Monitoring: Incoming traffic → Destination processor → TAP")
            
            # Enable tracing on destination
            try:
                subprocess.run(['docker', 'exec', 'destination', 'vppctl', 'clear', 'trace'],
                             capture_output=True, timeout=5)
                subprocess.run(['docker', 'exec', 'destination', 'vppctl', 'trace', 'add', 'af-packet-input', '10'],
                             capture_output=True, timeout=5) 
                print("    Tracing enabled on destination")
            except:
                print("     Could not enable tracing on destination")
        
        # Monitor for a brief period
        print(f"\n Monitoring traffic for 15 seconds...")
        time.sleep(15)
        
        # Check trace results
        if self.environment == 'aws':
            containers = ['vxlan-processor', 'security-processor']
        elif self.environment == 'gcp':
            containers = ['destination']
        else:
            containers = []
            
        for container in containers:
            try:
                result = subprocess.run(['docker', 'exec', container, 'vppctl', 'show', 'trace'],
                                      capture_output=True, text=True, timeout=10)
                if result.returncode == 0:
                    trace_lines = len([line for line in result.stdout.split('\n') if line.strip()])
                    if trace_lines > 5:  # More than just header
                        print(f"    {container}: {trace_lines} trace entries (traffic detected)")
                    else:
                        print(f"   {container}: No significant traffic detected")
            except:
                print(f"     Could not check trace on {container}")
    
    def generate_report(self):
        """Generate diagnostic report"""
        print("\n" + "=" * 80)
        print(" Diagnostic Report Summary")
        print("=" * 80)
        
        total_tests = len(self.results['tests'])
        passed_tests = len([t for t in self.results['tests'].values() if t.get('status') == 'pass'])
        
        print(f"Environment: {self.environment.upper()}")
        print(f"Tests Completed: {total_tests}")
        print(f"Tests Passed: {passed_tests}")
        print(f"Success Rate: {(passed_tests/total_tests*100) if total_tests > 0 else 0:.1f}%")
        print()
        
        # Test results summary
        for test_name, result in self.results['tests'].items():
            status_icon = "" if result['status'] == 'pass' else "" if result['status'] == 'partial' else ""
            print(f"{status_icon} {test_name.replace('_', ' ').title()}: {result['status'].upper()}")
        
        print()
        
        # Recommendations
        print("Recommendations:")
        if self.environment == 'aws':
            if passed_tests >= 3:
                print("   • AWS side appears healthy - proceed with GCP deployment")
                print("   • Verify VPN/interconnect configuration")
            else:
                print("   • Check VPP container logs: docker logs <container-name>")
                print("   • Verify network configuration")
        elif self.environment == 'gcp':
            if passed_tests >= 3:
                print("   • GCP side appears healthy - ready to receive traffic")
                print("   • Verify VPN/interconnect from AWS side")
            else:
                print("   • Check destination container deployment")
                print("   • Verify cross-cloud network routing")
        
        print("   • Run end-to-end testing once both sides are deployed")
        print("   • Monitor VPP performance: docker exec <container> vppctl show runtime")
        
        # Save report
        report_filename = f"diagnostic_report_{self.environment}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(report_filename, 'w') as f:
            json.dump(self.results, f, indent=2)
        
        print(f"\nFull report saved to: {report_filename}")
        print()
        
    def run_all_diagnostics(self):
        """Run all diagnostic tests"""
        self.print_header()
        
        if not self.config:
            print(" No configuration file found")
            print("   Run: python3 configure_multicloud_deployment.py first")
            return False
        
        # Run all tests
        tests = [
            self.test_docker_environment,
            self.test_vpp_status,
            self.test_network_configuration,
            self.test_cross_cloud_connectivity,
            self.test_vpp_specific_config,
            self.simulate_traffic_flow
        ]
        
        success = True
        for test in tests:
            try:
                result = test()
                if not result:
                    success = False
            except KeyboardInterrupt:
                print("\n\n Diagnostics interrupted by user")
                return False
            except Exception as e:
                print(f"\n Test failed with error: {e}")
                success = False
        
        self.generate_report()
        return success

def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--help':
        print("Cross-Cloud VPP Chain Diagnostics")
        print()
        print("Usage: python3 cross_cloud_diagnostics.py")
        print()
        print("This script automatically detects the environment (AWS/GCP) and runs")
        print("appropriate diagnostic tests for the multi-cloud VPP deployment.")
        print()
        print("Prerequisites:")
        print("- Run configure_multicloud_deployment.py first")
        print("- Deploy VPP containers with deploy_aws_multicloud.sh or deploy_gcp_multicloud.sh")
        print()
        return
    
    try:
        diagnostics = CrossCloudDiagnostics()
        success = diagnostics.run_all_diagnostics()
        
        if success:
            print("Diagnostics completed successfully!")
        else:
            print("  Some diagnostics failed - check the report for details")
            
    except KeyboardInterrupt:
        print("\n\n Diagnostics cancelled")
        sys.exit(1)
    except Exception as e:
        print(f"\nDiagnostics failed with error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()