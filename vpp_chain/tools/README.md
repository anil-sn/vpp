# VPP Multi-Container Chain - Utility Tools

This directory contains utility scripts and tools for the VPP Multi-Container Chain deployment and management.

## Directory Structure

```
tools/
├── README.md                                    # This file
├── discovery/                                   # Environment discovery tools
│   └── environment_discovery.sh               # Production environment analysis
└── config-generator/                          # Configuration generation tools
    └── production_config_generator.py         # Production config generator
```

## Tool Overview

### Environment Discovery Tool

**Location**: `tools/discovery/environment_discovery.sh`

**Purpose**: Comprehensive environment analysis for production deployment planning

**Features**:
- System resource analysis (CPU, memory, disk)
- Network interface and routing discovery
- Cloud provider detection (AWS, GCP, Azure)
- Existing application conflict detection
- Traffic pattern analysis
- Integration point identification

**Usage**:
```bash
# Basic discovery
./tools/discovery/environment_discovery.sh

# Custom discovery directory
./tools/discovery/environment_discovery.sh -d /opt/vpp_discovery

# Verbose output
./tools/discovery/environment_discovery.sh -v

# Help
./tools/discovery/environment_discovery.sh -h
```

**Output**:
The tool creates a discovery directory containing:
- `discovery_report.txt` - Complete discovery summary
- `system_info.txt` - System resources and specifications
- `network_config.txt` - Network interfaces and routing
- `cloud_environment.txt` - Cloud provider detection results
- `application_discovery.txt` - Existing services analysis
- `traffic_analysis.txt` - Traffic pattern analysis
- `traffic_integration/` - Integration point analysis

### Production Configuration Generator

**Location**: `tools/config-generator/production_config_generator.py`

**Purpose**: Generate production-ready configuration files from environment discovery data

**Features**:
- Analyzes discovery reports for deployment parameters
- Generates production.json with optimized settings
- Calculates resource allocation based on system specs
- Determines safe network ranges avoiding conflicts
- Creates container configurations with proper limits
- Validates generated configuration

**Usage**:
```bash
# Generate config from discovery data
./tools/config-generator/production_config_generator.py /tmp/vpp_discovery_20231201_143022

# Custom output file
./tools/config-generator/production_config_generator.py /path/to/discovery -o custom_production.json

# Validate generated config
./tools/config-generator/production_config_generator.py /path/to/discovery --validate

# Help
./tools/config-generator/production_config_generator.py -h
```

**Output**:
- `production_generated.json` - Production configuration file
- Console output with generation summary
- Validation results if requested

## Complete Workflow

### 1. Environment Discovery
```bash
# Run comprehensive environment discovery
./tools/discovery/environment_discovery.sh -v

# Note the discovery directory path from output
DISCOVERY_DIR=$(ls -1dt /tmp/vpp_discovery_* | head -1)
echo "Discovery completed in: $DISCOVERY_DIR"
```

### 2. Configuration Generation
```bash
# Generate production configuration
./tools/config-generator/production_config_generator.py "$DISCOVERY_DIR" --validate

# Review generated configuration
cat production_generated.json
```

### 3. Deployment
```bash
# Deploy using generated configuration
sudo python3 src/main.py cleanup
sudo python3 src/main.py setup --config production_generated.json --force

# Validate deployment
sudo python3 src/main.py test
```

## Prerequisites

### System Requirements
- **Linux Environment**: Ubuntu 20.04+ or equivalent
- **Python 3.8+**: For configuration generation
- **Bash 4.0+**: For discovery scripts
- **Network Tools**: ss, ip, curl for network analysis
- **Root Access**: Required for comprehensive system analysis

### Optional Tools for Enhanced Discovery
- **iftop**: Detailed traffic analysis
- **nethogs**: Process-based network monitoring
- **tshark**: Packet analysis capabilities
- **tcpdump**: Traffic capture functionality

Install optional tools:
```bash
sudo apt update
sudo apt install -y iftop nethogs tshark tcpdump
```

### Python Dependencies
```bash
pip3 install ipaddress pathlib argparse
```

## Advanced Usage

### Custom Discovery Parameters
```bash
# Discovery with custom parameters
DISCOVERY_DIR="/opt/custom_discovery" VERBOSE=true ./tools/discovery/environment_discovery.sh
```

### Configuration Generation Options
```bash
# Generate with specific deployment type
./tools/config-generator/production_config_generator.py $DISCOVERY_DIR --deployment-type staging

# Custom resource allocation
# Edit the generated config to adjust:
# - Container memory limits
# - CPU allocations  
# - Network address ranges
# - Performance parameters
```

### Integration with CI/CD

The tools can be integrated into automated deployment pipelines:

```bash
#!/bin/bash
# CI/CD Integration Example

# 1. Environment Discovery
./tools/discovery/environment_discovery.sh -d /opt/ci_discovery

# 2. Configuration Generation
./tools/config-generator/production_config_generator.py /opt/ci_discovery -o ci_production.json --validate

# 3. Automated Deployment
sudo python3 src/main.py setup --config ci_production.json --force

# 4. Validation
sudo python3 src/main.py test
```

## Troubleshooting

### Common Issues

**Discovery Permission Errors**:
```bash
# Run with appropriate permissions
sudo ./tools/discovery/environment_discovery.sh
```

**Configuration Generation Fails**:
```bash
# Check discovery directory exists and has required files
ls -la /tmp/vpp_discovery_*/
```

**Network Analysis Missing**:
```bash
# Install required network tools
sudo apt install -y iproute2 net-tools
```

### Debug Mode
```bash
# Enable detailed logging
set -x
./tools/discovery/environment_discovery.sh -v
set +x
```

## Contributing

When adding new tools:
1. Create appropriate subdirectory under `tools/`
2. Follow existing naming conventions
3. Include comprehensive help documentation
4. Add executable permissions
5. Update this README with tool information

## Support

For issues with utility tools:
1. Check tool-specific help: `tool_name -h`
2. Review discovery reports for analysis issues
3. Validate generated configurations before deployment
4. Refer to main project documentation in `docs/`