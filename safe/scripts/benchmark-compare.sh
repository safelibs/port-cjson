#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <original-build-dir> <safe-build-dir>" >&2
    exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SAFE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$SAFE_DIR/.." && pwd)
ORIGINAL_DIR="$REPO_ROOT/original"
ORIGINAL_BUILD_DIR=$(cd "$1" && pwd)
SAFE_BUILD_DIR=$(cd "$2" && pwd)
PARSE_BENCH_SOURCE="$SAFE_DIR/tests/perf/parse_print_bench.c"
UTILS_BENCH_SOURCE="$SAFE_DIR/tests/perf/utils_patch_bench.c"
TESTS_INPUT_DIR=$(cd "$ORIGINAL_DIR/tests/inputs" && pwd)
FUZZ_INPUT_DIR=$(cd "$ORIGINAL_DIR/fuzzing/inputs" && pwd)
PATCH_TESTS_JSON=$(cd "$ORIGINAL_DIR/tests/json-patch-tests" && pwd)/tests.json
PATCH_SPEC_JSON=$(cd "$ORIGINAL_DIR/tests/json-patch-tests" && pwd)/spec_tests.json
PATCH_UTILS_JSON=$(cd "$ORIGINAL_DIR/tests/json-patch-tests" && pwd)/cjson-utils-tests.json
WORK_DIR=$(mktemp -d)
CC_BIN=${CC:-cc}

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
    printf 'benchmark-compare: %s\n' "$*" >&2
    exit 1
}

expect_file() {
    [[ -f "$1" ]] || fail "missing file: $1"
}

expect_dir() {
    [[ -d "$1" ]] || fail "missing directory: $1"
}

find_python() {
    if command -v python3 >/dev/null 2>&1; then
        command -v python3
        return
    fi

    if command -v python >/dev/null 2>&1; then
        command -v python
        return
    fi

    fail "python interpreter not found"
}

build_source_dir() {
    sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$1/CMakeCache.txt" | tail -n1
}

cargo_profile_name() {
    local build_type

    build_type=$(sed -n 's/^CMAKE_BUILD_TYPE:STRING=//p' "$1/CMakeCache.txt" | tail -n1)
    case "$build_type" in
        Release|RelWithDebInfo|MinSizeRel)
            printf 'release'
            ;;
        *)
            printf 'debug'
            ;;
    esac
}

locate_library_dir() {
    local build_dir=$1
    local profile_dir
    local library_path

    profile_dir="$build_dir/cargo-target/$(cargo_profile_name "$build_dir")"
    if [ -e "$profile_dir/libcjson.so.1" ] && [ -e "$profile_dir/libcjson_utils.so.1" ]; then
        printf '%s\n' "$profile_dir"
        return
    fi

    library_path=$(find "$build_dir" -maxdepth 4 \( -type f -o -type l \) \( -name 'libcjson.so' -o -name 'libcjson.so.*' \) | sort | head -n1 || true)
    [[ -n "$library_path" ]] || fail "failed to locate libcjson.so under $build_dir"
    printf '%s\n' "$(dirname "$library_path")"
}

compile_core_bench() {
    local source_root=$1
    local library_dir=$2
    local output=$3

    "$CC_BIN" -O2 -std=c89 -pedantic -Wall -Wextra -Werror \
        -I"$source_root" \
        "$PARSE_BENCH_SOURCE" \
        -L"$library_dir" \
        -Wl,-rpath,"$library_dir" \
        -lcjson \
        -lm \
        -o "$output"
}

compile_utils_bench() {
    local source_root=$1
    local library_dir=$2
    local output=$3

    "$CC_BIN" -O2 -std=c89 -pedantic -Wall -Wextra -Werror \
        -I"$source_root" \
        "$UTILS_BENCH_SOURCE" \
        -L"$library_dir" \
        -Wl,-rpath,"$library_dir" \
        -lcjson_utils \
        -lcjson \
        -lm \
        -o "$output"
}

prepare_variant() {
    local variant=$1
    local build_dir=$2
    local expected_source=$3
    local source_root
    local library_dir
    local parse_binary="$WORK_DIR/${variant}-parse_print_bench"
    local utils_binary="$WORK_DIR/${variant}-utils_patch_bench"

    expect_file "$build_dir/CMakeCache.txt"

    source_root=$(build_source_dir "$build_dir")
    source_root=$(cd "$source_root" && pwd)
    [[ "$source_root" == "$expected_source" ]] || fail "$build_dir was configured for $source_root, expected $expected_source"

    library_dir=$(locate_library_dir "$build_dir")
    expect_file "$library_dir/libcjson.so"
    expect_file "$library_dir/libcjson_utils.so"

    printf 'benchmark-compare: compiling %s benches against %s\n' "$variant" "$build_dir" >&2
    compile_core_bench "$source_root" "$library_dir" "$parse_binary"
    compile_utils_bench "$source_root" "$library_dir" "$utils_binary"

    printf '%s\n' "$source_root;$library_dir;$parse_binary;$utils_binary"
}

expect_file "$PARSE_BENCH_SOURCE"
expect_file "$UTILS_BENCH_SOURCE"
expect_dir "$TESTS_INPUT_DIR"
expect_dir "$FUZZ_INPUT_DIR"
expect_file "$PATCH_TESTS_JSON"
expect_file "$PATCH_SPEC_JSON"
expect_file "$PATCH_UTILS_JSON"

PYTHON_BIN=$(find_python)

ORIGINAL_VARIANT=$(prepare_variant original "$ORIGINAL_BUILD_DIR" "$ORIGINAL_DIR")
SAFE_VARIANT=$(prepare_variant safe "$SAFE_BUILD_DIR" "$SAFE_DIR")

IFS=';' read -r ORIGINAL_SOURCE_ROOT ORIGINAL_LIBRARY_DIR ORIGINAL_PARSE_BIN ORIGINAL_UTILS_BIN <<<"$ORIGINAL_VARIANT"
IFS=';' read -r SAFE_SOURCE_ROOT SAFE_LIBRARY_DIR SAFE_PARSE_BIN SAFE_UTILS_BIN <<<"$SAFE_VARIANT"

export ORIGINAL_BUILD_DIR SAFE_BUILD_DIR
export ORIGINAL_SOURCE_ROOT SAFE_SOURCE_ROOT
export ORIGINAL_LIBRARY_DIR SAFE_LIBRARY_DIR
export ORIGINAL_PARSE_BIN ORIGINAL_UTILS_BIN SAFE_PARSE_BIN SAFE_UTILS_BIN
export TESTS_INPUT_DIR FUZZ_INPUT_DIR PATCH_TESTS_JSON PATCH_SPEC_JSON PATCH_UTILS_JSON

"$PYTHON_BIN" - <<'PY'
import json
import os
import statistics
import subprocess
import sys
import time

TARGET_SECONDS = 0.30
MAX_ITERATIONS = 4096
RUNS = 5
TIMEOUT_SECONDS = 120.0


def eprint(message: str) -> None:
    print(message, file=sys.stderr)


def run_timed(command, extra_env):
    merged_env = os.environ.copy()
    merged_env.update(extra_env)
    start = time.perf_counter()
    completed = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=TIMEOUT_SECONDS,
        env=merged_env,
        check=False,
    )
    elapsed = time.perf_counter() - start
    if completed.returncode != 0:
        raise RuntimeError(
            "command failed",
            {
                "command": command,
                "returncode": completed.returncode,
                "stdout": completed.stdout,
                "stderr": completed.stderr,
            },
        )
    return elapsed, completed.stdout.strip()


def calibrate_iterations(workload):
    iterations = 1
    extra_env = {"LD_LIBRARY_PATH": workload["original_library_dir"]}

    while True:
        command = [workload["original_binary"], *workload["args"], str(iterations)]
        elapsed, _ = run_timed(command, extra_env)
        if elapsed >= TARGET_SECONDS or iterations >= MAX_ITERATIONS:
            return iterations, elapsed

        if elapsed <= 0.0:
            scale = 8
        else:
            scale = int(TARGET_SECONDS / elapsed)
            if scale < 2:
                scale = 2
            if scale > 8:
                scale = 8

        next_iterations = iterations * scale
        if next_iterations <= iterations:
            next_iterations = iterations + 1
        if next_iterations > MAX_ITERATIONS:
            next_iterations = MAX_ITERATIONS

        iterations = next_iterations


def measure_variant(workload, variant):
    binary = workload[f"{variant}_binary"]
    library_dir = workload[f"{variant}_library_dir"]
    command = [binary, *workload["args"], str(workload["iterations"])]
    timings = []
    outputs = []

    run_timed(command, {"LD_LIBRARY_PATH": library_dir})

    for _ in range(RUNS):
        elapsed, output = run_timed(command, {"LD_LIBRARY_PATH": library_dir})
        timings.append(elapsed)
        outputs.append(output)

    return timings, outputs[-1]


workloads = [
    {
        "name": "parse",
        "binary_kind": "core",
        "threshold": 1.6,
        "args": [
            "parse",
            os.environ["TESTS_INPUT_DIR"],
            os.environ["FUZZ_INPUT_DIR"],
        ],
    },
    {
        "name": "print_unformatted",
        "binary_kind": "core",
        "threshold": 1.5,
        "args": [
            "print-unformatted",
            os.environ["TESTS_INPUT_DIR"],
            os.environ["FUZZ_INPUT_DIR"],
        ],
    },
    {
        "name": "print_buffered",
        "binary_kind": "core",
        "threshold": 1.5,
        "args": [
            "print-buffered",
            os.environ["TESTS_INPUT_DIR"],
            os.environ["FUZZ_INPUT_DIR"],
        ],
    },
    {
        "name": "minify",
        "binary_kind": "core",
        "threshold": 1.5,
        "args": [
            "minify",
            os.environ["TESTS_INPUT_DIR"],
            os.environ["FUZZ_INPUT_DIR"],
        ],
    },
    {
        "name": "apply_patches",
        "binary_kind": "utils",
        "threshold": 1.5,
        "args": [
            "apply",
            os.environ["PATCH_TESTS_JSON"],
            os.environ["PATCH_SPEC_JSON"],
            os.environ["PATCH_UTILS_JSON"],
        ],
    },
    {
        "name": "generate_patches",
        "binary_kind": "utils",
        "threshold": 1.5,
        "args": [
            "generate",
            os.environ["PATCH_TESTS_JSON"],
            os.environ["PATCH_SPEC_JSON"],
            os.environ["PATCH_UTILS_JSON"],
        ],
    },
    {
        "name": "generate_merge_patch",
        "binary_kind": "utils",
        "threshold": 1.5,
        "args": [
            "merge",
            os.environ["PATCH_TESTS_JSON"],
            os.environ["PATCH_SPEC_JSON"],
            os.environ["PATCH_UTILS_JSON"],
        ],
    },
]

for workload in workloads:
    if workload["binary_kind"] == "core":
        workload["original_binary"] = os.environ["ORIGINAL_PARSE_BIN"]
        workload["safe_binary"] = os.environ["SAFE_PARSE_BIN"]
    else:
        workload["original_binary"] = os.environ["ORIGINAL_UTILS_BIN"]
        workload["safe_binary"] = os.environ["SAFE_UTILS_BIN"]

    workload["original_library_dir"] = os.environ["ORIGINAL_LIBRARY_DIR"]
    workload["safe_library_dir"] = os.environ["SAFE_LIBRARY_DIR"]


results = []
violations = []

for workload in workloads:
    eprint(f"benchmark-compare: calibrating {workload['name']}")
    iterations, calibration_elapsed = calibrate_iterations(workload)
    workload["iterations"] = iterations

    eprint(
        f"benchmark-compare: running {workload['name']} "
        f"(iterations={iterations}, calibration={calibration_elapsed:.6f}s)"
    )

    original_runs, original_output = measure_variant(workload, "original")
    safe_runs, safe_output = measure_variant(workload, "safe")
    original_median = statistics.median(original_runs)
    safe_median = statistics.median(safe_runs)
    ratio = safe_median / max(original_median, 1e-9)
    outputs_match = original_output == safe_output
    passed = outputs_match and (ratio <= workload["threshold"])

    result = {
        "name": workload["name"],
        "iterations": iterations,
        "threshold": workload["threshold"],
        "calibration_seconds": calibration_elapsed,
        "original_median_seconds": original_median,
        "safe_median_seconds": safe_median,
        "safe_over_original_ratio": ratio,
        "original_runs_seconds": original_runs,
        "safe_runs_seconds": safe_runs,
        "original_output": original_output,
        "safe_output": safe_output,
        "outputs_match": outputs_match,
        "status": (
            "pass"
            if passed
            else "output_mismatch"
            if not outputs_match
            else "threshold_exceeded"
        ),
    }
    results.append(result)
    if not passed:
        violations.append(result)


summary = {
    "status": "pass" if not violations else "fail",
    "original_build_dir": os.environ["ORIGINAL_BUILD_DIR"],
    "safe_build_dir": os.environ["SAFE_BUILD_DIR"],
    "original_source_root": os.environ["ORIGINAL_SOURCE_ROOT"],
    "safe_source_root": os.environ["SAFE_SOURCE_ROOT"],
    "corpora": {
        "tests_inputs_dir": os.environ["TESTS_INPUT_DIR"],
        "fuzz_inputs_dir": os.environ["FUZZ_INPUT_DIR"],
        "patch_files": [
            os.environ["PATCH_TESTS_JSON"],
            os.environ["PATCH_SPEC_JSON"],
            os.environ["PATCH_UTILS_JSON"],
        ],
    },
    "runs_per_workload": RUNS,
    "results": results,
    "violations": [
        {
            "name": result["name"],
            "status": result["status"],
            "threshold": result["threshold"],
            "safe_over_original_ratio": result["safe_over_original_ratio"],
            "outputs_match": result["outputs_match"],
        }
        for result in violations
    ],
}

json.dump(summary, sys.stdout, indent=2, sort_keys=True)
sys.stdout.write("\n")

if violations:
    sys.exit(1)
PY
