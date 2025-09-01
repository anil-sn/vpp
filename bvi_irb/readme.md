### **VPP Integrated Routing and Bridging (IRB) Lab**

### **Section 1: Overview**

#### **1.1. Introduction**

This document outlines the design and implementation of a self-contained lab environment for demonstrating and testing the Integrated Routing and Bridging (IRB) functionality of the Vector Packet Processing (VPP) platform. IRB allows a single VPP instance to perform both Layer 2 (L2) bridging and Layer 3 (L3) routing on a shared set of interfaces, a critical feature for building advanced virtual network functions (VNFs) like virtual routers and switches.

The entire lab is encapsulated within a set of scripts and a Docker container, ensuring it is portable, reproducible, and can be set up and torn down with single commands.

#### **1.2. Technology Stack**

*   **Packet Forwarding:** Vector Packet Processing (VPP)
*   **Containerization:** Docker
*   **Host Virtualization:** Linux Network Namespaces
*   **Host/VPP Connectivity:** Virtual Ethernet (Tap) Interfaces
*   **Orchestration:** Bash Shell Scripts (`run_vpp_irb_lab.sh`, `cleanup.sh`)

#### **1.3. Goals and Objectives**

The primary goal is to create a clear, working example of VPP's IRB capabilities. The specific objectives are:

1.  **Demonstrate L2 Bridging:** Successfully forward packets between two endpoints (`ns1`, `ns2`) that reside in the same VPP bridge domain.
2.  **Demonstrate L3 Gateway Functionality:** Establish a Bridge Virtual Interface (BVI) to act as the default gateway for the bridged subnet and confirm connectivity from an endpoint to this gateway.
3.  **Demonstrate End-to-End IRB:** Successfully route a packet that originates from an endpoint in the L2 bridge domain, passes through the L3 BVI, and is routed out a separate L3 interface to an external endpoint (`ns3`).
4.  **Ensure Reproducibility:** The entire environment must be built from a standard base (Ubuntu 22.04) and automated via scripts, eliminating manual configuration steps and ensuring consistent results.

### **Section 2: System Architecture**

#### **2.1. Architecture Diagram**

The lab environment is structured as a "router-on-a-stick" topology, where VPP acts as the central routing and switching element connecting multiple isolated network segments (represented by Linux namespaces).

```text
       (Linux Namespace: ns1)          (Linux Namespace: ns2)             (Linux Namespace: ns3)
       +-----------------------+       +-----------------------+          +-----------------------+
       |   Host-side tap0      |       |   Host-side tap1      |          |   Host-side tap2      |
       |   IP: 192.168.10.10/24|       |   IP: 192.168.10.20/24|          |   IP: 10.10.10.2/24   |
       |   GW: 192.168.10.1    |       |   GW: 192.168.10.1    |          | Route: 192.168.10.0/24|
       +-----------+-----------+       +-----------+-----------+          +-----------+-----------+
                   |                               |                                | via 10.10.10.1
                   | (L2 Connection)               | (L2 Connection)                | (L3 Connection)
+------------------|-------------------------------|--------------------------------|-----------------+
|                  |                               |                                |                 |
|                   (VPP running inside a Docker container using --net=host)         |                 |
|                  |                               |                                |                 |
|              VPP tap0                        VPP tap1                         VPP tap2               |
|            (Bridged Port)                  (Bridged Port)                   (Routed Port)        |
|                  \                             /                            IP: 10.10.10.1/24      |
|                   +---------------------------+                                   |                |
|                   |    Bridge Domain 10       |                                   |                |
|                   +---------------------------+                                   |                |
|                              | (Logical L3 Attachment)                            |                |
|                         BVI0 Interface <----------(VPP IP ROUTER)-----------------+                |
|                         IP: 192.168.10.1/24                                                        |
|                                                                                                    |
+----------------------------------------------------------------------------------------------------+
```

#### **2.2. Component Description**

*   **VPP Docker Container (`vpp-irb-lab`)**:
    *   **Role**: The core network processing engine. It hosts the bridge domain, the BVI, and the routed interfaces.
    *   **Configuration**: Built from a minimal `ubuntu:22.04` base image with VPP installed from the official FD.io repository. It uses a custom `startup.conf` to enable the `tuntap` driver for creating virtual interfaces and disables the DPDK PCI scan, as no physical NICs are used. It runs with `--privileged` and `--net=host` flags to allow it to create and manage network interfaces on the host system.

*   **Linux Network Namespaces (`ns1`, `ns2`, `ns3`)**:
    *   **Role**: Simulate isolated end-hosts or virtual machines. Each namespace has its own private network stack.
    *   **`ns1` & `ns2` (LAN Clients)**: Represent two clients on the same local area network. They are configured with IP addresses in the `192.168.10.0/24` subnet and have their default gateway set to the BVI's IP address (`192.168.10.1`).
    *   **`ns3` (WAN Client)**: Represents a client on a separate, external network. It is configured with an IP in the `10.10.10.0/24` subnet and has a static route for the `192.168.10.0/24` LAN, pointing back to VPP's routed interface (`10.10.10.1`).

*   **VPP Bridge Domain (BD 10)**:
    *   **Role**: A virtual Layer 2 switch.
    *   **Function**: It groups the `tap0` and `tap1` interfaces into a single L2 broadcast domain. It learns MAC addresses from ingress traffic and forwards frames between its member ports.

*   **VPP Bridge Virtual Interface (BVI0)**:
    *   **Role**: The key IRB component; the L3 gateway for the bridge domain.
    *   **Function**: It is a virtual routed interface that is logically bound to Bridge Domain 10. By assigning it an IP address (`192.168.10.1/24`), it allows the VPP router to process packets arriving from the bridged segment and to inject routed packets into the bridged segment.


### **Section 3: Implementation and Configuration Details**

This section describes the step-by-step logic encoded within the orchestration scripts.

#### **3.1. Lab Setup (`run_vpp_irb_lab.sh`)**

The setup process is fully automated and follows a strict, sequential order to ensure a stable environment.

*   **Step 0: Cleanup**: The script first calls `cleanup.sh` to remove any artifacts from a previous run, including the Docker container and network namespaces. This guarantees a clean slate for every execution.

*   **Step 1: Container Orchestration**:
    *   A custom Docker image (`vpp-lab-final:latest`) is built if it does not already exist. The `Dockerfile` ensures a consistent VPP version and environment.
    *   The VPP container is started in detached mode. Crucially, it uses `--net=host` and `--privileged` permissions, which are required for VPP to create `tap` interfaces directly on the host operating system.
    *   The script includes a wait-loop that polls `vppctl show version` to ensure VPP is fully initialized before proceeding.

*   **Step 2: VPP-side Interface Creation**:
    *   Using the `vpp_cmd` helper function, VPP is instructed to create three `tap` interfaces (`tap0`, `tap1`, `tap2`). These interfaces are created by VPP's `tuntap` driver but manifest on the host OS, ready to be used.

*   **Step 3: Host-side Network Configuration**:
    *   Three Linux network namespaces (`ns1`, `ns2`, `ns3`) are created using `ip netns add`.
    *   The `tap` interfaces created by VPP are moved from the host's default namespace into their respective network namespaces (`ip link set tap0 netns ns1`, etc.).
    *   Inside each namespace, the interfaces are configured:
        *   The loopback and tap interfaces are brought up (`ip link set dev <if> up`).
        *   IP addresses and default gateways/static routes are assigned using `ip addr add` and `ip route add`, establishing the topology described in the architecture diagram.

*   **Step 4: VPP Network Configuration**:
    *   The VPP-side of the `tap` interfaces are brought up (`set interface state <if> up`).
    *   A bridge domain is created: `create bridge-domain 10`.
    *   `tap0` and `tap1` are assigned to the bridge domain as L2 ports: `set interface l2 bridge tap0 10`.
    *   The IRB functionality is configured using a multi-step process proven to work for the target VPP development version:
        1.  `bvi create`: A BVI is created, which appears as `bvi0`.
        2.  `set interface ip address bvi0 192.168.10.1/24`: The gateway IP is assigned.
        3.  `set interface l2 bridge bvi0 10 bvi`: The BVI is explicitly associated with Bridge Domain 10.
        4.  `set interface state bvi0 up`: The BVI is activated.
    *   The "WAN" interface is configured as a standard L3 port: `set interface ip address tap2 10.10.10.1/24`.
    *   A default route is added to VPP, directing all outbound traffic towards the external client (`ns3`): `ip route add 0.0.0.0/0 via 10.10.10.2 tap2`.

#### **3.2. Lab Teardown (`cleanup.sh`)**

The teardown script is designed to be simple and robust, using `>/dev/null 2>&1` to suppress errors if a resource does not exist (e.g., if the lab setup failed midway).

1.  The Docker container is stopped and then removed.
2.  The network namespaces are deleted. Deleting a namespace automatically removes the virtual interfaces (`tap0`, `tap1`, `tap2`) contained within it.
3.  As a failsafe, the script attempts to delete the `tap` interfaces from the host directly, in case they were orphaned.

### **Section 4: Verification and Testing**

The script includes a dedicated verification phase to programmatically validate that the IRB functionality is working as designed. This phase executes three distinct tests, each probing a different data path through the VPP instance.

#### **4.1. Test Plan**

The verification is performed by initiating `ping` commands from within the network namespaces. The success or failure of these pings validates the configuration of the data plane.

*   **Test 1: Intra-Bridge Domain Communication (L2 Path)**
    *   **Command:** `ip netns exec ns1 ping -c 4 192.168.10.20`
    *   **Purpose:** To verify pure Layer 2 bridging.
    *   **Expected Packet Flow:**
        1.  `ns1` sends an ICMP request to `ns2`.
        2.  The packet travels `ns1(tap0)` -> `VPP(tap0)`.
        3.  VPP's Bridge Domain 10 performs a MAC address lookup and forwards the packet directly to `VPP(tap1)`.
        4.  The packet is received by `ns2(tap1)`.
    *   **Success Criteria:** 0% packet loss. This test should pass even if the BVI configuration is incorrect, as it only exercises the L2 data path.

*   **Test 2: Gateway Communication (L2 to BVI Path)**
    *   **Command:** `ip netns exec ns1 ping -c 4 192.168.10.1`
    *   **Purpose:** To verify that endpoints on the bridged segment can reach their L3 gateway (the BVI).
    *   **Expected Packet Flow:**
        1.  `ns1` sends an ICMP request to its configured gateway, `192.168.10.1`.
        2.  The packet travels `ns1(tap0)` -> `VPP(tap0)`.
        3.  VPP's L2 input node sees that the destination MAC address belongs to its own `bvi0` interface.
        4.  The packet is consumed by VPP's L3 stack, which generates an ICMP reply.
    *   **Success Criteria:** 0% packet loss.

*   **Test 3: End-to-End Routed Communication (IRB Path)**
    *   **Command:** `ip netns exec ns1 ping -c 4 10.10.10.2`
    *   **Purpose:** To verify the complete Integrated Routing and Bridging functionality.
    *   **Expected Packet Flow:**
        1.  `ns1` sends an ICMP request for an external IP (`10.10.10.2`) to its gateway (`192.168.10.1`).
        2.  The packet arrives on `VPP(tap0)` and is passed to the L2 bridging path.
        3.  The packet's destination MAC is the BVI's, so VPP's IRB logic "pulls" the packet up to the L3 router.
        4.  The VPP IP router performs a FIB lookup for `10.10.10.2` and finds the default route via `10.10.10.2` on `tap2`.
        5.  The packet is routed and transmitted out of the `VPP(tap2)` interface.
        6.  The ICMP reply follows the reverse path.
    *   **Success Criteria:** 0% packet loss.

#### **4.2. Debugging and Failure Analysis**

The `run_vpp_irb_lab.sh` script is designed for robust failure analysis.

*   **`set -e`**: The script will exit immediately if any command fails.
*   **`trap fail_and_dump ERR`**: An error trap is set at the beginning of the script. If any command exits with a non-zero status, the `fail_and_dump` function is automatically executed before the script terminates.
*   **`fail_and_dump` Function**: This function provides a comprehensive snapshot of the system's state at the moment of failure, printing the following information:
    *   Docker container logs.
    *   VPP interface status (`show interface`).
    *   VPP IP routing table (`show ip fib`).
    *   VPP Neighbor/ARP table (`show ip neighbor`).
    *   VPP bridge domain details (`show bridge-domain 10 detail`).
    *   Host link status in the default and all network namespaces.

This automated state dump is critical for quickly diagnosing configuration errors, syntax issues with different VPP versions, or race conditions.


