# VPP Chain Automation Templates

This document provides Infrastructure as Code (IaC) templates and automation scripts for deploying the VPP multi-container chain in production environments.

## Terraform Templates

### AWS Infrastructure

#### main.tf (AWS)

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "c5.2xlarge"
}

variable "key_name" {
  description = "EC2 Key Pair name"
  type        = string
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to access the VPP chain"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC
resource "aws_vpc" "vpp_chain_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "vpp-chain-vpc-${var.environment}"
    Environment = var.environment
  }
}

# Internet Gateway
resource "aws_internet_gateway" "vpp_chain_igw" {
  vpc_id = aws_vpc.vpp_chain_vpc.id

  tags = {
    Name        = "vpp-chain-igw-${var.environment}"
    Environment = var.environment
  }
}

# Subnets
resource "aws_subnet" "vpp_chain_public_subnet" {
  count = 2

  vpc_id                  = aws_vpc.vpp_chain_vpc.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "vpp-chain-public-subnet-${count.index + 1}-${var.environment}"
    Environment = var.environment
    Type        = "public"
  }
}

# Route Table
resource "aws_route_table" "vpp_chain_public_rt" {
  vpc_id = aws_vpc.vpp_chain_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vpp_chain_igw.id
  }

  tags = {
    Name        = "vpp-chain-public-rt-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "vpp_chain_public_rta" {
  count = 2

  subnet_id      = aws_subnet.vpp_chain_public_subnet[count.index].id
  route_table_id = aws_route_table.vpp_chain_public_rt.id
}

# Security Groups
resource "aws_security_group" "vpp_chain_sg" {
  name_prefix = "vpp-chain-sg-${var.environment}"
  vpc_id      = aws_vpc.vpp_chain_vpc.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # VXLAN traffic
  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # IPsec ESP
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "50"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # IPsec NAT-T
  ingress {
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Test traffic port
  ingress {
    from_port   = 2055
    to_port     = 2055
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # HTTP/HTTPS for monitoring
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "vpp-chain-sg-${var.environment}"
    Environment = var.environment
  }
}

# IAM Role for EC2
resource "aws_iam_role" "vpp_chain_role" {
  name = "vpp-chain-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "vpp_chain_policy" {
  name = "vpp-chain-policy-${var.environment}"
  role = aws_iam_role.vpp_chain_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "vpp_chain_profile" {
  name = "vpp-chain-profile-${var.environment}"
  role = aws_iam_role.vpp_chain_role.name
}

# User Data Template
locals {
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    environment = var.environment
    region      = var.aws_region
  }))
}

# Launch Template
resource "aws_launch_template" "vpp_chain_lt" {
  name_prefix   = "vpp-chain-lt-${var.environment}"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.vpp_chain_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.vpp_chain_profile.name
  }

  user_data = local.user_data

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "vpp-chain-instance-${var.environment}"
      Environment = var.environment
      Project     = "vpp-chain"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name        = "vpp-chain-volume-${var.environment}"
      Environment = var.environment
      Project     = "vpp-chain"
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "vpp_chain_asg" {
  name                = "vpp-chain-asg-${var.environment}"
  vpc_zone_identifier = aws_subnet.vpp_chain_public_subnet[*].id
  target_group_arns   = [aws_lb_target_group.vpp_chain_tg.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = 1
  max_size         = 3
  desired_capacity = 2

  launch_template {
    id      = aws_launch_template.vpp_chain_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "vpp-chain-asg-${var.environment}"
    propagate_at_launch = false
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}

# Application Load Balancer
resource "aws_lb" "vpp_chain_alb" {
  name               = "vpp-chain-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.vpp_chain_sg.id]
  subnets            = aws_subnet.vpp_chain_public_subnet[*].id

  enable_deletion_protection = false

  tags = {
    Name        = "vpp-chain-alb-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "vpp_chain_tg" {
  name     = "vpp-chain-tg-${var.environment}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpp_chain_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "vpp-chain-tg-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_lb_listener" "vpp_chain_listener" {
  load_balancer_arn = aws_lb.vpp_chain_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vpp_chain_tg.arn
  }
}

# Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.vpp_chain_vpc.id
}

output "subnet_ids" {
  description = "IDs of the subnets"
  value       = aws_subnet.vpp_chain_public_subnet[*].id
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.vpp_chain_sg.id
}

output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = aws_lb.vpp_chain_alb.dns_name
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling group"
  value       = aws_autoscaling_group.vpp_chain_asg.name
}
```

#### user-data.sh (AWS)

```bash
#!/bin/bash
set -e

# Logging
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting VPP Chain deployment at $(date)"

# Variables from Terraform
ENVIRONMENT="${environment}"
REGION="${region}"

# Update system
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install prerequisites
apt-get install -y \
    docker.io \
    docker-compose \
    python3-pip \
    python3-scapy \
    git \
    htop \
    iotop \
    nethogs \
    tcpdump \
    curl \
    wget \
    unzip \
    jq

# Configure Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install CloudWatch Agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
rm amazon-cloudwatch-agent.deb

# Python packages
pip3 install docker-compose scapy boto3

# System optimization for VPP
echo 'net.core.rmem_default = 262144' >> /etc/sysctl.conf
echo 'net.core.rmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.core.wmem_default = 262144' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.core.netdev_max_backlog = 30000' >> /etc/sysctl.conf
echo 'net.core.netdev_budget = 600' >> /etc/sysctl.conf
sysctl -p

# Clone VPP chain repository
cd /opt
git clone https://github.com/your-org/vpp-chain.git vpp-chain
cd vpp-chain
chown -R ubuntu:ubuntu /opt/vpp-chain

# Configure for AWS
sed -i 's/"default_mode": "gcp"/"default_mode": "aws"/' config.json

# Setup logging directory
mkdir -p /var/log/vpp-chain
chown ubuntu:ubuntu /var/log/vpp-chain

# Create CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "metrics": {
    "namespace": "VPP/Chain",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_iowait",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "metrics_collection_interval": 60,
        "totalcpu": false
      },
      "disk": {
        "measurement": [
          "used_percent"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ],
        "metrics_collection_interval": 60
      },
      "netstat": {
        "measurement": [
          "tcp_established",
          "tcp_time_wait"
        ],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/vpp-chain/*.log",
            "log_group_name": "/aws/ec2/vpp-chain",
            "log_stream_name": "{instance_id}-vpp-chain"
          },
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "/aws/ec2/vpp-chain",
            "log_stream_name": "{instance_id}-user-data"
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

# Create health check endpoint
cat > /opt/vpp-chain/health_server.py << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import subprocess
import docker

class HealthHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            try:
                # Check Docker containers
                client = docker.from_env()
                containers = ['chain-ingress', 'chain-vxlan', 'chain-nat', 'chain-ipsec', 'chain-fragment', 'chain-gcp']
                
                health_status = {}
                all_healthy = True
                
                for container_name in containers:
                    try:
                        container = client.containers.get(container_name)
                        is_healthy = container.status == 'running'
                        health_status[container_name] = is_healthy
                        if not is_healthy:
                            all_healthy = False
                    except:
                        health_status[container_name] = False
                        all_healthy = False
                
                response = {
                    'status': 'healthy' if all_healthy else 'unhealthy',
                    'containers': health_status,
                    'timestamp': int(time.time())
                }
                
                self.send_response(200 if all_healthy else 503)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(response).encode())
                
            except Exception as e:
                self.send_response(503)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'status': 'error', 'message': str(e)}).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == "__main__":
    PORT = 80
    with socketserver.TCPServer(("", PORT), HealthHandler) as httpd:
        httpd.serve_forever()
EOF

chmod +x /opt/vpp-chain/health_server.py

# Create systemd services
cat > /etc/systemd/system/vpp-chain.service << 'EOF'
[Unit]
Description=VPP Multi-Container Chain
After=docker.service
Requires=docker.service

[Service]
Type=forking
User=ubuntu
WorkingDirectory=/opt/vpp-chain
ExecStart=/usr/bin/python3 src/main.py setup
ExecStop=/usr/bin/python3 src/main.py cleanup
Restart=on-failure
RestartSec=30
TimeoutStartSec=600
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/vpp-health.service << 'EOF'
[Unit]
Description=VPP Chain Health Check Server
After=vpp-chain.service
Requires=vpp-chain.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/vpp-chain
ExecStart=/usr/bin/python3 health_server.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
systemctl daemon-reload
systemctl enable vpp-chain.service
systemctl enable vpp-health.service

# Wait for Docker to be ready
sleep 10

# Start VPP chain
systemctl start vpp-chain.service

# Wait for VPP chain to be ready
sleep 30

# Start health check server
systemctl start vpp-health.service

# Create monitoring script
cat > /opt/vpp-chain/monitor.sh << 'EOF'
#!/bin/bash

# Monitor VPP chain and send metrics to CloudWatch
while true; do
    # Get container stats
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemPerc}}" > /tmp/docker_stats.txt
    
    # Send to CloudWatch (implement as needed)
    # aws cloudwatch put-metric-data --namespace VPP/Chain --metric-data ...
    
    sleep 60
done
EOF

chmod +x /opt/vpp-chain/monitor.sh

# Start monitoring in background
nohup /opt/vpp-chain/monitor.sh > /var/log/vpp-chain/monitor.log 2>&1 &

echo "VPP Chain deployment completed at $(date)"
```

### GCP Infrastructure

#### main.tf (GCP)

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Variables
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "machine_type" {
  description = "GCE machine type"
  type        = string
  default     = "c2-standard-4"
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to access the VPP chain"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# VPC Network
resource "google_compute_network" "vpp_chain_network" {
  name                    = "vpp-chain-network-${var.environment}"
  auto_create_subnetworks = false
}

# Subnet
resource "google_compute_subnetwork" "vpp_chain_subnet" {
  name          = "vpp-chain-subnet-${var.environment}"
  network       = google_compute_network.vpp_chain_network.id
  ip_cidr_range = "10.0.0.0/16"
  region        = var.region

  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "10.1.0.0/16"
  }
}

# Firewall Rules
resource "google_compute_firewall" "vpp_chain_allow_ssh" {
  name    = "vpp-chain-allow-ssh-${var.environment}"
  network = google_compute_network.vpp_chain_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_cidrs
  target_tags   = ["vpp-chain"]
}

resource "google_compute_firewall" "vpp_chain_allow_vxlan" {
  name    = "vpp-chain-allow-vxlan-${var.environment}"
  network = google_compute_network.vpp_chain_network.name

  allow {
    protocol = "udp"
    ports    = ["4789"]
  }

  source_ranges = ["10.0.0.0/16"]
  target_tags   = ["vpp-chain"]
}

resource "google_compute_firewall" "vpp_chain_allow_ipsec" {
  name    = "vpp-chain-allow-ipsec-${var.environment}"
  network = google_compute_network.vpp_chain_network.name

  allow {
    protocol = "esp"
  }

  allow {
    protocol = "udp"
    ports    = ["500", "4500"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["vpp-chain"]
}

resource "google_compute_firewall" "vpp_chain_allow_internal" {
  name    = "vpp-chain-allow-internal-${var.environment}"
  network = google_compute_network.vpp_chain_network.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "2055"]
  }

  allow {
    protocol = "udp"
    ports    = ["2055"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/16"]
  target_tags   = ["vpp-chain"]
}

resource "google_compute_firewall" "vpp_chain_allow_health" {
  name    = "vpp-chain-allow-health-${var.environment}"
  network = google_compute_network.vpp_chain_network.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"] # Google LB health check ranges
  target_tags   = ["vpp-chain"]
}

# Service Account
resource "google_service_account" "vpp_chain_sa" {
  account_id   = "vpp-chain-sa-${var.environment}"
  display_name = "VPP Chain Service Account"
}

resource "google_project_iam_member" "vpp_chain_compute_admin" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.vpp_chain_sa.email}"
}

resource "google_project_iam_member" "vpp_chain_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vpp_chain_sa.email}"
}

resource "google_project_iam_member" "vpp_chain_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vpp_chain_sa.email}"
}

# Instance Template
resource "google_compute_instance_template" "vpp_chain_template" {
  name_prefix  = "vpp-chain-template-${var.environment}-"
  machine_type = var.machine_type

  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
    disk_size_gb = 50
    disk_type    = "pd-ssd"
  }

  network_interface {
    network    = google_compute_network.vpp_chain_network.id
    subnetwork = google_compute_subnetwork.vpp_chain_subnet.id
    
    access_config {
      # Ephemeral external IP
    }
  }

  service_account {
    email  = google_service_account.vpp_chain_sa.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = templatefile("${path.module}/startup-script.sh", {
    environment = var.environment
    project_id  = var.project_id
    region      = var.region
  })

  tags = ["vpp-chain", var.environment]

  lifecycle {
    create_before_destroy = true
  }
}

# Managed Instance Group
resource "google_compute_instance_group_manager" "vpp_chain_igm" {
  name               = "vpp-chain-igm-${var.environment}"
  base_instance_name = "vpp-chain"
  zone               = var.zone
  target_size        = 2

  version {
    instance_template = google_compute_instance_template.vpp_chain_template.id
  }

  named_port {
    name = "http"
    port = 80
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.vpp_chain_health.id
    initial_delay_sec = 300
  }
}

# Health Check
resource "google_compute_health_check" "vpp_chain_health" {
  name               = "vpp-chain-health-${var.environment}"
  check_interval_sec = 30
  timeout_sec        = 10
  healthy_threshold  = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 80
    request_path = "/health"
  }
}

# Load Balancer
resource "google_compute_backend_service" "vpp_chain_backend" {
  name                    = "vpp-chain-backend-${var.environment}"
  load_balancing_scheme   = "EXTERNAL"
  health_checks          = [google_compute_health_check.vpp_chain_health.id]

  backend {
    group           = google_compute_instance_group_manager.vpp_chain_igm.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_url_map" "vpp_chain_url_map" {
  name            = "vpp-chain-url-map-${var.environment}"
  default_service = google_compute_backend_service.vpp_chain_backend.id
}

resource "google_compute_target_http_proxy" "vpp_chain_proxy" {
  name    = "vpp-chain-proxy-${var.environment}"
  url_map = google_compute_url_map.vpp_chain_url_map.id
}

resource "google_compute_global_address" "vpp_chain_ip" {
  name = "vpp-chain-ip-${var.environment}"
}

resource "google_compute_global_forwarding_rule" "vpp_chain_forwarding" {
  name       = "vpp-chain-forwarding-${var.environment}"
  target     = google_compute_target_http_proxy.vpp_chain_proxy.id
  port_range = "80"
  ip_address = google_compute_global_address.vpp_chain_ip.address
}

# Autoscaler
resource "google_compute_autoscaler" "vpp_chain_autoscaler" {
  name   = "vpp-chain-autoscaler-${var.environment}"
  zone   = var.zone
  target = google_compute_instance_group_manager.vpp_chain_igm.id

  autoscaling_policy {
    max_replicas    = 5
    min_replicas    = 2
    cooldown_period = 60

    cpu_utilization {
      target = 0.8
    }
  }
}

# Outputs
output "network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.vpp_chain_network.id
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = google_compute_subnetwork.vpp_chain_subnet.id
}

output "service_account_email" {
  description = "Email of the service account"
  value       = google_service_account.vpp_chain_sa.email
}

output "load_balancer_ip" {
  description = "IP address of the load balancer"
  value       = google_compute_global_address.vpp_chain_ip.address
}

output "instance_group_manager" {
  description = "Name of the instance group manager"
  value       = google_compute_instance_group_manager.vpp_chain_igm.name
}
```

This automation template provides comprehensive Infrastructure as Code for deploying the VPP multi-container chain with proper load balancing, auto-scaling, monitoring, and health checks in both AWS and GCP environments.