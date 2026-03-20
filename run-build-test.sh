#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="/workspace/nikolai/nextutils"

# --- Argument parsing ---
# SPACES is an array of "space:runs" pairs, e.g. "space3:2" "space4:3"
SPACES=()
DEFAULT_RUNS=2

usage() {
    echo "Usage: $0 --nexthome space3|space4[:N] [--nexthome space3|space4[:N]] ... [--runs N]"
    echo ""
    echo "  --nexthome SPACE[:N]   Space to test, with optional per-space run count"
    echo "  --runs N               Default run count when not specified per-space (default: 2)"
    echo ""
    echo "Examples:"
    echo "  $0 --nexthome space4"
    echo "  $0 --nexthome space3:2 --nexthome space4:3"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --nexthome)
            SPACES+=("$2"); shift 2 ;;
        --runs)
            DEFAULT_RUNS="$2"; shift 2 ;;
        *)
            echo "Unknown argument: $1"; usage ;;
    esac
done

[[ ${#SPACES[@]} -eq 0 ]] && { echo "Error: --nexthome is required"; usage; }
[[ "$DEFAULT_RUNS" =~ ^[1-9][0-9]*$ ]] || { echo "Error: --runs must be a positive integer"; exit 1; }

# Validate all --nexthome values upfront
for entry in "${SPACES[@]}"; do
    space="${entry%%:*}"
    [[ "$space" != "space3" && "$space" != "space4" ]] && {
        echo "Error: unknown space '$space' — must be space3 or space4"; exit 1;
    }
    if [[ "$entry" == *:* ]]; then
        n="${entry##*:}"
        [[ "$n" =~ ^[1-9][0-9]*$ ]] || { echo "Error: run count for '$space' must be a positive integer, got '$n'"; exit 1; }
    fi
done

# --- Helpers ---
elapsed_s() {
    echo $(( $(date +%s) - $1 ))
}

set_env_for_space() {
    local space=$1
    case "$space" in
        space3)
            export NEXT_HOME="/space3/users/nikolai/next_home/"
            export CCACHE_DIR="/space3/users/nikolai/.ccache"
            export CONAN_HOME="/space3/users/nikolai/.conan2"
            export UV_CACHE_DIR="/space3/users/nikolai/.cache/uv"
            ;;
        space4)
            export NEXT_HOME="/space4/users/nikolai/next_home/"
            export CCACHE_DIR="/space4/users/nikolai/.ccache"
            export CONAN_HOME="/space4/users/nikolai/.conan2"
            export UV_CACHE_DIR="/space4/users/nikolai/.cache/uv"
            ;;
    esac
}

print_table() {
    local csv="$1" space="$2"
    printf "\n  %-6s  %16s  %14s  %14s  %s\n" "Run" "Setup (s)" "Build (s)" "Total (s)" "Status"
    printf "  %-6s  %16s  %14s  %14s  %s\n" "------" "----------------" "--------------" "--------------" "--------"
    tail -n +2 "$csv" | while IFS=, read -r run setup build total status; do
        printf "  %-6s  %16s  %14s  %14s  %s\n" "$run" "$setup" "$build" "$total" "$status"
    done
}

# --- Collect all CSV files written during this session for final summary ---
SESSION_CSVS=()

finalize() {
    echo ""
    echo "========================================"
    echo "  Build Test Session Summary"
    echo "========================================"
    for csv in "${SESSION_CSVS[@]}"; do
        local_space=$(basename "$csv" | sed 's/build-test-[0-9]*-//;s/\.csv//')
        echo ""
        echo "  [ $local_space ]"
        print_table "$csv"
        {
            echo ""
            echo "=== Build Test Summary: $local_space ($(date)) ==="
            print_table "$csv"
        } >> "${csv%.csv}.log"
    done
    echo ""
    for csv in "${SESSION_CSVS[@]}"; do
        log="${csv%.csv}.log"
        echo "  CSV: $csv"
        echo "  Log: $log"
    done
}
trap finalize EXIT

DATE=$(date +%Y%m%d)

# --- Iterate over spaces ---
for entry in "${SPACES[@]}"; do
    space="${entry%%:*}"
    runs="${DEFAULT_RUNS}"
    [[ "$entry" == *:* ]] && runs="${entry##*:}"

    set_env_for_space "$space"

    CSV_FILE="${SCRIPT_DIR}/build-test-${DATE}-${space}.csv"
    SESSION_CSVS+=("$CSV_FILE")

    echo "========================================"
    echo "  Space: $space  |  Runs: $runs"
    echo "========================================"
    echo "run,setup_duration_s,build_duration_s,total_duration_s,status" > "$CSV_FILE"

    for (( run=1; run<=runs; run++ )); do
        echo ""
        echo "--- $space  run $run / $runs ---"

        run_start=$(date +%s)
        setup_duration=0
        build_duration=0
        status="OK"

        # Setup
        echo "  [setup.sh] starting..."
        setup_start=$(date +%s)
        if (cd "$WORKSPACE" && ./setup.sh \
                --fetch-next-toolchain \
                --fetch-python \
                --create-buildtools-venv \
                --fetch-syntacore-toolchain \
                --fetch-nfisim \
                --fetch-networking); then
            setup_duration=$(elapsed_s "$setup_start")
            echo "  [setup.sh] done in ${setup_duration}s"
        else
            setup_duration=$(elapsed_s "$setup_start")
            total_duration=$(elapsed_s "$run_start")
            echo "  [setup.sh] FAILED after ${setup_duration}s"
            echo "${run},${setup_duration},0,${total_duration},FAILED" >> "$CSV_FILE"
            continue
        fi

        # Build
        echo "  [build.sh] starting..."
        build_start=$(date +%s)
        if (cd "$WORKSPACE" && ./build.sh -c); then
            build_duration=$(elapsed_s "$build_start")
            echo "  [build.sh] done in ${build_duration}s"
        else
            build_duration=$(elapsed_s "$build_start")
            status="FAILED"
            echo "  [build.sh] FAILED after ${build_duration}s"
        fi

        total_duration=$(elapsed_s "$run_start")
        echo "${run},${setup_duration},${build_duration},${total_duration},${status}" >> "$CSV_FILE"
        echo "  Run $run complete: total=${total_duration}s  status=${status}"
    done
done
