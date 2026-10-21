#!/bin/bash
# Build Natron on Windows with MSYS2 (MINGW64 shell), optionally instrumented for Tracy.
# The steps mirror the Windows job of .github/workflows/ci.yml.
#
# Usage (from the MSYS2 MINGW64 shell, at the root of the Natron checkout):
#   tools/profiling/build-msys2.sh [--tracy] [--build-dir DIR]
#
# Then run Natron with tools/profiling/run-msys2.sh.

set -euo pipefail

NATRON_DIR=$(cd "$(dirname "$0")/../.." && pwd)
BUILD_DIR="${NATRON_DIR}/build-profiling"
TRACY=OFF
OCIO_CONFIG_VERSION=2.5

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tracy) TRACY=ON; shift ;;
        --build-dir) BUILD_DIR=$(realpath -m "$2"); shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ "${MSYSTEM:-}" != "MINGW64" ]]; then
    echo "Run this script from the MSYS2 MINGW64 shell (MSYSTEM=MINGW64)."
    exit 1
fi

# Retry a command a few times: MSYS2 and GitHub mirrors sometimes reject
# downloads temporarily (HTTP 429 "Too Many Requests").
retry() {
    local attempt
    for attempt in 1 2 3 4 5; do
        if "$@"; then
            return 0
        fi
        echo "Command failed (attempt ${attempt}/5), retrying in $((attempt * 30)) s: $*"
        sleep $((attempt * 30))
    done
    return 1
}

echo "== Installing MSYS2 tools"
retry pacman -S --needed --noconfirm git unzip mingw-w64-x86_64-wget mingw-w64-x86_64-ninja mingw-w64-x86_64-cmake mingw-w64-x86_64-gcc

echo "== Fetching submodules"
retry git -C "${NATRON_DIR}" submodule update --init --recursive

echo "== Installing Natron build dependencies (Natron pacman repository)"
if ! pacman -Q mingw-w64-x86_64-natron-build-deps-qt5 >/dev/null 2>&1; then
    "${NATRON_DIR}/.github/workflows/install_natron_pacman_repo.sh" "${NATRON_DIR}" "${NATRON_DIR}/natron_pacman_repo"
    retry pacman -S --needed --noconfirm --overwrite "*" mingw-w64-x86_64-natron-build-deps-qt5
fi
if ! pacman -Q mingw-w64-x86_64-natron-build-deps-qt5; then
    echo "The Natron build dependencies are not installed: check the messages above."
    exit 1
fi

echo "== Fetching OpenColorIO configs"
if [[ ! -d "${NATRON_DIR}/OpenColorIO-Configs" ]]; then
    (cd "${NATRON_DIR}" &&
        retry wget "https://github.com/NatronGitHub/OpenColorIO-Configs/archive/Natron-v${OCIO_CONFIG_VERSION}.tar.gz" &&
        tar xzf "Natron-v${OCIO_CONFIG_VERSION}.tar.gz" &&
        mv "OpenColorIO-Configs-Natron-v${OCIO_CONFIG_VERSION}" OpenColorIO-Configs &&
        rm "Natron-v${OCIO_CONFIG_VERSION}.tar.gz")
fi

echo "== Fetching the openfx-io plug-ins (Read/Write nodes)"
if [[ ! -d "${BUILD_DIR}/Plugins" ]]; then
    mkdir -p "${BUILD_DIR}/Plugins"
    (cd "${BUILD_DIR}/Plugins" &&
        retry wget https://github.com/NatronGitHub/openfx-io/releases/download/natron_testing/openfx-io-build-windows_latest-testing.zip &&
        unzip -q openfx-io-build-windows_latest-testing.zip &&
        rm openfx-io-build-windows_latest-testing.zip)
fi

echo "== Checking the compiler"
if ! gcc --version || ! g++ --version; then
    echo "gcc/g++ cannot be run. Check the output above, then re-run: pacman -S mingw-w64-x86_64-gcc"
    exit 1
fi
# A previous configure that could not find the compiler leaves a broken cache behind.
if [[ -f "${BUILD_DIR}/CMakeCache.txt" ]] && grep -q '^CMAKE_C\(XX\)\?_COMPILER:.*NOTFOUND' "${BUILD_DIR}/CMakeCache.txt"; then
    echo "Removing a CMake cache left by a failed configure"
    rm -f "${BUILD_DIR}/CMakeCache.txt"
    rm -rf "${BUILD_DIR}/CMakeFiles"
fi

echo "== Configuring (RelWithDebInfo, NATRON_TRACY=${TRACY})"
# RelWithDebInfo keeps optimizations (representative timings) and adds debug symbols.
cmake -S "${NATRON_DIR}" -B "${BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DNATRON_BUILD_TESTS=OFF \
    -DNATRON_TRACY="${TRACY}"

echo "== Building"
cmake --build "${BUILD_DIR}"

echo
echo "Done. Start Natron with: tools/profiling/run-msys2.sh --build-dir \"${BUILD_DIR}\""
