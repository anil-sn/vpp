#!/bin/bash
# Comprehensive VPP Chain Validation Script
# This script tells the complete story of our VPP chain like reading a novel

set -e
sudo python3 src/main.py setup
sudo python3 src/main.py test
echo ""

