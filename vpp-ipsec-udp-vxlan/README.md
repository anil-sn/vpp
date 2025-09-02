# VPP VXLAN Decapsulation, NAT, and IPsec Forwarding Simulation

VXLAN Decapsulation -> NAT -> IPsec Encapsulation

This project provides a complete, containerized simulation of a sophisticated cloud networking architecture. It demonstrates how VPP (Vector Packet Processing) can be used to replicate the functionality of a custom Linux-based network forwarding appliance for mirroring and processing traffic.

## The Real-World Scenario

### High-Level Purpose

This architecture is designed to mirror live network traffic (specifically Netflow, sFlow, or IPFIX data) from an AWS environment and forward it to a processing service running in Google Kubernetes Engine (GKE) within the Google Cloud Platform (GCP). A primary requirement of this solution is to preserve the original source IP address of the traffic throughout the entire process.

### The Core Technical Challenge

The main obstacle this system overcomes is related to how networking operates at Layer 2 (MAC addresses) and Layer 3 (IP addresses) within a virtualized cloud environment.

When AWS Traffic Mirroring captures a network packet, it wraps it in a VXLAN header and sends it to a destination. The "Mirror Target EC2" instances in this design receive and decapsulate this VXLAN packet. The packet that emerges is an exact copy of the original, including its original destination MAC address.

The Linux kernel on the EC2 instance, upon seeing a packet with a destination MAC address that doesn't belong to any of its own network interfaces, would not process it up to the IP layer for routing. Instead, it would attempt to forward it at Layer 2. This packet would then be dropped by the AWS network infrastructure, which enforces a security check that the source MAC address of any outgoing packet must match the MAC of the Elastic Network Interface (ENI) it is leaving from.

### The Linux-Based Solution: A Multi-Layer Forwarding Engine

To solve this, the real-world "Mirror Target EC2" instances are configured as sophisticated forwarding engines using a combination of standard Linux networking utilities:

*   **Dual Network Interfaces (ENIs):** Each EC2 instance uses two ENIs: a primary one and a secondary one dedicated to the forwarding task.
*   **VXLAN Decapsulation:** A virtual VXLAN interface (`vxlan1`) is created to listen for the mirrored traffic on UDP port 4789 and automatically decapsulate it.
*   **Virtual Bridge:** A network bridge (`br0`) is set up to act as a virtual switch, connecting the VXLAN interface and the secondary ENI.
*   **Layer 2 MAC Address NAT (`ebtables`):** This is the crucial step. An `ebtables` rule rewrites the destination MAC address of the decapsulated packet to match the bridge's own MAC address. This tricks the kernel into believing the packet is destined for the EC2 instance itself.
*   **Passing to the IP Stack:** Because the destination MAC now matches a local interface, the kernel passes the packet up from Layer 2 to the IP (Layer 3) stack.
*   **Layer 3 IP Address NAT (`iptables`):** A Destination NAT (DNAT) rule changes the packet's destination IP address and port to that of the service in GCP, while leaving the original source IP untouched.
*   **Routing & Egress:** Custom routing rules and MAC address configuration on the bridge ensure the final packet is sent out correctly without being dropped by AWS security checks.

---

## The VPP Simulation

This project replaces the complex Linux-based forwarding engine with a single, high-performance VPP instance running in a Docker container. VPP's user-space networking stack can perform all the required functions more directly and efficiently.

### Simulated Components

*   **`aws_vpp` container:** This simulates the "Mirror Target EC2" instance. It runs VPP and performs all the core logic.
*   **`gcp_vpp` container:** This simulates the GCP endpoint. It terminates the IPsec tunnel and receives the final traffic.
*   **`send_flows.py` script:** This Python script simulates the AWS Traffic Mirroring source, generating and sending a correctly formatted VXLAN-encapsulated packet to the `aws_vpp` container.

### Traffic Flow within the `aws_vpp` Container

1.  **Ingress:** The `aws_vpp` container receives the VXLAN packet on its `host-aws-phy` interface.
2.  **VXLAN Decapsulation:** The packet is directed to a VPP `vxlan_tunnel0` interface, which decapsulates it, exposing the original inner packet.
3.  **L3 Processing (The VPP Advantage):** Unlike the Linux kernel, VPP does **not** need the complex `ebtables` MAC address hack. As a user-space forwarding plane, once the packet is decapsulated, its inner L3 header is immediately available for processing in the VPP graph.
4.  **Destination NAT (DNAT):** VPP's `nat44` feature performs a static mapping, changing the inner packet's destination IP and port to that of the GCP service, exactly like the `iptables` rule. The original source IP is preserved.
5.  **IPsec Encapsulation:** The modified packet is routed into an IPIP tunnel that is protected by a static IPsec Security Association (SA). VPP encrypts the packet using AES-GCM-128.
6.  **Egress:** The final, encrypted ESP packet is sent out of the `host-aws-phy` interface towards the `gcp_vpp` container.

## How to Run

1.  **Prerequisites:** Docker, Python 3, and the Scapy library (`pip install scapy`).
2.  **Build & Start:** Run `sudo bash ./run_vpp_test.sh`. This script will build the Docker image, create the networks, and start the containers.
3.  **Host Bridge IP:** The host bridge `br0` is assigned `192.168.1.1/24` so the host can reach `aws_vpp (192.168.1.2)` and `gcp_vpp (192.168.1.3)` directly.
4.  **Send Traffic:** In a **new terminal**, run `python3 send_flows.py`.
4.  **Verify:**
    *   Check the NAT session on the AWS side: `sudo bash ./debug.sh aws_vpp show nat44 sessions`
    *   Trace the final decrypted packet on the GCP side:
        *   `sudo bash ./debug.sh gcp_vpp trace add af-packet-input 10`
        *   Run `python3 send_flows.py` again.
        *   `sudo bash ./debug.sh gcp_vpp show trace`
6.  **Cleanup:** Run `sudo bash ./cleanup.sh` to stop and remove all containers and networks.