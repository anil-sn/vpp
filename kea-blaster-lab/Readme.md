Of course. Here is a detailed `Readme.md` file based on the complete project structure and file contents you provided.

---

# Kea Control Development Kit (`keactrl`)

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/actions)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Language](https://img.shields.io/badge/language-C-orange.svg)](#)

**`keactrl`** is a high-performance C library (`libkeactrl`) and a companion command-line tool (`keactrl`) for managing the ISC Kea DHCP server ecosystem. It provides a robust, developer-friendly interface to automate and script interactions with Kea's standard Control Agent REST API, making it ideal for integration into larger network management systems, orchestration platforms, and testing frameworks.

The project includes a fully containerized, production-grade lab environment that simulates a multi-VLAN network, allowing for comprehensive, stateful integration testing.

---

## Table of Contents

1.  [Key Features](#key-features)
2.  [Architectural Overview](#architectural-overview)
    - [Pillar 1: The Core Library (`libkeactrl`)](#pillar-1-the-core-library-libkeactrl)
    - [Pillar 2: The Command-Line Interface (`keactrl`)](#pillar-2-the-command-line-interface-keactrl)
    - [Pillar 3: The Docker Lab & Testing Environment](#pillar-3-the-docker-lab--testing-environment)
3.  [Lab Environment & Network Topology](#lab-environment--network-topology)
    - [Services within the Lab](#services-within-the-lab)
    - [Virtual Network Topology](#virtual-network-topology)
4.  [Getting Started: Build and Test](#getting-started-build-and-test)
    - [Prerequisites](#prerequisites)
    - [Option A: Run the Full Test Suite (Recommended)](#option-a-run-the-full-test-suite-recommended)
    - [Option B: Launch an Interactive Lab Shell](#option-b-launch-an-interactive-lab-shell)
    - [Option C: Validate the Lab Environment](#option-c-validate-the-lab-environment)
5.  [Project Directory Structure](#project-directory-structure)
6.  [Core Dependencies](#core-dependencies)

---

## Key Features

-   **Comprehensive API Coverage:** Provides C functions that map directly to Kea Control Agent commands for managing configuration, subnets, leases, statistics, host reservations, and more.
-   **High-Performance C Library:** A clean, lightweight C library (`libkeactrl.so`) with minimal dependencies, perfect for integration into performance-sensitive applications.
-   **Powerful CLI Tool:** A versatile command-line utility (`keactrl`) that exposes the full power of the library, with support for both human-readable tables and machine-readable raw JSON output.
-   **Hermetic Docker Lab:** A self-contained Docker environment that builds a complete Kea ecosystem (`kea-dhcp4`, `kea-dhcp6`, `kea-ctrl-agent`) and a realistic network topology for development and testing.
-   **Stateful Integration Testing:** Includes a C-based test suite that runs against the live lab services, programmatically controlling thousands of simulated DHCP clients using the **BNG Blaster** traffic generator for realistic, end-to-end validation.

## Architectural Overview

The `keactrl` project is built on three distinct but interconnected pillars:

### Pillar 1: The Core Library (`libkeactrl`)

The heart of the project is a shared C library responsible for all communication with the Kea server.

-   **Protocol:** All communication occurs over the standard **HTTP/REST API** provided by the `kea-ctrl-agent`. The library constructs JSON-RPC 2.0 requests and parses the corresponding responses.
-   **Transport Layer:** `libcurl` is used for all HTTP communication, providing a robust, industry-standard, and well-supported transport mechanism.
-   **JSON Handling:** The `cJSON` library is used for creating, parsing, and manipulating all JSON payloads. It is included as a static library to avoid external runtime dependencies.
-   **Abstraction:** The library's core (`src/core/keactrl_core.c`) abstracts away all `libcurl` and JSON-RPC logic. It exposes a clean, high-level C API (`src/include/keactrl.h`) where each function corresponds directly to a Kea API command (e.g., `kea_cmd_subnet4_list()`, `kea_cmd_lease4_del()`).

### Pillar 2: The Command-Line Interface (`keactrl`)

The `keactrl` CLI is a powerful tool built directly on top of `libkeactrl`. It serves as both a reference implementation and a practical utility for system administrators.

-   **Functionality:** Provides shell access to the entire Kea Control Agent API.
-   **Output Formatting:** Features dual output modes:
    -   **Human-Readable (Default):** Formats complex JSON responses into clean, readable tables.
    -   **Raw JSON (`--json`):** Outputs the raw `arguments` payload from the Kea response, perfect for scripting and piping to tools like `jq`.

### Pillar 3: The Docker Lab & Testing Environment

A crucial component is the fully automated, containerized lab environment that provides a consistent and reproducible platform for development and testing.

-   **Containerization:** A single `Dockerfile` defines an Ubuntu 22.04-based image containing all necessary build tools, Kea daemons, and the BNG Blaster traffic generator.
-   **Orchestration:** The `lab/entrypoint.sh` script automatically configures the virtual network topology and starts all required services in the correct order.
-   **Stateful Testing:** The C-based integration test suite (`tests/`) is the key to ensuring correctness. It doesn't just make stateless API calls; it uses a BNG Blaster helper library (`tests/helpers/bngblaster_api.c`) to **programmatically control a DHCP client simulator via its REST API**. This allows tests to:
    1.  Start hundreds or thousands of simulated DHCP clients.
    2.  Wait for them to acquire leases.
    3.  Use `libkeactrl` to query Kea for lease information or statistics.
    4.  Verify that Kea's state matches the expected outcome.
    5.  Modify Kea's configuration on the fly and ensure clients can still operate.
    6.  Terminate the simulated clients and clean up.

## Lab Environment & Network Topology

The lab environment is designed to simulate a real-world scenario where a DHCP server serves clients across multiple VLANs.

### Services within the Lab

The Docker container runs the following services in the background:

-   **`kea-dhcp4` & `kea-dhcp6`:** The core ISC Kea DHCP servers.
-   **`kea-ctrl-agent`:** The control agent that exposes the REST API on port `8000`.
-   **`radvd`:** The Router Advertisement Daemon, essential for IPv6 clients to discover the network and learn that they must use DHCPv6 for addressing.
-   **`bngblaster-controller`:** The control daemon for the BNG Blaster traffic generator, exposing its own REST API on port `8001` for test automation.

### Virtual Network Topology

The `lab/entrypoint.sh` script dynamically creates a virtual network using Linux bridges and `veth` pairs. This setup mimics a DHCP server connected to a trunk port on a switch.

-   **`veth` Pairs:** For each logical network, a pair of virtual interfaces is created (e.g., `srv-eth1` and `cli-eth1`).
-   **VLAN Tagging:** The "server-side" interface (`srv-eth1`) is used as a trunk, with VLAN sub-interfaces created on it (e.g., `srv-eth1.101`).
-   **Bridging:** Each VLAN sub-interface is attached to a corresponding Linux bridge (e.g., `srv-eth1.101` is attached to `br101`).
-   **Server Interfaces:** The Kea DHCP server is configured to listen on these bridges (`br101`, `br102`, etc.), which also hold the gateway IP addresses.
-   **Client Interfaces:** The BNG Blaster test tool sends traffic from the "client-side" interfaces (`cli-eth1`, `cli-eth2`, etc.), tagging packets with the appropriate VLAN ID.

This design effectively isolates traffic from different client networks and delivers it to the correct server interface.

**Visualized Topology (for VLAN 101):**
You are absolutely right to ask for a clearer explanation. The networking setup is the most complex part of this lab, and a good diagram is essential. Let's break it down with a much clearer analogy and a detailed packet-flow diagram.

The entire setup is designed to simulate a common real-world scenario: a DHCP server connected to a **managed switch** that uses **VLANs** to separate different networks.

---

### The Real-World Analogy

Imagine you have physical hardware:
1.  A **Client PC** (BNG Blaster).
2.  A **DHCP Server** (Kea).
3.  A **Managed Switch** that connects them.

The Linux kernel's networking features (veth pairs, bridges, VLAN sub-interfaces) are used to create a *virtual version* of this exact setup inside a single Docker container.

#### Visualized Topology (Hardware Analogy)

This diagram maps the virtual Linux components to their physical hardware counterparts.

```ascii
+-----------------------------------------------------------------------------------------+
|                                  Docker Lab Container                                   |
|                                                                                         |
|  [ BNG Blaster "Client PC" ]                             [ Kea "DHCP Server" ]          |
|                                                                                         |
|   +------------+                                      +---------------------------+     |
|   |  BNG App   |                                      |         Kea App           |     |
|   +------------+                                      +---------------------------+     |
|        |                                                           ^ (Listens On) |     |
|        | Sends DHCP Request                                        |              |     |
|        v                                                           |              |     |
|   +------------+                                      +---------------------------+     |
|   |  cli-eth1  |                                      |           br101           |     |
|   +------------+                                      | (The "Access Port" for    |     |
|        |                                              |  VLAN 101 / Gateway IP)   |     |
|        |                                              +---------------------------+     |
|        |                                                           ^              |     |
|        +..[ Virtual "Patch Cable" (veth pair) ]....................|..............+     |
|        |                                                           |              |     |
|        v                                                           |              |     |
|   +------------+                                      +---------------------------+     |
|   |  srv-eth1  |<----(Kernel VLAN Logic)---------------+  This entire box is the   |    |
|   +------------+       (srv-eth1.101)                   |   "Virtual Managed Switch"|   |
|   (The "Trunk Port"                                     |  (Linux Bridge & VLANs)   |   |
|    accepting tagged traffic)                            +---------------------------+   |
|                                                                                         |
+-----------------------------------------------------------------------------------------+
```

**Explanation of the Analogy:**

1.  **`cli-eth1` and `srv-eth1` (The Virtual Cable):** The `veth` pair is like a virtual ethernet cable. Whatever BNG Blaster sends into `cli-eth1` instantly comes out of `srv-eth1`, and vice-versa.
2.  **`srv-eth1` (The Trunk Port):** This interface is configured to act like a **trunk port** on a managed switch. It's expecting to receive traffic that has a VLAN tag.
3.  **`br101` (The Virtual Switch / Access Port):** The Linux bridge `br101` acts like a simple virtual switch for a single VLAN. The Kea server's IP address (`192.101.1.1`) is assigned here, making it the gateway for that network. Kea listens on this bridge, just as a server would plug into an **access port** on a switch.
4.  **Kernel VLAN Logic (The Magic):** When a packet tagged for VLAN 101 arrives at the "trunk port" (`srv-eth1`), the kernel's VLAN sub-interface (`srv-eth1.101`) automatically strips the VLAN tag and forwards the clean packet to the `br101` bridge. This is exactly what a real managed switch does internally.

---

### The Packet Lifecycle (Step-by-Step Flow)

This diagram focuses exclusively on the journey of a single DHCP Discover packet.

```ascii
  =========================================================================================
  STEP 1: BNG Blaster Application                                    [ In Application Memory ]
  -----------------------------------------------------------------------------------------
  Payload: [ DHCP Discover ]
  Goal: Get an IP address.

      |
      v

  =========================================================================================
  STEP 2: Interface `cli-eth1`                                       [ Leaving the Client ]
  -----------------------------------------------------------------------------------------
  Frame:   [ Eth Header | VLAN Tag (ID=101) | IP Header | UDP Header | DHCP Discover ]
  Action:  The packet is encapsulated in an Ethernet frame and the VLAN tag is added.

      |
      +-----> (Travels across the virtual veth "cable" to srv-eth1)
      |

  =========================================================================================
  STEP 3: Sub-Interface `srv-eth1.101`                               [ Entering the "Switch" ]
  -----------------------------------------------------------------------------------------
  Frame:   [ Eth Header | IP Header | UDP Header | DHCP Discover ]
  Action:  The kernel sees the VLAN 101 tag on the trunk port (`srv-eth1`) and directs
           the packet to this virtual interface, which STRIPS the VLAN tag.

      |
      v

  =========================================================================================
  STEP 4: Bridge `br101`                                             [ Inside the VLAN ]
  -----------------------------------------------------------------------------------------
  Frame:   [ Eth Header | IP Header | UDP Header | DHCP Discover ]
  Action:  The clean, untagged packet is forwarded onto the bridge, which acts as the
           broadcast domain for the VLAN 101 network.

      |
      v

  =========================================================================================
  STEP 5: Kea DHCP Application                                       [ Received by Server ]
  -----------------------------------------------------------------------------------------
  Payload: [ DHCP Discover ]
  Action:  Kea, listening on `br101`, receives the broadcast packet and begins processing
           the lease request for the 192.101.0.0/16 subnet.
  =========================================================================================
```

### Why is this setup necessary?

This seemingly complex setup is crucial for **realistic and robust testing**. It ensures that:
- The Kea server is correctly configured to listen on the right interfaces.
- The server correctly identifies which subnet a request belongs to based on the interface it arrived on.
- The entire system works in an environment that closely mimics a production network with VLANs, rather than a simple, flat network.

## Getting Started: Build and Test

The entire project lifecycle is managed through simple shell scripts.

### Prerequisites

-   A Linux-based host (or macOS with compatible tools).
-   **Docker** installed and the current user added to the `docker` group.

### Option A: Run the Full Test Suite (Recommended)

This is the simplest way to verify the entire project. It will perform a clean build inside the Docker lab and execute the complete C-based integration test suite. A zero exit code indicates all tests passed.

```bash
./run-test.sh
```

### Option B: Launch an Interactive Lab Shell

This command builds the Docker image and drops you into a `bash` shell inside the running container. The network and all Kea services will be running in the background, allowing you to develop, build, and debug interactively.

```bash
./run-lab.sh
```

Once inside the container, you can use the following workflow:

```bash
# Navigate to the project directory (mounted from your host)
cd /usr/src/keactrl

# Perform a clean build of the library, CLI, and test runner
./build.sh

# Run the keactrl CLI tool
./build/bin/keactrl subnet4-list
./build/bin/keactrl --json config-get dhcp4 | jq .

# Run the full integration test suite
./build/bin/test_runner
```

### Option C: Validate the Lab Environment

This command builds and starts the lab container in the background, waits 10 seconds, and then verifies that all required services have started correctly. It's a quick sanity check for the Docker environment itself.

```bash
./run-lab.sh validate
```
## Core Dependencies

-   **Build-time:** `cmake`, `build-essential` (gcc, make, etc.).
-   **Library (`libkeactrl`):** `libcurl` (for HTTP), `cJSON` (vendored).
-   **Lab Environment:** `Docker`.
-   **Testing:** `bngblaster` (for client simulation).