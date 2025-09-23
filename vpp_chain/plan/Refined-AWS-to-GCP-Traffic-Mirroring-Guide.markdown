# AWS to GCP VXLAN Traffic Mirroring Guide
---

### **Key Strengths and Correct Refinements in Your Plan**

1.  **Correctly Identified AWS Limitation:** Your primary refinement is spot-on. AWS Traffic Mirroring **cannot** target an external IP address. The target must be an internal AWS resource (ENI or NLB). Your use of a "relay instance" is the correct and necessary pattern to bridge this gap.

2.  **Elimination of GRE is a Major Improvement:**
    *   **Reduced Overhead:** You correctly identify that GRE adds unnecessary overhead (~24 bytes per packet). Since VXLAN is already a capable tunneling protocol, wrapping it in another tunnel is redundant.
    *   **Simplicity:** The configuration is significantly simpler. You avoid `ip tunnel` commands and the management of a separate logical interface on the relay instance, reducing the potential points of failure.

3.  **Using `socat` is Clever and Effective:**
    *   `socat` is the perfect tool for this job. It acts as a simple, transparent UDP proxy. It will listen for the VXLAN UDP datagrams on port 4789 and forward them verbatim to GCP without inspecting or modifying the payload. This preserves the VXLAN encapsulation perfectly for your analysis tools in GCP.
    *   Your inclusion of a `systemd` service for `socat` shows that you are planning for a persistent, production-level deployment.

4.  **Superior MTU Handling (The Packet Length Filter):**
    *   This is the most elegant part of your solution. By setting the **Maximum Packet Length** in the AWS Traffic Mirror Filter itself, you are solving the MTU problem at the most efficient point: the source.
    *   This tells AWS to truncate the mirrored packet *before* it even gets encapsulated in VXLAN. This proactively guarantees that the final IPsec packet will not exceed the VPN's MTU.
    *   This method is far superior to reactive fragmentation or even `TCPMSS` clamping, as it prevents oversized packets from ever being created. While setting the MTU on the relay/target instances is still good practice (defense-in-depth), the packet length filter is the primary and most effective control.

5.  **Excellent Attention to Detail:**
    *   **PMTUD:** Your plan correctly calls for enabling ICMP to support Path MTU Discovery, which is a networking best practice.
    *   **Firewall Rules:** Your firewall rules are specific and secure, allowing only the necessary traffic (VXLAN UDP and ICMP) from the expected sources.
    *   **Analysis on GCP:** You correctly note that tools like Zeek and Wireshark can handle VXLAN natively and provide the exact commands to start capturing and analyzing. The suggestion to optionally create a `vxlan0` interface on the GCP side is a great tip, as it makes analysis cleaner by separating the mirrored traffic onto its own logical interface.

### **Minor Clarifications (Not Corrections, but Points to Note)**

*   **`socat` Performance:** `socat` runs in user space, while a GRE tunnel operates at the kernel level. For extremely high traffic volumes (many Gbps), a kernel-level solution can be more performant. However, for the vast majority of use cases, `socat` will be perfectly adequate and the simplicity it provides is a worthwhile trade-off. Your plan to scale by adding more relay instances behind an NLB is the correct way to handle higher loads.
*   **`TCPMSS` Clamping:** Given that you are using the "Maximum Packet Length" filter, the `TCPMSS` clamping rule on the relay instance becomes less critical, as oversized packets are already prevented. It is still good practice to have as a defense-in-depth mechanism, but the primary solution is the filter.


**Key Refinements for Correctness:**
- **Traffic Mirroring Targets**: Confirmed via AWS docs—targets are limited to ENIs, NLBs, or GWLBs within AWS (same VPC, peered VPCs, or via Transit Gateway). Cannot directly target external IPs like GCP. Hence, use an AWS relay instance.
- **Forwarding Mechanism**: Use `socat` for UDP relay to preserve VXLAN without decapsulation. Verified feasible via networking examples; `socat` relays UDP datagrams effectively.
- **MTU Overhead**: Precise calculation: VXLAN (50 bytes) + IPsec ESP (typically 54–74 bytes for AES-256-GCM, including 20-byte outer IP, 8-byte ESP, 16-byte IV, 0–15 padding, 16-byte ICV). Total ~104–124 bytes. GCP HA VPN default MTU is 1460 bytes, so recommend 1400 for safety.
- **DF Bit**: AWS sets DF on outer VXLAN packets if the path requires it; inherited for inner. Emphasize PMTUD with ICMP enabled to handle drops.
- **Simplifications**: No NLB (adds cost/latency; use for HA if needed). No GRE (unnecessary overhead; VXLAN is sufficient).
- **Scalability/HA**: Single relay instance for basics; scale by adding instances or NLB.
- **Tool Compatibility**: GCP tools like Wireshark/Zeek handle VXLAN natively.

**Assumptions:**
- Existing HA IPsec VPN (4 tunnels) with BGP between AWS VPC (e.g., 10.0.0.0/16, ASN 64512) and GCP VPC (e.g., 172.16.0.0/16, ASN 65001).
- Administrative access to AWS and GCP.
- GCP instance for analysis with tools like Wireshark, Zeek, or Suricata.
- Source AWS instance(s) in a VPN-routable subnet.

**Architecture Overview:**
- AWS Source → Traffic Mirroring (VXLAN encapsulation) → AWS Relay Instance (ENI target) → `socat` UDP relay → IPsec VPN → GCP Analysis Instance (receives VXLAN packets).

## Step 1: Verify VPN Connectivity and Routing
Ensure bidirectional routing for VXLAN (UDP/4789).

### AWS:
1. In **VPC Console > Site-to-Site VPN Connections**, confirm all 4 tunnels **UP** and BGP **Established**.
2. In **Route Tables**, verify BGP-propagated routes for GCP subnet (e.g., 172.16.1.0/24 via Virtual Private Gateway).
3. Test: From an AWS instance, ping GCP instance private IP (e.g., 172.16.1.10).

### GCP:
1. In **VPC Network > VPN**, confirm tunnels **Established** and BGP active.
2. In **Routes**, verify AWS routes (e.g., 10.0.0.0/16 via Cloud Router).
3. Set VPN MTU: In **VPN > Edit**, set to 1460 (default; adjust to 1400 if issues).

## Step 2: Set Up GCP Analysis Instance
1. In **Compute Engine > VM Instances > Create Instance**:
   - Name: `traffic-mirror-target`.
   - Region/Zone: Match VPN (e.g., us-east1-b).
   - Machine type: `e2-standard-4` (scale as needed).
   - Boot disk: Ubuntu 22.04 LTS.
   - Network: VPC subnet (e.g., 172.16.1.0/24).
   - IP forwarding: Enabled.
   - Tags: `mirror-target`.
   - Private IP: Static (e.g., 172.16.1.10).

2. SSH and install tools:
   ```bash
   sudo apt update
   sudo apt install -y socat tcpdump wireshark tshark
   ```

3. Create firewall rules:
   - In **VPC Network > Firewall > Create Firewall Rule**:
     - Name: `allow-vxlan-from-aws`.
     - Direction: Ingress.
     - Source: AWS VPC CIDR (10.0.0.0/16).
     - Protocols/Ports: UDP 4789, ICMP (all types for PMTUD).
     - Targets: `mirror-target` tag.

4. Set MTU:
   ```bash
   sudo ip link set dev eth0 mtu 1400
   sudo iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360
   ```

## Step 3: Set Up AWS Relay Instance
1. Launch EC2 instance:
   - In **EC2 Console > Launch Instance**:
     - Name: `vxlan-relay`.
     - AMI: Ubuntu 22.04 LTS.
     - Instance type: t3.micro (scale for traffic).
     - VPC/Subnet: VPN-routable (e.g., 10.0.1.0/24).
     - Security Group: Inbound UDP/4789 from VPC CIDR (10.0.0.0/16), ICMP from VPC; outbound all (for VPN).
     - Enable IP forwarding: In advanced details, set `sysctl net.ipv4.ip_forward=1`.

2. SSH and install tools:
   ```bash
   sudo apt update
   sudo apt install -y socat
   ```

3. Set MTU:
   ```bash
   sudo ip link set dev eth0 mtu 1400
   sudo iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360
   sudo sysctl -w net.ipv4.ip_no_pmtu_disc=0  # Enable PMTUD
   ```

4. Configure UDP relay with `socat` (replace `<GCP_IP>` with 172.16.1.10):
   ```bash
   sudo socat UDP-LISTEN:4789,reuseaddr,fork UDP:<GCP_IP>:4789
   ```
   - Run as daemon (e.g., via systemd service for persistence):
     - Create `/etc/systemd/system/socat-vxlan.service`:
       ```
       [Unit]
       Description=VXLAN UDP Relay
       After=network.target

       [Service]
       ExecStart=/usr/bin/socat UDP-LISTEN:4789,reuseaddr,fork UDP:<GCP_IP>:4789
       Restart=always

       [Install]
       WantedBy=multi-user.target
       ```
     - Enable: `sudo systemctl daemon-reload; sudo systemctl enable --now socat-vxlan`.

5. Note the relay instance's ENI ID (in EC2 > Network Interfaces).

## Step 4: Configure AWS Traffic Mirroring
### 4.1 Create Traffic Mirror Filter
1. In **VPC Console > Traffic Mirroring > Filters > Create**:
   - Name: `mirror-filter`.
   - Rules: As needed (e.g., accept TCP port 80).
   - Maximum Packet Length: 1350 bytes (fits within 1400 MTU after overhead).

### 4.2 Create Traffic Mirror Target
1. In **Traffic Mirroring > Targets > Create**:
   - Name: `gcp-relay-target`.
   - Type: Network Interface.
   - Network Interface: Relay instance's ENI ID.

### 4.3 Create Traffic Mirror Session
1. Identify source ENI (from monitored EC2 instance).
2. In **Traffic Mirroring > Sessions > Create**:
   - Name: `gcp-mirror-session`.
   - Source: Source ENI.
   - Target: `gcp-relay-target`.
   - Filter: `mirror-filter`.
   - Session Number: 1.
   - VXLAN ID: 4789.
   - Packet Format: Entire packet.

## Step 5: Enable PMTUD for DF Bit Handling
- **AWS Security Group (Relay Instance)**: Allow outbound ICMP Type 3 Code 4 (Fragmentation Needed).
- **GCP Firewall**: Already allows ICMP ingress from AWS.
- Test PMTUD: From AWS relay, `ping -s 1372 -M do <GCP_IP>` (adjust size; success confirms no drops).

## Step 6: Test and Analyze
1. Generate traffic on AWS source (e.g., `curl http://example.com`).
2. On AWS relay, verify `socat` forwards (check logs or `netstat -u`).
3. On GCP:
   - Capture: `sudo tcpdump -i eth0 -n udp port 4789 -w /tmp/mirrored.pcap`
   - Analyze: Open in Wireshark (filter `vxlan`); or Zeek: `sudo zeek -i eth0 udp.port==4789`
   - Decapsulate if needed: 
     ```bash
     sudo ip link add vxlan0 type vxlan id 4789 dev eth0 dstport 4789
     sudo ip link set vxlan0 up
     sudo tcpdump -i vxlan0 -n
     ```

## Step 7: Monitor and Troubleshoot
- **AWS**: CloudWatch for Traffic Mirroring (`DroppedPackets`, `AcceptedPackets`).
- **GCP**: VPC Flow Logs for UDP/4789 ingress.
- **VPN**: Tunnel metrics for errors.
- **Issues**:
  - No packets: Check Security Groups (inbound UDP/4789), GCP Firewall, BGP routes, `socat` running.
  - Drops: Reduce max packet length; verify MTU with `tracepath <GCP_IP>`.
  - DF drops: Ensure ICMP PMTUD; fallback: Set `net.ipv4.ip_no_pmtu_disc=1` on source.
  - High load: Scale relay instance or add NLB.

## Best Practices
- **Security**: Restrict mirror filters to essential traffic.
- **HA**: Use NLB as target with multiple relay instances.
- **Cost**: Monitor data transfer over VPN (egress charges).
- **Alternatives**: If decapsulation needed, add VXLAN interface on AWS relay and forward inner packets via GRE (as in original proposal), but this increases complexity.


### **Architecture Overview**

We will configure a direct UDP relay to forward encapsulated VXLAN packets from AWS to GCP, avoiding the complexity of a GRE overlay.

*   **Flow:** AWS Source Instance → AWS Traffic Mirroring (VXLAN Wrap) → AWS Relay EC2 (ENI Target) → `socat` UDP Relay → IPsec VPN → GCP Analysis VM (Receives VXLAN)
*   **MTU Solution:** Proactively solved by setting a **Maximum Packet Length** in the AWS Traffic Mirror Filter, ensuring packets never exceed the VPN's MTU.



---

### **Phase 1: Preparation and Verification**

Before configuring, let's verify the foundation and define our variables.

#### **Step 1.1: Define Key Information**
Have these values ready to ensure a smooth copy-paste experience.

```sh
# --- Fill these in before you start ---

# AWS Values
AWS_VPC_CIDR="10.0.0.0/16"
AWS_RELAY_INSTANCE_IP="10.0.1.5"   # The private IP you will assign to the AWS relay
AWS_SOURCE_INSTANCE_IP="10.0.2.10" # An example source instance to test ping from

# GCP Values
GCP_VPC_CIDR="172.16.0.0/16"
GCP_ANALYSIS_INSTANCE_IP="172.16.1.10" # The static private IP for the GCP analysis VM
```

#### **Step 1.2: Verify VPN Connectivity and BGP Routing**
Ensure the underlay network is healthy.

1.  **On your local machine (with AWS and GCP CLI configured):**
    *   **Check AWS VPN:** `aws ec2 describe-vpn-connections --query "VpnConnections[*].State"` (Should be `available`)
    *   **Check AWS BGP:** `aws ec2 describe-vpn-connections --query "VpnConnections[*].VgwTelemetry[?Status=='UP']"` (Should show all 4 tunnels `UP`)
    *   **Check GCP VPN:** `gcloud compute vpn-tunnels list` (Should be `ESTABLISHED`)
    *   **Check GCP BGP:** `gcloud compute routers get-status <your-gcp-router-name> --region <your-region>` (Look for `BGP_ESTABLISHED`)

2.  **Perform a Ping Test:**
    *   From an existing instance in your AWS VPC, ping the private IP of an instance in your GCP VPC.
    *   `ping -c 4 <some-gcp-instance-ip>`
    *   If this fails, do not proceed. Troubleshoot your VPN, route tables, and firewalls first.

---

### **Phase 2: Configure the GCP Analysis Instance**

This VM will receive the mirrored traffic.

#### **Step 2.1: Launch the Compute Engine VM**
1.  Navigate to **Compute Engine > VM Instances > Create Instance**.
2.  **Name:** `gcp-analysis-vm`
3.  **Region/Zone:** A zone in the region connected to your VPN.
4.  **Machine type:** `e2-standard-4` or higher, depending on expected traffic volume.
5.  **Boot disk:** Ubuntu 22.04 LTS.
6.  **Advanced options > Networking:**
    *   **Network tags:** `vxlan-receiver`
    *   **Network interfaces:** Assign it a **Static internal IP** corresponding to `GCP_ANALYSIS_INSTANCE_IP` (e.g., `172.16.1.10`).
    *   **IP forwarding:** Set to **On**.
7.  Click **Create**.

#### **Step 2.2: Install Tools and Configure Network**
1.  SSH into `gcp-analysis-vm`.
2.  Install analysis tools:
    ```bash
    sudo apt-get update
    sudo apt-get install -y socat tcpdump tshark
    ```
3.  Set the MTU for the network interface to be safe.
    ```bash
    # Set the MTU to 1400. eth0 is the standard interface name.
    sudo ip link set dev eth0 mtu 1400
    ```
    *(Note: To make this persistent, you would configure it in `/etc/netplan/` on Ubuntu).*

#### **Step 2.3: Create GCP Firewall Rule**
1.  Navigate to **VPC Network > Firewall > Create Firewall Rule**.
2.  **Name:** `allow-vxlan-and-icmp-from-aws`
3.  **Direction of traffic:** Ingress
4.  **Targets:** Specified target tags > `vxlan-receiver`
5.  **Source filter:** IPv4 ranges > enter your `AWS_VPC_CIDR` (e.g., `10.0.0.0/16`).
6.  **Protocols and ports:**
    *   Select **Specified protocols and ports**.
    *   Check **UDP** and enter port `4789`.
    *   Check **Other protocols** and enter `icmp`. This is crucial for Path MTU Discovery.
7.  Click **Create**.

---

### **Phase 3: Configure the AWS Relay Instance**

This EC2 instance will catch the mirrored traffic and forward it.

#### **Step 3.1: Launch the EC2 Instance**
1.  Navigate to **EC2 > Launch Instance**.
2.  **Name:** `aws-vxlan-relay`
3.  **AMI:** Ubuntu 22.04 LTS.
4.  **Instance type:** `t3.medium` is a good start; scale as needed.
5.  **Key pair:** Select a key pair you can use to SSH.
6.  **Network settings:**
    *   **VPC/Subnet:** Select a private subnet that has a route to your VPN's Virtual Private Gateway (VGW).
    *   **Auto-assign Public IP:** Disable.
    *   **Private IP address:** Enter the `AWS_RELAY_INSTANCE_IP` (e.g., `10.0.1.5`).
    *   **Firewall (security groups):** Create a new security group. We'll configure it next.
7.  Click **Launch instance**.

#### **Step 3.2: Configure the Security Group**
1.  Find the security group for `aws-vxlan-relay`.
2.  Edit **Inbound rules:**
    *   **Rule 1:**
        *   **Type:** Custom UDP
        *   **Port Range:** `4789`
        *   **Source:** Your `AWS_VPC_CIDR` (e.g., `10.0.0.0/16`). This allows it to receive traffic from any instance being mirrored.
    *   **Rule 2 (for SSH):**
        *   **Type:** SSH
        *   **Source:** Your IP, or your Bastion Host's security group.
3.  Edit **Outbound rules:**
    *   Keep the default "Allow all traffic" rule, or restrict it to UDP/4789 and ICMP to your `GCP_VPC_CIDR` for tighter security. Ensure ICMP is allowed for PMTUD.

#### **Step 3.3: Install and Configure `socat` as a Service**
1.  SSH into `aws-vxlan-relay`.
2.  Install `socat`:
    ```bash
    sudo apt-get update
    sudo apt-get install -y socat
    ```
3.  Create a `systemd` service file to run `socat` persistently:
    ```bash
    # Use your defined GCP IP
    GCP_IP="172.16.1.10"

    sudo tee /etc/systemd/system/socat-vxlan-relay.service > /dev/null <<EOF
    [Unit]
    Description=VXLAN UDP Relay to GCP
    After=network.target
    StartLimitIntervalSec=0

    [Service]
    Type=simple
    Restart=always
    RestartSec=1
    User=root
    ExecStart=/usr/bin/socat -u UDP-LISTEN:4789,fork,reuseaddr UDP-SENDTO:${GCP_IP}:4789

    [Install]
    WantedBy=multi-user.target
    EOF
    ```4.  Enable and start the service:
    ```bash
    sudo systemctl daemon-reload
    sudo systemctl enable --now socat-vxlan-relay.service
    sudo systemctl status socat-vxlan-relay.service # Should show active (running)
    ```

#### **Step 3.4: Note the Relay Instance's ENI**
1.  In the EC2 console, select the `aws-vxlan-relay` instance.
2.  In the "Networking" tab, find and copy the **Network interface ID** (e.g., `eni-0123456789abcdef0`).

---

### **Phase 4: Configure AWS Traffic Mirroring**

Now we tie the source traffic to our relay.

#### **Step 4.1: Create Traffic Mirror Target**
1.  Navigate to **VPC > Traffic Mirroring > Mirror Targets**.
2.  Click **Create traffic mirror target**.
3.  **Name:** `gcp-bound-relay-target`
4.  **Target type:** Network Interface
5.  **Network Interface:** Paste the ENI of your `aws-vxlan-relay` instance.
6.  Click **Create**.

#### **Step 4.2: Create Traffic Mirror Filter**
1.  Go to **VPC > Traffic Mirroring > Mirror Filters**.
2.  Click **Create traffic mirror filter**.
3.  **Name:** `mirror-filter-for-gcp`
4.  **Inbound/Outbound Rules:** Add rules to capture the traffic you need (e.g., allow all traffic from `0.0.0.0/0`).
5.  Click **Create filter**.

#### **Step 4.3: Create Traffic Mirror Session**
1.  Go to **VPC > Traffic Mirroring > Mirror Sessions**.
2.  Click **Create traffic mirror session**.
3.  **Name:** `session-to-gcp-relay`
4.  **Mirror Source:** Select the ENI of the production instance you want to monitor.
5.  **Mirror Target:** Select `gcp-bound-relay-target`.
6.  **Mirror Filter:** Select `mirror-filter-for-gcp`.
7.  **Session number:** `1`
8.  **VXLAN Network Identifier (VNI):** `4789` (can be anything, but using the port number is intuitive).
9.  **Packet length:** This is the critical MTU-solving step. Set it to `1350`. This truncates mirrored packets to ensure the final VXLAN+IPsec packet fits within the 1460-byte VPN MTU.
10. Click **Create session**.

---

### **Phase 5: Test and Analyze**

1.  **Generate Traffic:** On your AWS source instance, generate some network traffic (e.g., `curl ifconfig.me`).
2.  **Verify on AWS Relay (Optional):** SSH to the relay and run `sudo tcpdump -i eth0 -n udp port 4789`. You should see VXLAN packets arriving from your source instance's IP.
3.  **Capture on GCP Analysis VM:**
    *   SSH to `gcp-analysis-vm`.
    *   Run `tcpdump` to confirm traffic is arriving from the AWS relay.
    ```bash
    # You should see packets from AWS_RELAY_INSTANCE_IP
    sudo tcpdump -i eth0 -n host <AWS_RELAY_INSTANCE_IP> and udp port 4789
    ```
4.  **Analyze the Mirrored Traffic:**
    *   You can now point your tools at the `eth0` interface and filter for VXLAN traffic.
    *   **Using TShark (Wireshark CLI):**
        ```bash
        # This will decode the VXLAN traffic and show you the inner packets
        sudo tshark -i eth0 -d udp.port==4789,vxlan
        ```
    *   **Using Zeek:**
        ```bash
        sudo zeek -i eth0
        # Zeek will automatically decode VXLAN and analyze the inner traffic.
        # Check the logs in /opt/zeek/logs/current/ (or similar path).
        ```