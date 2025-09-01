#!/bin/bash
#
# Convenience build script for the Kea Control (keactrl) project.
#
# This script automates the standard out-of-source build process, ensuring
# a clean and repeatable compilation environment.
#
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
BUILD_DIR="build"
SOURCE_DIR=$(pwd) # Assumes the script is run from the project root

# --- Clean and Recreate Build Directory ---
echo "--> Cleaning up old build directory..."
rm -rf "${SOURCE_DIR}/${BUILD_DIR}"

echo "--> Creating new build directory: ${BUILD_DIR}/"
mkdir -p "${SOURCE_DIR}/${BUILD_DIR}"

# --- Run CMake and Build ---
echo "--> Configuring project with CMake..."
cd "${SOURCE_DIR}/${BUILD_DIR}"
cmake -DCMAKE_BUILD_TYPE=Debug ..

echo "--> Compiling all targets with make..."
make -j$(nproc)

# --- Final Output ---
echo
echo "✅ Build successful!"
echo "   Library is at: ./${BUILD_DIR}/lib/libkeactrl.so"
echo "   CLI tool is at:  ./${BUILD_DIR}/bin/keactrl"
echo "   Test runner is at: ./${BUILD_DIR}/bin/test_runner"
