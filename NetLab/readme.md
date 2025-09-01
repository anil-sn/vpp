# VPP NetLab: A High-Performance L3 Router Simulation

This project creates a robust virtual network lab on a single host to demonstrate and test core routing concepts using Vector Packet Processing (VPP) and standard Linux networking tools. It showcases how VPP can be used as a high-performance virtual router connecting multiple distinct network segments.

The entire lab is orchestrated with a single, idempotent shell script, making it fully automated, reproducible, and easy to explore. It's designed to provide a hands-on understanding of how VPP integrates with the Linux kernel to perform efficient IP routing.

## Table of Contents
1.  [Goals and Objectives](#goals-and-objectives)
2.  [Architecture Diagram](#architecture-diagram)
3.  [Technology Deep Dive](#technology-deep-dive)
    - [Linux Bridge](#linux-bridge)
    - [Veth Pairs](#veth-pairs)
    - [VPP `af_packet`](#vpp-af_packet)
    - [VPP L3 Routing](#vpp-l3-routing)
4.  [File Structure](#file-structure)
5.  [Prerequisites](#prerequisites)
6.  [Usage](#usage)
7.  [Verification and Testing](#verification-and-testing)

## Goals and Objectives

The primary goal is to build a clean, reliable network topology that demonstrates VPP's capabilities as a pure Layer 3 router.

- **Demonstrate Network Segmentation** using separate Linux Bridges to create distinct L2 domains.
- **Showcase High-Performance L3 Routing** by connecting VPP to these L2 domains and routing traffic between them.
- **Integrate VPP with standard Linux networking** using the flexible `af_packet` driver, treating kernel interfaces as VPP ports.
- **Provide a fully automated setup and teardown** for a consistent and repeatable lab environment.
- **Include built-in validation tests** to automatically verify L2 and L3 connectivity upon deployment.

### File 2 of 6: `readme.md` (Architecture and Technology)

```markdown
## Architecture Diagram

The lab simulates a core router (VPP) connecting two separate networks: a "Server Network" and an "External Network". Each network is built on its own Linux bridge, ensuring complete L2 isolation.

```text
       (ns-server1)              (ns-server2)                     (ns-external: "Internet")
    192.168.10.101/24         192.168.10.102/24                      10.0.0.2/24
    +-----------------+         +-----------------+                +-----------------+
    |  veth-srv1-p1   |         |  veth-srv2-p1   |                |  veth-ext-p1    |
    +-------+---------+         +--------+--------+                +--------+--------+
            | (veth)                     | (veth)                           | (veth)
            |                            |                                  |
+-----------|----------------------------|----------------------------------|------------------+
|           |                            |                                  | (Host Machine)   |
|     veth-srv1-p0                 veth-srv2-p0                         veth-ext-p0            |
|           |                            |                                  |                  |
|     +-----> "Server" Linux Bridge <----+                                  |                  |
|     |           (br_srv)               |                                  |                  |
|     |                                  |                      "External" Linux Bridge        |
| veth-vpp-srv                           |                                (br_ext)             |
|     |                                  |                                  ^                  |
|     |                                  |                                  |                  |
|     +----------------------------------+----------------------------> veth-vpp-ext         |
|                                                                                              |
| (VPP Router Container)                                                                       |
| +------------------------------------------------------------------------------------------+ |
| |                        +----------------------------------+                              | |
| |  (af_packet)           |       VPP L3 Routing Logic       |          (af_packet)         | |
| | veth-vpp-srv-p1 <------> (GW: 192.168.10.1/24) <-> (GW: 10.0.0.1/24) <------> veth-vpp-ext-p1 | |
| |                        +----------------------------------+                              | |
| +------------------------------------------------------------------------------------------+ |
|                                                                                              |
+----------------------------------------------------------------------------------------------+
```

## Technology Deep Dive

- **Linux Bridge (`br_srv`, `br_ext`)**: We use two separate Linux bridges to act as simple Layer 2 switches. `br_srv` connects the two servers and VPP's "internal" interface, creating the `192.168.10.0/24` network. `br_ext` connects the external client and VPP's "external" interface, creating the `10.0.0.0/24` network.

- **Veth Pairs**: These are used as virtual "patch cables" throughout the lab to connect network namespaces to the Linux bridges, and to connect the bridges to the VPP container.

- **VPP `af_packet`**: VPP uses the `af_packet` driver to "ingest" standard Linux kernel interfaces (`veth-vpp-srv-p1` and `veth-vpp-ext-p1`) and treat them as native VPP ports. This is the primary mechanism for integrating VPP's high-performance data plane with the host's networking stack.

- **VPP L3 Routing**: The VPP instance is configured as a pure L3 router. It has an IP address on each of its two interfaces, creating two directly connected routes in its Forwarding Information Base (FIB). When a packet arrives on one interface destined for the other network, VPP performs a route lookup and forwards the packet to the correct outgoing interface, rewriting the MAC headers in the process. This is the fundamental function of a router.

### File 3 of 6: `readme.md` (File Structure, Prerequisites, Usage)


## File Structure

The project is organized into a main orchestration script and a library of shell scripts, each responsible for a specific phase of the lab setup.

```
.
├── Dockerfile                 # Builds the custom VPP+Tools image.
├── README.md                  # This file.
├── cleanup.sh                 # Tears down all lab resources idempotently.
├── run_lab.sh                 # The main orchestration script.
├── lib/
│   ├── common.sh              # Shared variables and helper functions.
│   ├── phase1_setup.sh        # Environment and Linux plumbing setup.
│   ├── phase2_tor_config.sh   # VPP router configuration.
│   └── phase4_validation.sh   # Connectivity tests and analysis.
└── vpp-tor-startup.conf       # VPP startup config for the router.
```

## Prerequisites

1.  **Linux Host**: A Linux machine (or a VM/WSL2 environment) with root/sudo access.
2.  **Docker**: Docker must be installed and the current user should have permission to run `sudo docker`.
3.  **Kernel Hugepages**: VPP requires pre-allocated hugepages for performance. The lab script checks for this, but you can configure it manually if needed with:
    ```bash
    sudo sysctl -w vm.nr_hugepages=1024
    ```

## Usage

The entire lab is managed by two primary scripts, `run_lab.sh` and `cleanup.sh`.

1.  **Make scripts executable:**
    ```bash
    chmod +x run_lab.sh cleanup.sh
    ```

2.  **Run the lab:**
    The script will perform all necessary setup, configuration, and testing, printing self-explanatory messages at every step.
    ```bash
    sudo ./run_lab.sh
    ```

3.  **Explore the lab (Optional):**
    Once the script completes, you can interact with the components:
    ```bash
    # Access the VPP router's command line
    sudo docker exec -it vpp-tor-switch vppctl

    # Run a ping from an internal server to the external one
    sudo ip netns exec ns-server1 ping 10.0.0.2
    ```

4.  **Clean up the lab:**
    The cleanup script is robust and will remove all created resources (containers, bridges, namespaces, etc.), returning your system to its previous state.
    ```bash
    sudo ./cleanup.sh
    ```

### File 4 of 6: `readme.md` (Verification and Testing)


## Verification and Testing

The `run_lab.sh` script automatically performs a series of validation tests at the end of the setup process to confirm that the entire topology is working as expected.

1.  **Static IP Configuration**: The script first configures all Linux network namespaces (`ns-server1`, `ns-server2`, `ns-external`) with the appropriate static IP addresses and default routes pointing to the VPP router.

2.  **L2 Connectivity Test**: An intra-network `ping` is performed from `ns-server1` to `ns-server2`.
    *   **Path:** `ns-server1 -> br_srv -> ns-server2`
    *   **Purpose:** This validates that the `br_srv` Linux bridge is functioning correctly as a Layer 2 switch.

3.  **L3 Routing Test**: An inter-network `ping` is performed from `ns-server1` to `ns-external`.
    *   **Path:** `ns-server1 -> br_srv -> VPP -> br_ext -> ns-external`
    *   **Purpose:** This is the key validation test. It confirms that VPP is successfully receiving packets from the server network, making a routing decision based on its FIB, and forwarding the packets to the external network. It validates the end-to-end L3 forwarding path.

4.  **Final State Dump**: After the tests, the script queries the VPP instance and displays its IP neighbor table (`show ip neighbor`), visually confirming that VPP has learned the MAC addresses of the clients it communicated with via the ARP protocol.

---

### File 5 of 6: `vpp-tor-startup.conf`

This is the startup configuration for the VPP router instance. It is now the only VPP config file actively used by the lab.

```ini
# VPP TOR STARTUP
# Version: Final
# Configuration for the VPP instance acting as the lab's main L3 router.
unix {
  # Run in the foreground for better logging within Docker.
  nodaemon
  
  # Specify a log file path inside the container.
  log /var/log/vpp/vpp.log

  # Enable the interactive CLI on a container-specific socket.
  cli-listen /run/vpp/cli.sock
  
  # Specify the directory for runtime files (sockets, etc.).
  runtime-dir /run/vpp

  # Run as root inside the container.
  gid 0
}

# Tell VPP not to look for physical PCI devices.
dpdk {
  no-pci
}
```

---
### File 6 of 6: `vpp-hps-startup.conf` (Now Unused)

This file is no longer used by the simplified lab but is kept here for historical context. It was originally intended for the High-Performance Server which was removed due to VPP plugin incompatibilities.

```ini
# VPP HPS STARTUP
# Version: Unused
# This file is no longer used in the simplified lab.
unix {
  nodaemon
  log /var/log/vpp/vpp.log
  cli-listen /run/vpp/cli.sock
  runtime-dir /run/vpp
  gid 0
}

dpdk {
  no-pci
}
```