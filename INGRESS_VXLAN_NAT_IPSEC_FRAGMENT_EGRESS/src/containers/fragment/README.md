# Fragment Container

## Purpose
Fragments large IP packets that exceed MTU limits before final delivery.

## Configuration
- **VPP Config**: `../../configs/fragment-config.sh`
- **Network**: chain-4-5 (10.1.4.2), underlay (192.168.10.20)
- **Function**: IP packet fragmentation

## Fragmentation Configuration
- **Input Interface**: host-eth0 (from IPsec)
- **Output Interface**: host-eth1 (to underlay)
- **MTU Limit**: 1400 bytes
- **Fragment Strategy**: IP-level fragmentation

## Key Features
- Automatic packet fragmentation for >MTU packets
- IP fragmentation and reassembly support
- MTU discovery and handling
- Fragment sequence management

## Usage
```bash  
# Check fragmentation statistics
sudo python3 src/main.py debug chain-fragment "show interface"

# Monitor fragmentation activity
docker exec chain-fragment vppctl show trace
```