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

echo "== Installing MSYS2 tools"
pacman -S --needed --noconfirm git unzip mingw-w64-x86_64-wget mingw-w64-x86_64-ninja mingw-w64-x86_64-cmake

echo "== Fetching submodules"
git -C "${NATRON_DIR}" submodule update --init --recursive

echo "== Installing Natron build dependencies (Natron pacman repository)"
if ! pacman -Q mingw-w64-x86_64-natron-build-deps-qt5 >/dev/null 2>&1; then
    "${NATRON_DIR}/.github/workflows/install_natron_pacman_repo.sh" "${NATRON_DIR}" "${NATRON_DIR}/natron_pacman_repo"
    pacman -S --needed --noconfirm --overwrite "*" mingw-w64-x86_64-natron-build-deps-qt5
fi

echo "== Fetching OpenColorIO configs"
if [[ ! -d "${NATRON_DIR}/OpenColorIO-Configs" ]]; then
    (cd "${NATRON_DIR}" &&
        wget "https://github.com/NatronGitHub/OpenColorIO-Configs/archive/Natron-v${OCIO_CONFIG_VERSION}.tar.gz" &&
        tar xzf "Natron-v${OCIO_CONFIG_VERSION}.tar.gz" &&
        mv "OpenColorIO-Configs-Natron-v${OCIO_CONFIG_VERSION}" OpenColorIO-Configs &&
        rm "Natron-v${OCIO_CONFIG_VERSION}.tar.gz")
fi

echo "== Fetching the openfx-io plug-ins (Read/Write nodes)"
if [[ ! -d "${BUILD_DIR}/Plugins" ]]; then
    mkdir -p "${BUILD_DIR}/Plugins"
    (cd "${BUILD_DIR}/Plugins" &&
        wget https://github.com/NatronGitHub/openfx-io/releases/download/natron_testing/openfx-io-build-windows_latest-testing.zip &&
        unzip -q openfx-io-build-windows_latest-testing.zip &&
        rm openfx-io-build-windows_latest-testing.zip)
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
