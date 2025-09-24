#!/bin/bash
# VXLAN Traffic Redirection Setup for AWS VPP Chain

set -e

log_info() { echo "[INFO] $1"; }
log_success() { echo "[SUCCESS] $1"; }
log_error() { echo "[ERROR] $1"; }

# Get VPP container IP using hostname -I and extract first IP
VPP_CONTAINER_IP=$(docker exec vxlan-processor hostname -I 2>/dev/null | awk '{print $1}')

if [ -z "$VPP_CONTAINER_IP" ]; then
    log_error "Cannot get vxlan-processor container IP"
    exit 1
fi

if [ -z "$VPP_CONTAINER_IP" ]; then
    log_error "Cannot find vxlan-processor container IP"
    exit 1
fi

log_info "VPP Container IP: $VPP_CONTAINER_IP"

# Backup current iptables rules
BACKUP_FILE="/tmp/iptables_backup_$(date +%Y%m%d_%H%M%S).rules"
iptables-save > "$BACKUP_FILE"
log_info "Iptables backed up to: $BACKUP_FILE"

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Redirect VXLAN traffic from ens5 to VPP container
log_info "Setting up VXLAN traffic redirection..."

# Method 1: Direct NAT redirection
iptables -t nat -A PREROUTING -i ens5 -p udp --dport 4789 -j DNAT --to-destination $VPP_CONTAINER_IP:4789

# Method 2: Bridge integration (alternative)
# Create bridge interface for VPP integration
if ! ip link show br-vxlan >/dev/null 2>&1; then
    ip link add name br-vxlan type bridge
    ip link set br-vxlan up
    ip addr add 172.20.100.1/24 dev br-vxlan
    ip link set br-vxlan mtu 9000
fi

# Route VXLAN traffic through bridge to container
iptables -t nat -A POSTROUTING -s 172.20.100.0/24 ! -d 172.20.100.0/24 -j MASQUERADE

log_success "Traffic redirection configured successfully"

# Test connectivity and VPP status
log_info "Testing VPP container connectivity..."
if docker exec vxlan-processor vppctl show version >/dev/null 2>&1; then
    log_success "VPP container is responsive"

    # Show VXLAN tunnel status
    log_info "VXLAN tunnel status:"
    docker exec vxlan-processor vppctl show vxlan tunnel | head -3

    # Show interface status
    log_info "Container interfaces:"
    docker exec vxlan-processor vppctl show interface | grep -E "(host-eth0|host-eth1)" | head -2
else
    log_error "VPP container is not responding"
fi

# Display current redirection status
echo ""
echo "=== VXLAN Traffic Redirection Status ==="
echo "VPP Container: $VPP_CONTAINER_IP:4789"
echo "Backup Rules: $BACKUP_FILE"
echo "Traffic Flow: ens5:4789 → VPP Container:4789"
echo ""
echo "To rollback: iptables-restore < $BACKUP_FILE"