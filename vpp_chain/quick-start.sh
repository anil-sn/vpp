#!/bin/bash
# Quick Start Script - VPP Multi-Container Chain
# Performs full setup and testing of the VPP chain

set -e
echo "🚀 Starting VPP Multi-Container Chain setup and test..."
sudo python3 src/main.py setup
sudo python3 src/main.py test
echo "✅ VPP Chain setup and testing complete!"