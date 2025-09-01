#!/bin/bash
#
# Main test runner script for the Kea Control (keactrl) project.
#
# This script ensures a completely clean, hermetic test environment by:
# 1. Forcefully cleaning up stale state from previous runs.
# 2. Rebuilding the Docker lab image from scratch.
# 3. Running the container, which executes a clean build and the full C-based
#    integration test suite.
#
# A zero exit code indicates that all tests passed.

set -e

# Delegate all logic to the robust run-lab.sh script.
# This ensures that a single, authoritative script manages the entire lab
# lifecycle, and this script serves as the simple entry point for CI/CD.
bash ./run-lab.sh test_all