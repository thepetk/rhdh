#!/bin/bash

#
# Copyright Red Hat, Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Benchmark script: measures and compares execution time of concurrent vs sequential
# install-dynamic-plugins modes.
#
# Usage: ./benchmark.sh [--concurrent|--sequential] [--cached] [dynamic-plugins-root-dir]
#   --concurrent                   run only the concurrent mode
#   --sequential                    run only the sequential mode
#   (no flag)                 run both modes and compare
#   --cached                  warm up the install dir first, then measure the
#                             re-run where all plugins are already cached
#   dynamic-plugins-root-dir: directory where plugins will be installed
#                             (default: /tmp/dynamic-plugins-root)

MODE="both"
CACHED=false
POSITIONAL=()

for arg in "$@"; do
    case "$arg" in
        --concurrent)  MODE="concurrent" ;;
        --sequential)   MODE="sequential" ;;
        --cached) CACHED=true ;;
        *)        POSITIONAL+=("$arg") ;;
    esac
done

INSTALL_DIR="${POSITIONAL[0]:-/tmp/dynamic-plugins-root}"

cleanup() {
    local dir="$1"
    echo "  Cleaning up $dir ..."
    rm -rf "$dir"
}

warmup() {
    local label="$1"
    local script="$2"
    local dir="$3"

    mkdir -p "$dir"
    echo ""
    echo "==> Warming up $label (installing all plugins into $dir) ..."
    python3 "$script" "$dir" > /dev/null 2>&1
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "  [WARN] warm-up for $label exited with code $exit_code — cached timings may be inaccurate"
    else
        echo "  Warm-up done."
    fi
}

ELAPSED_S="0.000"

run_and_measure() {
    local label="$1"
    local script="$2"
    local dir="$3"

    mkdir -p "$dir"
    echo ""
    echo "==> Running $label mode (output dir: $dir)"
    local start
    start=$(date +%s%N)

    python3 "$script" "$dir"
    local exit_code=$?

    local end
    end=$(date +%s%N)
    local elapsed_ms=$(( (end - start) / 1000000 ))
    ELAPSED_S=$(LC_NUMERIC=C awk "BEGIN {printf \"%.3f\", $elapsed_ms / 1000}")

    if [ $exit_code -ne 0 ]; then
        echo "  [WARN] $label exited with code $exit_code"
    fi

    echo "  $label duration: ${ELAPSED_S} s"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONCURRENT_SCRIPT="$SCRIPT_DIR/install-dynamic-plugins-concurrent.py"
SEQUENTIAL_SCRIPT="$SCRIPT_DIR/install-dynamic-plugins.py"

for script in "$CONCURRENT_SCRIPT" "$SEQUENTIAL_SCRIPT"; do
    if [ ! -f "$script" ]; then
        echo "Error: script not found: $script" >&2
        exit 1
    fi
done

CONCURRENT_DIR="${INSTALL_DIR}-concurrent"
SEQUENTIAL_DIR="${INSTALL_DIR}-sequential"

concurrent_s=""
sequential_s=""

if [ "$MODE" = "concurrent" ] || [ "$MODE" = "both" ]; then
    [ "$CACHED" = true ] && warmup "concurrent" "$CONCURRENT_SCRIPT" "$CONCURRENT_DIR"
    run_and_measure "concurrent" "$CONCURRENT_SCRIPT" "$CONCURRENT_DIR"
    concurrent_s=$ELAPSED_S
    cleanup "$CONCURRENT_DIR"
fi

if [ "$MODE" = "sequential" ] || [ "$MODE" = "both" ]; then
    [ "$CACHED" = true ] && warmup "sequential" "$SEQUENTIAL_SCRIPT" "$SEQUENTIAL_DIR"
    run_and_measure "sequential" "$SEQUENTIAL_SCRIPT" "$SEQUENTIAL_DIR"
    sequential_s=$ELAPSED_S
    cleanup "$SEQUENTIAL_DIR"
fi

# --- Summary ---
echo ""
echo "=============================="
if [ "$CACHED" = true ]; then
    echo "  Benchmark results (cached)"
else
    echo "  Benchmark results (cold)"
fi
echo "=============================="

if [ "$MODE" = "both" ]; then
    printf "  %-8s %s s\n" "concurrent:" "$concurrent_s"
    printf "  %-8s %s s\n" "sequential:" "$sequential_s"
    diff_s=$(LC_NUMERIC=C awk "BEGIN {d = $concurrent_s - $sequential_s; if (d < 0) d = -d; printf \"%.3f\", d}")
    winner=$(LC_NUMERIC=C awk "BEGIN {print ($concurrent_s < $sequential_s) ? \"concurrent\" : ($sequential_s < $concurrent_s) ? \"sequential\" : \"tie\"}")
    if [ "$winner" = "tie" ]; then
        echo "  Both modes took the same time."
    else
        printf "  %s was faster by %s s\n" "$winner" "$diff_s"
    fi
else
    printf "  %-8s %s s\n" "$MODE:" "${concurrent_s:-$sequential_s}"
fi
echo "=============================="
