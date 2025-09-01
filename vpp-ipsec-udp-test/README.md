### **VPP IPsec Tunnel Design Document**

| **Author:** | AI Assistant | **Version:** | 1.0 |
| :--- | :--- | :--- | :--- |
| **Date:** | Aug 27, 2025 | **Status:** | Final |

### **Section 1: Introduction and Objectives**

#### **1.1. Overview**

This document details the design and implementation of a high-performance, site-to-site IPsec VPN tunnel using the Vector Packet Processing (VPP) data plane. The architecture is deployed in a containerized environment simulating a connection between two separate cloud networks, designated `AWS` and `GCP`.

The primary goal is to establish a secure and robust overlay network that can transparently handle various traffic types, including large packets that exceed the standard Internet MTU (jumbo frames). The design focuses on verifying advanced VPP features such as IP fragmentation and reassembly within the context of an IPsec tunnel.

#### **1.2. Business and Technical Objectives**

This project aims to achieve the following:

-   **Objective 1: Secure Site-to-Site Connectivity:** Establish a secure, encrypted tunnel between two distinct private networks (`10.0.1.0/24` for `AWS` and `10.0.2.0/24` for `GCP`) over a simulated public, untrusted network (`192.168.1.0/24`).
-   **Objective 2: High-Performance Data Plane:** Utilize VPP as the core data plane engine to achieve high-throughput packet processing, bypassing the standard Linux kernel networking stack for tunnel traffic.
-   **Objective 3: Jumbo Frame Transit:** Demonstrate the ability of the end-to-end solution to pass jumbo frames (packets with an MTU greater than 1500 bytes) without fragmentation, proving the correct configuration of the entire network path.
-   **Objective 4: Robust IP Fragmentation and Reassembly:** Prove that VPP can seamlessly handle cases where a large packet *must* be fragmented to traverse a network link with a smaller MTU. The system must correctly fragment the packet before encryption and reassemble it after decryption without data loss.
-   **Objective 5: Automation and Repeatability:** The entire environment must be defined and managed through version-controlled scripts, allowing for automated, one-command deployment, testing, and teardown.

#### **1.3. Scope**

-   **In Scope:**
    -   Host network setup using Linux bridges and `veth` pairs.
    -   Containerization of VPP nodes using Docker.
    -   Configuration of VPP interfaces (TAP, `af_packet`).
    -   Configuration of a policy-based IPsec tunnel using IPIP encapsulation.
    -   End-to-end MTU path configuration for jumbo frames.
    -   Verification of basic connectivity, jumbo frame transit, and fragmentation/reassembly via `ping`.

-   **Out of Scope:**
    -   Performance benchmarking (e.g., using `iperf3`).
    -   High-availability (HA) or redundant tunnel configurations.
    -   Dynamic routing protocols (e.g., BGP) over the tunnel.
    -   Firewalling (ACLs) or Network Address Translation (NAT) rules.
    -   Internet Key Exchange (IKEv2) for dynamic key management; this design uses static keys for simplicity.

---

### **Section 2: Network Architecture and Design**

#### **2.1. Layered Network Model**

The architecture is best understood as a three-layer model, with each layer serving a distinct purpose and having its own addressing and MTU considerations.

-   **Layer 1: Host Underlay Network:** This represents the physical or public network over which the encrypted traffic will travel.
-   **Layer 2: VPP Data Plane:** This is the high-performance core of the solution, responsible for all packet processing, routing, and cryptographic operations.
-   **Layer 3: Overlay Network:** This is the virtual private network visible to the end-user applications running in the containers' Linux kernels.

#### **2.2. Detailed Component Design**

##### **2.2.1. Host Underlay Network (`192.168.1.0/24`)**

-   **Component:** Linux Bridge (`br0`)
    -   **Purpose:** Simulates an unsecure Layer 2 network (like the internet or a data center fabric) connecting the two sites.
    -   **Configuration:**
        -   **MTU:** `9000` bytes. This is the foundational requirement for jumbo frame support. By setting the MTU on the bridge, we ensure the entire underlay fabric can physically transport large frames without fragmentation.
        -   **IP Address:** The bridge itself does not require an IP address; it functions purely as a Layer 2 switch.

-   **Component:** Virtual Ethernet (`veth`) Pairs (e.g., `aws-br`/`aws-phy`)
    -   **Purpose:** Act as virtual "patch cables" connecting the isolated network namespace of each Docker container to the host's bridge.
    -   **Configuration:**
        -   **`aws-br` / `gcp-br` (Host Side):** Attached to `br0`. MTU is set to `9000` to match the bridge.
        -   **`aws-phy` / `gcp-phy` (Container Side):** Moved into the container's network namespace. VPP will bind to this interface. Its MTU is also effectively 9000 upon creation.

##### **2.2.2. VPP Data Plane**

-   **Component:** `af_packet` Interface (`host-aws-phy`, `host-gcp-phy`)
    -   **Purpose:** This VPP driver binds directly to a kernel network interface (`aws-phy`, `gcp-phy`), pulling it out of the kernel's control and into the VPP data plane. This "zero-copy" mechanism is key to VPP's performance.
    -   **Configuration:**
        -   **IP Address:** `192.168.1.2/24` (AWS) and `192.168.1.3/24` (GCP). These are the public-facing "endpoint" addresses for the IPsec tunnel.
        -   **Packet MTU:** Explicitly set to `9000` bytes using `set interface mtu packet 9000`. This command allocates large physical receive buffers, which is critical for ingesting jumbo frames from the underlay.

-   **Component:** `TAP` Interface (`tap0`)
    -   **Purpose:** Provides a high-speed, memory-mapped connection between VPP and the Linux kernel *within the same container*. Applications in the container send traffic to VPP through this interface.
    -   **Configuration:**
        -   **IP Address:** `10.0.1.2/24` (AWS) and `10.0.2.2/24` (GCP). This IP serves as the default gateway for the container's Linux kernel.
        -   **Packet MTU:** Explicitly set to `9000` bytes. This allows VPP to receive large, unfragmented packets from the local Linux application.

-   **Component:** `IPIP` Tunnel Interface (`ipip0`)
    -   **Purpose:** Serves as the logical "input" for the IPsec encryption engine. Any packet routed to this virtual interface will be encapsulated and encrypted according to the IPsec policy.
    -   **Configuration:**
        -   **Source/Destination:** `192.168.1.2` / `192.168.1.3`. These define the outer IP headers for the encapsulated packet.
        -   **IPsec Protection:** Bound to the pre-configured Security Associations.
        -   **Packet MTU:** Explicitly set to `1400` bytes. **This is a deliberate bottleneck.** It forces VPP's `ip4-fragment` node to act on any packet larger than 1400 bytes, allowing us to test the fragmentation/reassembly feature.
        -   **IP Table:** Assigned to table `0` to ensure it is a fully functional Layer 3 interface capable of handling post-decryption routing decisions.

##### **2.2.3. Overlay Network (`10.0.1.0/24`, `10.0.2.0/24`)**

-   **Component:** Container's Linux Kernel (`vpp-linux` interface)
    -   **Purpose:** Represents the "application" layer. This is where the `ping` command is executed.
    -   **Configuration:**
        -   **IP Address:** `10.0.1.1/24` (AWS) and `10.0.2.1/24` (GCP). These are the private IPs of the "application servers".
        -   **MTU:** Explicitly set to `9000` bytes. This is the final critical link in the chain, allowing the kernel to generate a large packet and send it to VPP without first fragmenting it.
        -   **Default Gateway:** The kernel's default route for the remote private network points to VPP's `tap0` interface IP (`10.0.1.2` or `10.0.2.2`).   

---

### **Section 3: Packet Flow and Data Plane Logic**

This section details the precise journey of a packet through the system. Understanding the packet flow at each step is critical for configuration and troubleshooting. We will trace a jumbo frame ICMP packet from its origin in the AWS container's Linux kernel to the destination in the GCP container's kernel.

#### **3.1. High-Level Packet Journey**

1.  **Origination:** The `ping` command in the AWS container's kernel creates an 8028-byte ICMP packet (`10.0.1.1` -> `10.0.2.1`).
2.  **Forwarding to VPP:** The AWS kernel's routing table directs the packet to its gateway (`10.0.1.2`) via the `vpp-linux` interface (MTU 9000).
3.  **VPP Ingress & Fragmentation (AWS):** VPP receives the 8028-byte packet on its `tap0` interface. VPP's routing table directs this packet to the `ipip0` tunnel interface. Since `ipip0` has an MTU of 1400, VPP's `ip4-fragment` node breaks the 8028-byte packet into six smaller IP fragments.
4.  **IPsec Encapsulation (AWS):** Each of the six IP fragments is individually processed by the `ipip0` tunnel. It is encapsulated first with an IPIP header and then encrypted and encapsulated with an IPsec ESP header. The final outer IP header is `192.168.1.2` -> `192.168.1.3`.
5.  **Underlay Transit:** The six small, encrypted packets are sent out of VPP's `host-aws-phy` interface, across the host's `br0` bridge, and into VPP's `host-gcp-phy` interface on the other side.
6.  **IPsec Decapsulation (GCP):** VPP in the GCP container receives the six encrypted packets. The IPsec engine decrypts each one, stripping the ESP and IPIP headers. This reveals the six original IP fragments.
7.  **IP Reassembly (GCP):** The `ip4-reassembly` node in VPP gathers the six fragments. Once all fragments for the original packet have arrived, it reassembles them back into the single 8028-byte ICMP packet.
8.  **Forwarding to Kernel (GCP):** VPP's routing table directs the now-reassembled 8028-byte packet to its destination (`10.0.2.1`) via the `tap0` interface.
9.  **Termination:** The GCP container's Linux kernel receives the 8028-byte ICMP packet on its `vpp-linux` interface and processes the ping.

The return path for the ICMP reply follows the exact same process in reverse.

#### **3.2. Detailed VPP Node Graph Logic**

-   **On the Sending Node (AWS):**
    1.  `tap-input`: Packet is received from the Linux kernel.
    2.  `ip4-lookup`: VPP's Forwarding Information Base (FIB) is consulted. The route `10.0.2.0/24 via ipip0` is matched.
    3.  `ip4-fragment`: VPP compares the packet size (8028) to the egress interface MTU (1400). It fragments the packet.
    4.  `ipip4-tunnel`: The (now smaller) fragments are passed to the tunnel. It adds the outer `192.168.1.2 -> 192.168.1.3` header.
    5.  `ipsec4-encrypt-tun`: The `ipsec tunnel protect` configuration intercepts the packets. They are encrypted using the parameters from the outbound SA (SPI 1000).
    6.  `ip4-lookup`: A second FIB lookup is performed for the outer destination `192.168.1.3`. This matches the directly connected `host-aws-phy` interface.
    7.  `af-packet-output`: The final, encrypted packets are queued for transmission onto the host `veth` pair.

-   **On the Receiving Node (GCP):**
    1.  `af-packet-input`: Encrypted packets are received from the host `veth` pair.
    2.  `ip4-lookup`: The FIB is consulted for the outer destination `192.168.1.3`. This is a local address, so the packet is passed up the stack.
    3.  `esp4-decrypt-tun`: The ESP header is processed. Based on the SPI (1000), VPP finds the correct inbound SA and decrypts the packet.
    4.  `ipip4-tunnel`: The IPIP header is removed. This reveals the inner IP packet, which is one of the original fragments.
    5.  `ip4-reassembly`: VPP's reassembly engine holds onto the fragment and waits for its siblings. Once all fragments of a single datagram have arrived, it reassembles them.
    6.  `ip4-lookup`: A FIB lookup is performed on the *reassembled* packet. The route `10.0.2.0/24 via tap0` is matched.
    7.  `tap-output`: The large, reassembled packet is queued for transmission to the GCP container's Linux kernel.

---

### **Section 4: Configuration Details**

This section provides a detailed breakdown of the key configuration files and explains the rationale behind important commands.

#### **4.1. VPP Startup Configuration (`aws-startup.conf`, `gcp-startup.conf`)**

The startup configuration is intentionally minimal to ensure stability. The critical component is the `plugins` stanza, which enables the necessary VPP features at boot time.

```
plugins {
  plugin default { enable }
  plugin crypto_native_plugin.so { enable } // Hardware-accelerated crypto (if available)
  plugin ipsec_plugin.so { enable }         // Core IPsec functionality
  plugin ping_plugin.so { enable }         // Enables 'vppctl ping' for underlay tests
  plugin af_packet_plugin.so { enable }    // Driver for connecting to host veth pairs
}
```

-   **Rationale:** Only essential plugins are loaded. This reduces the memory footprint and attack surface of the VPP instance. `af_packet` is the high-performance choice for connecting to the host kernel interfaces.

#### **4.2. VPP Data Plane Configuration (`aws-config.sh`)**

This script contains the sequence of `vppctl` commands that build the data plane. The order of operations is critical.

**Interface MTU Configuration:**
```bash
# Bring the interface DOWN before changing its physical properties.
vppctl set interface state tap0 down
# 'mtu packet 9000' allocates large hardware-level packet buffers.
vppctl set interface mtu packet 9000 tap0
# Bring the interface back UP with the new configuration.
vppctl set interface state tap0 up
```
-   **Rationale:** This `DOWN -> CONFIGURE -> UP` sequence is the most important concept for successfully configuring jumbo frames in VPP. The `packet` keyword in the `mtu` command is what changes the underlying buffer size, which is a physical property that can only be modified when the interface is administratively down. This is applied to both the `tap0` and `host-aws-phy` interfaces.

**IPsec and Tunnel Configuration:**
```bash
# Create the virtual IPIP tunnel interface.
vppctl create ipip tunnel src 192.168.1.2 dst 192.168.1.3

# Bind the pre-configured Security Associations to the tunnel.
vppctl ipsec tunnel protect ipip0 sa-in 2000 sa-out 1000

# Deliberately create an MTU bottleneck to force fragmentation.
vppctl set interface mtu packet 1400 ipip0

# Make the tunnel a fully-featured Layer 3 interface.
vppctl set interface ip table ipip0 0
vppctl set interface ip address ipip0 169.254.1.1/30
vppctl set interface state ipip0 up
```
-   **Rationale:** The configuration is built in layers. First, the basic tunnel is created. Then, the IPsec policy is attached. Finally, its Layer 3 properties (MTU, IP table, IP address) are configured. Setting the MTU to 1400 is the key to forcing the fragmentation test case.

**Routing Configuration:**
```bash
# Route traffic for the remote private network INTO the tunnel.
vppctl ip route add 10.0.2.0/24 via ipip0

# Route decrypted traffic for the local private network OUT to the kernel via the TAP.
vppctl ip route add 10.0.1.0/24 via tap0
```
-   **Rationale:** This demonstrates a classic "split routing" model. One route directs traffic *into* the encryption domain, while a separate route directs traffic *out of* the decryption domain.

#### **4.3. Linux Kernel Configuration (within `aws-config.sh`)**

VPP configures its own data plane, but it must also configure the container's local Linux kernel to correctly use VPP.

```bash
# Set a jumbo MTU on the Linux side of the TAP to match the VPP side.
ip link set dev vpp-linux mtu 9000

# Add a route in the Linux kernel to send traffic for the remote network to VPP.
ip route add 10.0.2.0/24 via 10.0.1.2
```
-   **Rationale:** The `vpp-linux` interface is the boundary between the kernel and VPP. Both sides of this boundary must have the same MTU. The route tells the kernel, "To reach the GCP network, your next hop is the VPP data plane, accessible at `10.0.1.2`."

---

### **Section 5: Test Plan and Verification**

The `test.sh` script serves as the automated test plan for this design. It provides a comprehensive suite of verifications to ensure all objectives have been met. Each test is designed to validate a specific aspect of the configuration, building upon the success of the previous test.

#### **5.1. Test Cases**

The test suite is executed in a specific order to diagnose problems logically.

-   **Test Case 1: Underlay Connectivity Verification**
    -   **Command:** `docker exec AWS vppctl ping 192.168.1.3`
    -   **Purpose:** To confirm basic Layer 3 connectivity between the two VPP instances over the unencrypted underlay network.
    -   **Success Criteria:** The ping must succeed with 0% packet loss. A failure here indicates a problem with the host `br0`, the `veth` pairs, or the `af_packet` interfaces in VPP.

-   **Test Case 2: Overlay ARP Resolution ("Warm-up Ping")**
    -   **Command:** `docker exec AWS ping -c 1 -W 2 10.0.2.1 || true`
    -   **Purpose:** To trigger the dynamic ARP process for the overlay network. The first time VPP2 receives a packet for `10.0.2.1`, it must send an ARP request to its local kernel to discover the MAC address of the `vpp-linux` interface.
    -   **Success Criteria:** This ping is expected to fail (100% packet loss) as VPP drops the initial packet while performing ARP. The `|| true` ensures the script continues.

-   **Test Case 3: Standard Overlay Connectivity**
    -   **Command:** `docker exec AWS ping -c 3 10.0.2.1`
    -   **Purpose:** To confirm that the IPsec tunnel is fully established and can pass standard-sized traffic.
    -   **Success Criteria:** The ping must succeed with 0% packet loss. A failure here points to an issue with the IPsec SAs, the tunnel protection, or the VPP routing logic.

-   **Test Case 4: MTU Bottleneck Verification**
    -   **Command:** `docker exec AWS ping -c 1 -s 1472 -M do 10.0.2.1 || true`
    -   **Purpose:** To prove that the MTU of `1400` on the `ipip0` interface is being correctly enforced. We send a 1500-byte packet with the "Don't Fragment" bit set.
    -   **Success Criteria:** The test succeeds if the `ping` command fails and VPP sends back an ICMP "Fragmentation Needed" error. This confirms the bottleneck is in place as designed.

-   **Test Case 5: Jumbo Frame Fragmentation & Reassembly**
    -   **Command:** `docker exec AWS ping -c 3 -s 8000 10.0.2.1`
    -   **Purpose:** This is the ultimate test of the design. It sends a large frame that is allowed to be fragmented.
    -   **Success Criteria:** The ping must succeed with 0% packet loss. This definitively proves that VPP on the AWS side correctly fragmented the 8028-byte packet, and VPP on the GCP side correctly reassembled it before forwarding it to the destination kernel.

#### **5.2. Post-Test Probes**

After the tests are complete, the script runs several commands to capture the final state of the VPP data plane, providing statistical evidence of the test's success.

-   **Probe 1: VPP Error Counters (AWS)**
    -   **Command:** `docker exec AWS vppctl show error`
    -   **Purpose:** To inspect the internal processing counters of the sending node.
    -   **Expected Result:** The output should show a non-zero count for nodes related to fragmentation, such as `ip4-fragment: packets fragmented`, and a count of `1` for `ip4-input: ip4 MTU exceeded and DF set`, corresponding to the single packet from Test Case 4.

-   **Probe 2: VPP Interface Counters (GCP)**
    -   **Command:** `docker exec GCP vppctl show int`
    -   **Purpose:** To show the final packet and byte counters on the receiving node's interfaces.
    -   **Expected Result:** The counters should show a significantly higher number of packets received on the `host-gcp-phy` interface than on the `tap0` interface. This is because VPP received multiple small fragments for each large ICMP packet that was ultimately delivered to the kernel, providing further proof of reassembly.