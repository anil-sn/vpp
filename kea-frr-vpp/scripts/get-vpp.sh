#!/bin/bash
#
# This script, adapted from the FD.io CSIT project, downloads a consistent
# set of VPP .deb packages from the official Packagecloud repository.
#
# It is designed to be run inside a Docker build to fetch all necessary
# packages for a local, atomic installation with 'apt-get install ./*.deb'.
# This avoids complex dependency resolution issues with remote repositories.
#
# Environment variables used:
# - REPO: The VPP repository to use (e.g., 'release'). Defaults to 'release'.
# - VPP_VERSION: The specific version of VPP to download (e.g., '24.02').
#                If not set, it will automatically find the latest version.

set -euo pipefail

# --- Helper Functions ---
die () {
    echo "ERROR: ${1:-Unspecified run-time error occurred!}" >&2
    exit "${2:-1}"
}

# --- Main Logic ---

# 1. Set repository URL
REPO="${REPO:-release}"
REPO_URL="https://packagecloud.io/install/repositories/fdio/${REPO}"

echo "--- Using VPP Repository: ${REPO_URL} ---"

# 2. Add the FD.io repository to APT sources
curl -sS "${REPO_URL}/script.deb.sh" | bash || die "Packagecloud FD.io repo fetch failed."

# 3. Find the local APT source file path created by the script
#    This is a robust way to find the file without hardcoding its name.
both_quotes='"'"'"
match="[^${both_quotes}]*"
qmatch="[${both_quotes}]\?"
sed_command="s#.*apt_source_path=${qmatch}\(${match}\)${qmatch}#\1#p"
apt_fdio_repo_file=$(curl -s "${REPO_URL}/script.deb.sh" | sed -n "${sed_command}") || die "Local fdio repo file path fetch failed."

if [ ! -f "${apt_fdio_repo_file}" ]; then
    die "${apt_fdio_repo_file} not found; repository installation was not successful."
fi

echo "--- FD.io APT source file found at: ${apt_fdio_repo_file} ---"

# 4. Get a list of all VPP-related packages available in the new repository
packages=$(apt-cache -o Dir::Etc::SourceList="${apt_fdio_repo_file}" \
           -o Dir::Etc::SourceParts="/" dumpavail \
           | grep Package: | cut -d " " -f 2) || die "Retrieval of available VPP packages failed."

# 5. Determine the target VPP version if not explicitly set
if [ -z "${VPP_VERSION-}" ]; then
    echo "--- VPP_VERSION not set, detecting latest version... ---"
    allVersions=$(apt-cache -o Dir::Etc::SourceList="${apt_fdio_repo_file}" \
                  -o Dir::Etc::SourceParts="/" \
                  show vpp | grep Version: | cut -d " " -f 2) || die "Retrieval of available VPP versions failed."
    VPP_VERSION=$(echo "$allVersions" | head -n1) || true
fi

echo "--- Target VPP Version: ${VPP_VERSION} ---"

# 6. Build the list of artifacts (package=version) to download
artifacts=()
echo "--- Finding packages matching version ${VPP_VERSION} ---"
for package in ${packages}; do
    # Filter packages that match the target version string
    pkg_info=$(apt-cache show -- "${package}") || die "apt-cache show on ${package} failed."
    ver=$(echo "${pkg_info}" | grep -o "Version: ${VPP_VERSION}[^ ]*" | head -1) || true

    if [ -n "${ver-}" ]; then
        ver_string=$(echo "$ver" | cut -d " " -f 2)
        artifacts+=("${package}=${ver_string}")
        echo "  [+] Found: ${package}=${ver_string}"
    fi
done

if [ ${#artifacts[@]} -eq 0 ]; then
    die "No artifacts found for version ${VPP_VERSION}. Please check the version string and repository."
fi

# 7. Download all the found artifacts as .deb files to the current directory
echo "--- Downloading ${#artifacts[@]} VPP packages... ---"
apt-get -y download "${artifacts[@]}" || die "Download of VPP artifacts failed."

echo "--- VPP package download successful. ---"