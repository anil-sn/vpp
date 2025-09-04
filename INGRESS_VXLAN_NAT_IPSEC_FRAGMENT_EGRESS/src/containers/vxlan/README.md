# VXLAN Container

## Purpose  
Decapsulates VXLAN packets (VNI 100) and extracts inner IP packets for NAT processing.

## Configuration
- **VPP Config**: `../../configs/vxlan-config.sh`
- **Network**: chain-1-2 (10.1.1.2), chain-2-3 (10.1.2.1) 
- **Function**: VXLAN tunnel termination and L2 bridging

## Key Features
- VXLAN tunnel creation with VNI 100
- Bridge domain for L2 packet switching
- VXLAN decapsulation and inner packet extraction

## VXLAN Configuration
- **Source IP**: 10.1.1.2
- **Destination IP**: 10.1.1.1  
- **VNI**: 100
- **Decap**: l2 (Layer 2 processing)

## Usage
```bash
# Check VXLAN tunnels
sudo python3 src/main.py debug chain-vxlan "show vxlan tunnel"

# Check bridge domains
docker exec chain-vxlan vppctl show bridge-domain
```