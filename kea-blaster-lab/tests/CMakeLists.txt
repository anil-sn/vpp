# =========================================================================
# CMakeLists.txt for the 'tests' Directory (Definitive Fix)
# =========================================================================

# --- 1. Define the Test Runner Executable ---
add_executable(test_runner
    runner.c
    helpers/bngblaster_api.c
    helpers/config_helper.c
    cases/test_generic_cmds.c
    cases/test_config_cmds.c
    cases/test_lease_cmds.c
    cases/test_subnet_cmds.c
    cases/test_stat_cmds.c
)

# --- 2. Configure Include Directories for the Test Runner ---
target_include_directories(test_runner
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/src/include
)

# --- 3. Link Libraries for the Test Runner ---
target_link_libraries(test_runner
    PRIVATE
        keactrl_lib
        cJSON::cJSON
        CURL::libcurl	
)