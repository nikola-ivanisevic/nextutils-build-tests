# nextutils-build-tests

Benchmarks the nextutils build pipeline across multiple sequential runs, collecting timing data into a CSV.

## Script

`run-build-test.sh` — the main script. No dependencies beyond bash and standard POSIX tools.

## Usage

```bash
./run-build-test.sh --nexthome space3|space4[:N] [--nexthome ...] [--runs N]
```

| Argument | Required | Default | Description |
|---|---|---|---|
| `--nexthome SPACE[:N]` | yes (repeatable) | — | Space to test, with optional per-space run count |
| `--runs N` | no | `2` | Default run count when not specified per-space |

**Examples:**

```bash
# Single space, default 2 runs
./run-build-test.sh --nexthome space4

# Single space, explicit run count
./run-build-test.sh --nexthome space3 --runs 5

# Multiple spaces with per-space run counts
./run-build-test.sh --nexthome space3:2 --nexthome space4:3

# Multiple spaces sharing a default run count
./run-build-test.sh --nexthome space3 --nexthome space4 --runs 4
```

## What it does

For each run:
1. `cd /workspace/nikolai/nextutils`
2. Times `./setup.sh --fetch-next-toolchain --fetch-python --create-buildtools-venv --fetch-syntacore-toolchain --fetch-nfisim --fetch-networking`
3. Times `./build.sh -c`

Environment variables (`NEXT_HOME`, `CCACHE_DIR`, `CONAN_HOME`, `UV_CACHE_DIR`) are set inline based on the selected space — no `.bashrc` sourcing required.

## Output

| File | Description |
|---|---|
| `build-test-YYYYMMDD-<space>.csv` | Per-run timing data (written incrementally) |
| `build-test-YYYYMMDD-<space>.log` | Summary table appended at end of run |

CSV columns: `run`, `setup_duration_s`, `build_duration_s`, `total_duration_s`, `status`

A formatted summary table is printed to stdout and appended to the `.log` file on exit — including on Ctrl-C interruption.

## Error handling

If `setup.sh` or `build.sh` fails, the run is recorded as `FAILED` with elapsed time, and the script continues to the next run.
