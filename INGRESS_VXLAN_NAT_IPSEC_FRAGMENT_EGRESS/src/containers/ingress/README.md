# INGRESS Container

## Purpose
Receives VXLAN-encapsulated traffic from external sources on the underlay network.

## Configuration
- **VPP Config**: `../../configs/ingress-config.sh`
- **Network**: underlay (192.168.10.x), chain-1-2 (10.1.1.1)
- **Function**: VXLAN packet reception and forwarding

## Key Features
- Host interface creation for inter-container networking
- Basic packet forwarding to VXLAN decapsulation stage
- Packet tracing enabled for debugging

## Interfaces
- `host-eth0`: Underlay network interface
- `host-eth1`: Chain connection to VXLAN container

## Usage
```bash
# Debug this container
sudo python3 src/main.py debug chain-ingress "show interface"

# Check packet processing
docker exec chain-ingress vppctl show interface
```