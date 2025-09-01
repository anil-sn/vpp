# VPP & Ubuntu Container Networking Lab

This project provides a fully automated, deterministic environment for testing network connectivity between a container running [Vector Packet Processing (VPP)](https://fd.io/vppproject/) and a standard Ubuntu container.

It serves as a comprehensive, hands-on example of how to integrate VPP's high-performance user-space dataplane with a standard Docker bridge network. The entire lifecycle—build, readiness verification, packet capture, testing, and cleanup—is managed by a single, robust script.

---
## Project Goals & Architecture

The primary goal is to demonstrate a reliable method for integrating a VPP dataplane into a containerized environment and to verify its operation with detailed, low-level packet analysis.

### Key Objectives:
- **Automation:** Provide a single script (`test_connectivity.sh`) to manage the entire test lifecycle.
- **Determinism:** Eliminate race conditions and unreliable `sleep` timers by actively polling for system readiness before running tests.
- **Deep Packet Inspection:** Use native tools (`tcpdump` for the Linux kernel and `vppctl trace` for the VPP dataplane) to capture and analyze traffic at both ends of the connection, proving the theory of operation.
- **Reproducibility:** Use Docker and Docker Compose to create a self-contained, portable lab that runs identically on any machine with Docker installed.

### Network Topology

The architecture consists of a custom Docker bridge network that connects the two containers. VPP is configured to "capture" its container's standard Linux network interface (`eth0`) and manage all traffic directly, bypassing the container's kernel for high performance.

```
+-------------------------------------------------------------------------+
| Docker Host                                                             |
|                                                                         |
|     +-------------------------------------------------------------+     |
|     | Docker Bridge Network (my_vpp_network: 192.168.1.0/24)      |     |
|     +-----------------------+-------------------------------------+     |
|                             | (veth pair)                         |     |
|                             |                                     |     |
| +-------------------------+ | +---------------------------------+ |     |
| | vpp-container           | | | ubuntu-container                | |     |
| |                         | | |                                 | |     |
| |  +-------------------+  | | |  +---------------------------+  | |     |
| |  | VPP Dataplane     |  | | |  | Linux Kernel Network Stack|  | |     |
| |  | (controls eth0)   |  <----->  | (controls eth0)           |  | |     |
| |  | IP: 192.168.1.2   |  | | |  | IP: 192.168.1.3           |  | |     |
| |  +-------------------+  | | |  +---------------------------+  | |     |
| +-------------------------+ | +---------------------------------+ |     |
|                                                                         |
+-------------------------------------------------------------------------+
```

---
## Prerequisites

To run this lab, you will need the following software installed:
- **Docker Engine**: The core platform for running containers.
- **Docker Compose Plugin**: The modern `docker compose` command (with a space) is required. The test script will fail with older, hyphenated `docker-compose` versions.
- `jq`: A command-line JSON processor used by the test script to parse Docker's output. Install it with your system's package manager (e.g., `sudo apt-get install jq` or `sudo dnf install jq`).
- `sudo` access: Required by the test script to run `tcpdump` on the host's network interfaces.

## File Structure

The project is organized to clearly separate the concerns of each component.

```
.
├── docker-compose.yaml      # Defines the services, network, and static IPs.
├── test_connectivity.sh     # The main, deterministic script to run the entire test.
├── ubuntu-container/
│   └── Dockerfile           # Builds the Ubuntu container with a full suite of networking tools.
└── vpp-container/
    ├── Dockerfile           # Builds the VPP container with the same networking tools.
    └── vpp_startup.sh       # Script run inside the VPP container to configure its interfaces.
```
---
## How to Run the Lab

The entire process is automated by the main test script.

1.  **Make Scripts Executable**

    Ensure all shell scripts have execute permissions.
    ```sh
    chmod +x test_connectivity.sh vpp-container/vpp_startup.sh
    ```

2.  **Run the Test**

    Execute the main script with `sudo` to allow for the host-level packet capture.
    ```sh
    sudo ./test_connectivity.sh
    ```

### Step-by-Step Script Execution Flow

The `test_connectivity.sh` script performs the following actions:

1.  **Cleanup:** It starts by running `docker compose down` to remove any containers and networks from previous runs, ensuring a clean state.
2.  **Build & Start:** It uses `docker compose up --build -d` to build the container images (if they've changed) and start both containers in the background.
3.  **Deterministic Readiness Check:** This is the core of the script's reliability.
    *   **Stage 1 (VPP API Ready):** The script enters a loop, repeatedly checking for the existence of the VPP API socket (`/run/vpp/api.sock`) inside the `vpp-container`. It proceeds only when the VPP process is fully running.
    *   **Stage 2 (Network Path Ready):** After the API is ready, the script enters a second loop. It repeatedly sends a single ping from the `vpp-container` to the `ubuntu-container`. It waits for a `0% packet loss` response, which definitively proves that VPP has configured its interface, has an IP address, and that the entire network path between the containers is operational. This check eliminates all race conditions.
4.  **Start Packet Captures:**
    *   It starts `tcpdump` inside the `ubuntu-container`.
    *   It enables VPP's powerful internal packet tracer (`vppctl trace`) on the `af-packet-input` node.
5.  **Execute Formal Tests:**
    *   It pings from VPP to Ubuntu using `vppctl ping`.
    *   It pings from Ubuntu to VPP using the standard Linux `ping`.
6.  **Stop Captures & Analyze:** The script stops the captures and then displays the results from three distinct viewpoints:
    *   The Ubuntu container's kernel-level view of the traffic (`tshark`).
    *   The VPP dataplane's internal, highly-detailed view of the traffic (`vppctl show trace`).
7.  **Final Cleanup:** The script runs `docker compose down` again to stop and remove the containers and network, leaving the host system clean.

---
## Interpreting the Output

The script's primary value is the detailed analysis it provides at the end. By comparing the packet captures from the two different perspectives (Linux kernel vs. VPP dataplane), you can definitively trace the journey of each packet.

### 1. Analysis: Ubuntu Container's Kernel View
```
========================================================================
  ANALYSIS: Packets from UBUNTU CONTAINER'S KERNEL VIEW (via tshark)
========================================================================
# ... tshark output showing ARP and ICMP packets ...
```
This section shows the network conversation as seen by the standard Linux networking stack inside the Ubuntu container. You will see a perfectly symmetric exchange of packets:
- **ARP Requests/Replies:** The initial Layer 2 address resolution.
- **ICMP Echo Requests/Replies:** The Layer 3 ping packets for both tests.

This confirms what the "client" container is sending and receiving.

### 2. Analysis: VPP's Internal Dataplane Trace
```
============================================================
  ANALYSIS: Packets from VPP's INTERNAL DATAPLANE TRACE
============================================================
# ... detailed VPP trace output showing the VPP graph nodes ...
```
This is the most revealing part of the test. It shows the packet's journey *through VPP's internal processing graph*. You can see:
- `af-packet-input`: The node where VPP receives a packet from the kernel interface it captured. This proves the packet successfully traveled across the Docker bridge and `veth` pair.
- `ethernet-input`, `ip4-input`, `ip4-icmp-input`: Nodes that classify the packet.
- `ip4-icmp-echo-request`: The node that processes the incoming ping.
- `ip4-rewrite`: The node that constructs the reply packet with the correct Ethernet and IP headers.
- `host-eth0-output` / `host-eth0-tx`: Nodes that transmit the reply packet out of the VPP-controlled interface.

---
## In-Depth Packet Walkthrough

This section details the precise journey of a single ICMP packet from the Ubuntu container to the VPP container and back, explaining the role of each component at both Layer 2 (Ethernet/ARP) and Layer 3 (IP/Routing).

### Scenario: `ping 192.168.1.2` from the Ubuntu Container

**Initial State:**
- The **Ubuntu container** has a network namespace with a virtual interface `eth0` (IP `192.168.1.3`), which is controlled by its Linux kernel.
- The **VPP container** has a network namespace, but its `eth0` interface has been captured by the VPP dataplane, which assigned it the IP `192.168.1.2`.
- Both containers are connected via a `veth` pair to the Docker bridge `br-xxxxxxxxxxxx`.

---

#### **Step 1: Route Lookup (Inside Ubuntu Container)**

1.  The `ping` command creates an ICMP Echo Request destined for `192.168.1.2`.
2.  The Ubuntu kernel consults its **routing table**. The destination IP `192.168.1.2` falls within the `192.168.1.0/24` subnet, which the table shows is directly connected to the `eth0` interface.
3.  The kernel determines it does not need to send the packet to a gateway/router; the destination is on the local network segment.

#### **Step 2: ARP Resolution (Layer 2 Address Discovery)**

1.  To build the Ethernet frame, the kernel needs the destination MAC address corresponding to `192.168.1.2`. It checks its **ARP table**.
2.  Assuming the entry is not cached, the kernel pauses the ICMP packet and initiates an ARP request. It crafts a broadcast frame:
    - **Source MAC:** `eth0` MAC of the Ubuntu container.
    - **Destination MAC:** `FF:FF:FF:FF:FF:FF` (Broadcast).
    - **Payload:** "Who has the IP `192.168.1.2`? Tell `192.168.1.3`."
3.  This ARP packet is sent out of the `eth0` interface.

#### **Step 3: Traversing the Bridge (From Ubuntu to VPP)**

1.  The ARP packet exits the Ubuntu container's `eth0` and enters its end of the `veth` pair.
2.  It instantly emerges from the other end of the `veth` pair, which is connected to a port on the Docker bridge (`br-xxxxxxxxxxxx`) on the host.
3.  The Docker bridge, acting as a virtual switch, sees the broadcast destination MAC. It **floods** the ARP request to all of its ports, including the one connected to the VPP container's `veth` pair.

#### **Step 4: VPP Processes the ARP Request**

1.  The broadcast ARP packet travels down the VPP container's `veth` pair and arrives at its `eth0` interface.
2.  The **VPP dataplane** (not the kernel) receives the frame. The `arp-input` node in the VPP graph processes it.
3.  VPP checks its configuration, sees that it owns the IP `192.168.1.2`, and crafts an ARP reply.
4.  VPP sends the unicast ARP reply (destined for the Ubuntu container's MAC address) back out through `host-eth0`, onto the bridge. The Ubuntu container receives it and updates its ARP table with the MAC address for `192.168.1.2`.

#### **Step 5: Sending the ICMP Packet**

1.  With the MAC address now known, the Ubuntu kernel can finally build and send the ICMP Echo Request frame.
2.  It travels the same path: out `eth0`, through the `veth` pair, and onto the Docker bridge.
3.  This time, the destination MAC is a known unicast address. The Docker bridge consults its MAC address table, knows which port the VPP container is on, and **forwards** the frame only to that specific port.

#### **Step 6: VPP Processes the ICMP Packet and Replies**

1.  The ICMP packet arrives at the VPP container's `eth0` and is processed by the VPP dataplane (`af-packet-input` node).
2.  The VPP graph identifies it as an ICMP Echo Request for an IP it owns (`ip4-icmp-echo-request` node).
3.  VPP constructs an ICMP Echo Reply packet.
4.  It consults its own **IP neighbor table** (VPP's equivalent of an ARP table, which was populated by the earlier ARP exchange) to find the MAC address for `192.168.1.3`.
5.  The `ip4-rewrite` node builds the complete Ethernet frame for the reply.
6.  The packet is sent out `host-eth0`, forwarded by the bridge directly to the Ubuntu container's `veth` port, and received by the Ubuntu kernel, completing the ping.