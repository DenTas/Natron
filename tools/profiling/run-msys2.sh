#!/bin/bash
# Start a Natron build made by build-msys2.sh, with the environment it needs
# (same variables as the Windows tests in .github/workflows/ci.yml).
#
# Usage (from the MSYS2 MINGW64 shell):
#   tools/profiling/run-msys2.sh [--build-dir DIR] [Natron arguments...]

set -euo pipefail

NATRON_DIR=$(cd "$(dirname "$0")/../.." && pwd)
BUILD_DIR="${NATRON_DIR}/build-profiling"

if [[ "${1:-}" == "--build-dir" ]]; then
    BUILD_DIR=$(realpath -m "$2")
    shift 2
fi

export PYTHONHOME=/mingw64
export OFX_PLUGIN_PATH="${BUILD_DIR}/Plugins"
export OCIO="${NATRON_DIR}/OpenColorIO-Configs/blender/config.ocio"

exec "${BUILD_DIR}/App/Natron.exe" "$@"
