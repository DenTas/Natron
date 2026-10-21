#!/bin/bash
# Build Natron (Qt5) and the openfx-misc / openfx-io plug-ins on Windows with
# MSYS2, in the UCRT64 environment, optionally instrumented for Tracy.
#
# Why UCRT64: MSYS2 no longer builds pyside2, pyside6, python-qtpy, breakpad,
# openimageio or opencolorio for MINGW64, so the MINGW64-based Windows CI
# (and its Natron pacman repository) cannot be installed any more. Every
# dependency below comes from the official MSYS2 UCRT64 repository, and the
# plug-ins are built from source, following the approach of
# https://github.com/Niik-l/Natron (tools/win-build), whose openfx patches
# are reused in tools/profiling/patches.
#
# Usage (from the MSYS2 UCRT64 shell, at the root of the Natron checkout):
#   tools/profiling/build-msys2.sh [--tracy] [--build-dir DIR]
#
# Then run Natron with tools/profiling/run-msys2.sh.

set -euo pipefail

NATRON_DIR=$(cd "$(dirname "$0")/../.." && pwd)
PATCH_DIR="${NATRON_DIR}/tools/profiling/patches"
BUILD_DIR="${NATRON_DIR}/build-profiling"
TRACY=OFF
OCIO_CONFIG_VERSION=2.5
# Plug-in revisions the patches apply to (same pins as Niik-l/Natron).
OPENFX_MISC_REF=0abd46b5a8cbc98fa24579042129460d0aa87b8f
OPENFX_IO_REF=31ebb488d0b4aec52e92ec94cdc30da277091d30

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tracy) TRACY=ON; shift ;;
        --build-dir) BUILD_DIR=$(realpath -m "$2"); shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ "${MSYSTEM:-}" != "UCRT64" ]]; then
    echo "Run this script from the MSYS2 UCRT64 shell (Start menu: \"MSYS2 UCRT64\")."
    exit 1
fi

SRC_DIR="${BUILD_DIR}/src"
PLUGIN_DIR="${BUILD_DIR}/Plugins"
P=mingw-w64-ucrt-x86_64

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

echo "== Installing dependencies (official MSYS2 UCRT64 packages)"
retry pacman -S --needed --noconfirm \
    git unzip wget curl make patch \
    $P-gcc $P-cmake $P-ninja $P-pkgconf \
    $P-qt5-base $P-pyside2 $P-python $P-boost $P-cairo $P-expat \
    $P-openimageio $P-openexr $P-imath $P-opencolorio $P-ffmpeg $P-libraw $P-libpng $P-seexpr

echo "== Checking the compiler"
if ! gcc --version || ! g++ --version; then
    echo "gcc/g++ cannot be run. Check the output above, then re-run: pacman -S $P-gcc"
    exit 1
fi

echo "== Fetching Natron submodules"
retry git -C "${NATRON_DIR}" submodule update --init --recursive

echo "== Fetching OpenColorIO configs"
if [[ ! -d "${NATRON_DIR}/OpenColorIO-Configs" ]]; then
    (cd "${NATRON_DIR}" &&
        retry wget -O ocio-configs.tar.gz "https://github.com/NatronGitHub/OpenColorIO-Configs/archive/Natron-v${OCIO_CONFIG_VERSION}.tar.gz" &&
        tar xzf ocio-configs.tar.gz &&
        mv "OpenColorIO-Configs-Natron-v${OCIO_CONFIG_VERSION}" OpenColorIO-Configs &&
        rm ocio-configs.tar.gz)
fi

# A previous configure that could not find the compiler leaves a broken cache behind.
drop_broken_cache() {
    if [[ -f "$1/CMakeCache.txt" ]] && grep -q '^CMAKE_C\(XX\)\?_COMPILER:.*NOTFOUND' "$1/CMakeCache.txt"; then
        echo "Removing a CMake cache left by a failed configure in $1"
        rm -f "$1/CMakeCache.txt"
        rm -rf "$1/CMakeFiles"
    fi
}

# Clone an openfx repository at a pinned revision and apply its patches
# (patches/<name>.patch, then patches/<name>-*.patch), each one only once.
fetch_plugin_source() {
    local name="$1" ref="$2" dir="${SRC_DIR}/$1"
    if [[ ! -d "${dir}/.git" ]]; then
        retry git clone "https://github.com/NatronGitHub/${name}.git" "${dir}"
        git -C "${dir}" checkout -q "${ref}"
    fi
    retry git -C "${dir}" submodule update --init --recursive
    local patch
    for patch in "${PATCH_DIR}/${name}.patch" "${PATCH_DIR}/${name}"-*.patch; do
        [[ -f "${patch}" ]] || continue
        if git -C "${dir}" apply --reverse --check "${patch}" 2>/dev/null; then
            echo "${name}: $(basename "${patch}") already applied"
        else
            git -C "${dir}" apply "${patch}"
        fi
    done
}

# Configure and build a plug-in, then install each <Plugin>.ofx as an OFX bundle.
build_plugin() {
    local name="$1"; shift
    local dir="${SRC_DIR}/${name}"
    drop_broken_cache "${dir}/build"
    # CMAKE_POLICY_VERSION_MINIMUM: the plug-ins declare an old cmake_minimum_required
    # that CMake 4 rejects otherwise.
    cmake -S "${dir}" -B "${dir}/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    cmake --build "${dir}/build"
    local ofx
    for ofx in "$@"; do
        if [[ ! -f "${dir}/build/${ofx}.ofx" ]]; then
            echo "${name}: ${ofx}.ofx was not built"
            exit 1
        fi
        mkdir -p "${PLUGIN_DIR}/${ofx}.ofx.bundle/Contents/Win64"
        cp "${dir}/build/${ofx}.ofx" "${PLUGIN_DIR}/${ofx}.ofx.bundle/Contents/Win64/"
    done
}

mkdir -p "${SRC_DIR}"

echo "== Building the openfx-misc plug-ins (Blur, Grade, Transform...)"
fetch_plugin_source openfx-misc "${OPENFX_MISC_REF}"
retry make -C "${SRC_DIR}/openfx-misc/CImg" CImg.h
build_plugin openfx-misc Misc CImg

echo "== Building the openfx-io plug-ins (Read/Write nodes)"
fetch_plugin_source openfx-io "${OPENFX_IO_REF}"
build_plugin openfx-io IO

echo "== Configuring Natron (RelWithDebInfo, NATRON_TRACY=${TRACY})"
drop_broken_cache "${BUILD_DIR}"
# RelWithDebInfo keeps optimizations (representative timings) and adds debug symbols.
cmake -S "${NATRON_DIR}" -B "${BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DNATRON_BUILD_TESTS=OFF \
    -DNATRON_TRACY="${TRACY}"

echo "== Building Natron"
cmake --build "${BUILD_DIR}"

echo
echo "Done. Start Natron with: tools/profiling/run-msys2.sh --build-dir \"${BUILD_DIR}\""
