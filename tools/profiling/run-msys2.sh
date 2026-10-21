#!/bin/bash
# Start a Natron build made by build-msys2.sh, with the environment it needs.
#
# Usage (from the MSYS2 UCRT64 shell):
#   tools/profiling/run-msys2.sh [--build-dir DIR] [Natron arguments...]

set -euo pipefail

NATRON_DIR=$(cd "$(dirname "$0")/../.." && pwd)
BUILD_DIR="${NATRON_DIR}/build-profiling"

if [[ "${1:-}" == "--build-dir" ]]; then
    BUILD_DIR=$(realpath -m "$2")
    shift 2
fi

if [[ "${MSYSTEM:-}" != "UCRT64" ]]; then
    echo "Run this script from the MSYS2 UCRT64 shell (Start menu: \"MSYS2 UCRT64\")."
    exit 1
fi

export PYTHONHOME=/ucrt64
export OFX_PLUGIN_PATH="${BUILD_DIR}/Plugins"
export OCIO="${NATRON_DIR}/OpenColorIO-Configs/blender/config.ocio"

exec "${BUILD_DIR}/App/Natron.exe" "$@"
