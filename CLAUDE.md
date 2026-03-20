# nextutils build test script

This repo contains a script to benchmark the build of nextutils across multiple runs.

## What the script does

Each run must:
1. `cd /workspace/nikolai/nextutils`
2. Run and time: `./setup.sh --fetch-next-toolchain --fetch-python --create-buildtools-venv --fetch-syntacore-toolchain --fetch-nfisim --fetch-networking`
3. Run and time: `./build.sh -c`

Runs are sequential, not parallel.

## Environment / nexthome

Before running, the script must export the correct environment variables based on the chosen space. The mappings are (derived from `~/.bashrc.nikolai`):

| Space   | `NEXT_HOME`                        | `CCACHE_DIR`              | `CONAN_HOME`              | `UV_CACHE_DIR`              |
|---------|------------------------------------|---------------------------|---------------------------|-----------------------------|
| space3  | `/space3/users/nikolai/next_home/` | `/space3/users/nikolai/.ccache` | `/space3/users/nikolai/.conan2` | `/space3/users/nikolai/.cache/uv` |
| space4  | `/space4/users/nikolai/next_home/` | `/space4/users/nikolai/.ccache` | `/space4/users/nikolai/.conan2` | `/space4/users/nikolai/.cache/uv` |

The script should NOT rely on sourcing `.bashrc.nikolai` — export these vars inline based on the selected space.

## Arguments

- `--nexthome space3|space4[:N]` — which space to use (required, repeatable); optional `:N` sets per-space run count
- `--runs N` — default run count when no per-space count is given (default: 2)

Multiple `--nexthome` flags are supported to run against several spaces in one invocation, e.g. `--nexthome space3:2 --nexthome space4:3`. Runs are always sequential (all runs for space3, then all for space4, etc.).

## Output

### CSV file

- Location: repo root
- Filename: `build-test-YYYYMMDD-<space>.csv` (e.g. `build-test-20260320-space4.csv`)
- Columns: `run`, `setup_duration_s`, `build_duration_s`, `total_duration_s`, `status`
- Write each row immediately after the run completes so partial results are preserved if interrupted

### Table summary

- Print a formatted table to stdout at the end
- Also append the same table to the CSV file (or a companion `.log` file — pick one and document it)
- If the script is interrupted, the table should reflect only the completed runs

## Error handling

- If `setup.sh` or `build.sh` exits with a non-zero status, record the run as `FAILED` with the elapsed time up to that point, then continue to the next run
- Do not abort the entire test on a single failure

## Implementation

The script is implemented in **bash** (`run-build-test.sh`). Chosen over Go/Rust since the task is pure shell orchestration with no complex data structures.

### Key implementation notes

- `--nexthome` is repeatable; each entry is a `"space[:N]"` string parsed at runtime
- All `--nexthome` values are validated upfront before any runs start
- Each space gets its own CSV and `.log` file; both are listed in the final summary
- Summary table is appended to a companion `.log` file (not the CSV) to keep the CSV machine-readable
- `trap finalize EXIT` ensures the summary is printed/logged even on Ctrl-C
- Each CSV row is written immediately after the run completes (incremental writes)
- `setup.sh` failure skips `build.sh` for that run but continues to the next iteration
- Subshell `(cd "$WORKSPACE" && ...)` is used to avoid changing the script's own working directory
- Environment variables are exported inline based on `--nexthome` — no `.bashrc` sourcing
