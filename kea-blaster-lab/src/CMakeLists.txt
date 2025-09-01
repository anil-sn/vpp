# =========================================================================
# CMakeLists.txt for the 'src' Directory (Definitive Fix)
# =========================================================================

# --- 1. Define the Library Target ---
# The target is named keactrl_lib. CMake will automatically create
# the correctly named shared library file (libkeactrl_lib.so or keactrl_lib.dll)
add_library(keactrl_lib SHARED
    core/keactrl_core.c
    utils/kea_config_builder.c
    api/generic_cmds.c
    api/config_cmds.c
    api/lease_cmds.c
    api/subnet_cmds.c
    api/stat_cmds.c
    api/host_cmds.c
    api/class_cmds.c
    api/cache_cmds.c
)
# We can rename the output file if desired, but let's stick to the target name
# for clarity and to avoid the collision.
set_target_properties(keactrl_lib PROPERTIES OUTPUT_NAME "keactrl")


# --- 2. Configure Library Dependencies ---
# The public API of our library uses cJSON types, so its include directory
# must be PUBLIC. The linking of the static cJSON library is an internal
# detail, so it is PRIVATE. libcurl is a shared dependency, so it is PUBLIC.
target_include_directories(keactrl_lib
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        $<TARGET_PROPERTY:cJSON,INTERFACE_INCLUDE_DIRECTORIES>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/internal
        ${CMAKE_CURRENT_SOURCE_DIR}/core
)

target_link_libraries(keactrl_lib
    PRIVATE
        cJSON::cJSON
    PUBLIC
        CURL::libcurl
)


# --- 3. Define the CLI Executable Target ---
# FIX: The target is now simply named 'keactrl'. We do not need to rename it.
add_executable(keactrl
    cli/keactrl.c
    cli/output.c
)

# Enforce that the library is built before the executable.
add_dependencies(keactrl keactrl_lib)

target_include_directories(keactrl
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/cli
)

# Link the executable against the library. CMake will correctly propagate the
# public dependencies (cURL) and public include directories (cJSON).
target_link_libraries(keactrl
    PRIVATE
        keactrl_lib
)