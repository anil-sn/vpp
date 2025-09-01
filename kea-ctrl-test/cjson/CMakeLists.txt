#
# CMakeLists.txt for the vendored cJSON library
#

add_library(cJSON
    cJSON.c
)

# Set the public include directory for cJSON
# PUBLIC means that any target linking against cJSON will automatically
# get this include directory. This is the key to solving the build error.
target_include_directories(cJSON
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
)

# This alias is a modern CMake convention.
add_library(cJSON::cJSON ALIAS cJSON)