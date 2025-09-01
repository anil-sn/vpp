#
# CMakeLists.txt for libkeactrl and the keactl utility
#

# --- Project Definition and Required Version ---
cmake_minimum_required(VERSION 3.10)
project(keactrl C)

# --- Standard Settings ---
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# --- Find Dependencies ---
add_subdirectory(cjson)
find_package(CURL REQUIRED)

# --- Setup Build Directories ---
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# --- Library Target (libkeactrl) ---
add_library(keactrl SHARED
    lib/libkeactrl_core.c
    lib/libkeactrl_generic.c
    lib/libkeactrl_config.c
    lib/libkeactrl_lease4.c
    lib/libkeactrl_lease6.c
    lib/libkeactrl_stats_ha.c
)

# Define include directories and link libraries FOR THE LIBRARY
target_include_directories(keactrl
    PUBLIC
        ${PROJECT_SOURCE_DIR}/lib
)

target_link_libraries(keactrl
    PUBLIC
        cJSON::cJSON
    PRIVATE
        CURL::libcurl
)

# --- CLI Tool Target (keactl) ---
add_executable(keactl
    cli/keactl.c
    cli/output.c
)

# Link the CLI tool (keactl) to our library (keactrl)
target_link_libraries(keactl    # <-- CORRECTED TARGET NAME
    PUBLIC
        keactrl
)

# --- Test Runner Target ---
enable_testing()

add_executable(test_runner
    tests/runner.c
    tests/test_generic_cmds.c
    tests/test_config_cmds.c
    tests/test_lease_cmds.c
    tests/test_stats_ha_cmds.c
)

# Link the test runner to our library
target_link_libraries(test_runner
    PUBLIC
        keactrl
)

add_test(NAME run-tests COMMAND test_runner)

# --- Installation ---
install(TARGETS keactrl keactl
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
install(FILES lib/libkeactrl.h DESTINATION include)

# --- Final Output ---
message(STATUS "Build system configured for libkeactrl and keactl.")
message(STATUS "Run 'cmake --build .' to build all targets.")
message(STATUS "Run 'ctest' or 'make test' to run integration tests.")