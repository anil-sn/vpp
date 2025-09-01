#!/bin/bash
#
# This is the robust build script for the keactrl project.
# It performs a clean, out-of-source build every time.
#
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
BUILD_DIR="build"
SOURCE_DIR=$(pwd) # Assumes the script is run from the project root

# --- Clean and Recreate Build Directory ---
echo "--> Removing old build directory..."
rm -rf "${SOURCE_DIR}/${BUILD_DIR}"

echo "--> Creating new build directory..."
mkdir -p "${SOURCE_DIR}/${BUILD_DIR}"

# --- Run CMake and Build ---
echo "--> Configuring project with CMake..."
# Change into the build directory to run cmake
cd "${SOURCE_DIR}/${BUILD_DIR}"

# Run cmake, pointing it to the source directory containing the main CMakeLists.txt
cmake ..

echo "--> Compiling project with make..."
# Run make from inside the build directory
make

echo
echo "✅ Build successful!"
echo "   Library is at: ${BUILD_DIR}/lib/libkeactrl.so"
echo "   CLI tool is at:  ${BUILD_DIR}/bin/keactrl"
echo "   Test runner is at: ${BUILD_DIR}/bin/test_runner"
echo
echo "   To run tests, execute: 'cd ${BUILD_DIR} && ctest'"