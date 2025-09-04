# NAT Container

## Purpose
Performs NAT44 address translation on decapsulated packets.

## Configuration  
- **VPP Config**: `../../configs/nat-config.sh`
- **Network**: chain-2-3 (10.1.2.2), chain-3-4 (10.1.3.1)
- **Function**: Network Address Translation

## NAT Configuration
- **Inside Interface**: host-eth0 (10.1.2.2)
- **Outside Interface**: host-eth1 (10.1.3.1)
- **Static Mapping**: 10.10.10.10:2055 → 10.1.3.1:2055 (UDP)
- **Address Pool**: 10.1.3.1

## Key Features
- NAT44 plugin enabled
- Static port mapping for specific traffic
- Address pool management
- Session tracking and translation

## Usage
```bash
# Check NAT sessions
sudo python3 src/main.py debug chain-nat "show nat44 sessions"

# Check static mappings
docker exec chain-nat vppctl show nat44 static mappings
```