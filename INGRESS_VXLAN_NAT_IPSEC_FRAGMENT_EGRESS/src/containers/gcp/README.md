# GCP Container

## Purpose
Acts as the final destination endpoint, receives processed packets and provides packet capture.

## Configuration
- **VPP Config**: `../../configs/gcp-config.sh`
- **Network**: underlay (192.168.10.30)
- **Function**: Packet reassembly and capture

## Destination Configuration
- **Interface**: host-eth0 (192.168.10.30)
- **TAP Interface**: tap0 (10.0.3.1) for Linux integration
- **Packet Capture**: tcpdump on TAP interface
- **Reassembly**: IP fragment reassembly enabled

## Key Features
- IP fragment reassembly for large packets
- TAP interface for Linux kernel integration
- Automatic packet capture (tcpdump)
- Final packet delivery and validation

## Packet Capture
- **Location**: `/tmp/gcp-received.pcap`
- **Interface**: vpp-tap0 (Linux TAP)
- **Format**: Standard pcap for analysis

## Usage
```bash
# Check received packets
sudo python3 src/main.py debug chain-gcp "show interface addr"

# View packet capture
docker exec chain-gcp tcpdump -r /tmp/gcp-received.pcap
```