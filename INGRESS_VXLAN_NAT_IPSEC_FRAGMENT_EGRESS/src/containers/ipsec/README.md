# IPsec Container

## Purpose
Encrypts packets using ESP (Encapsulating Security Payload) with AES-GCM-128.

## Configuration
- **VPP Config**: `../../configs/ipsec-config.sh` 
- **Network**: chain-3-4 (10.1.3.2), chain-4-5 (10.1.4.1)
- **Function**: IPsec ESP encryption in IPIP tunnel

## IPsec Configuration
- **Encryption**: AES-GCM-128
- **Outbound SA**: SPI 1000 (encrypt)
- **Inbound SA**: SPI 2000 (decrypt)
- **Tunnel**: IPIP (10.1.3.2 → 10.1.4.2)
- **Crypto Key**: 4a506a794f574265564551694d653768

## Key Features
- ESP tunnel mode encryption
- AES-GCM-128 authenticated encryption
- IPIP tunnel encapsulation
- Crypto hardware acceleration support

## Usage
```bash
# Check IPsec SAs
sudo python3 src/main.py debug chain-ipsec "show ipsec sa"

# Check tunnel status
docker exec chain-ipsec vppctl show ipsec tunnel
```