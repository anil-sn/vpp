# =========================================================================
# Root CMakeLists.txt for the Kea Control (keactrl) Project
#
# This file defines the project, finds all system-level dependencies, and
# delegates the build process to subdirectories.
# =========================================================================

cmake_minimum_required(VERSION 3.10)
project(keactrl C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# --- Define Output Directories ---
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# --- Find All Global Dependencies ---
# Find libcurl once at the top level. This makes the imported target
# CURL::libcurl globally visible to all subdirectories that need it.
find_package(CURL REQUIRED)

# --- Add Subdirectories to Build ---
# CMake will process the CMakeLists.txt in each of these directories.
add_subdirectory(vendor/cjson)
add_subdirectory(src)
add_subdirectory(tests)

# Enable CTest support for the 'ctest' command.
enable_testing()

message(STATUS "Project root configured. Delegating build to subdirectories.")