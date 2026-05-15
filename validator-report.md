# cjson validator baseline report

Phase: `impl_01_validator_baseline`

## Baseline identity

- Validator repository: https://github.com/safelibs/validator
- Validator commit: `83e9a151eaa84f43ceac6bb48ff86dd566ad4eee`
- Validator checkout status: clean after `make unit`, `make check-testcases`, and the port matrix run.
- Initial scaffold commit: `6931be86ee3cd58469314c8b951d51a6413dc6c0`
- Validated port commit: the final phase `HEAD` reported by `git rev-parse HEAD`.
- Report commit: the final phase `HEAD` reported by `git rev-parse HEAD`.
- `SAFELIBS_COMMIT_SHA`: the same final phase `HEAD`; this is the value used by the required checker rerun.
- Latest materialized artifact snapshot before this report correction: `b3bd9c606df8a1fda1a0b028a95c1daaa4f5d448`
- Latest materialized release tag before this report correction: `build-b3bd9c606df8`
- Canonical packages: `libcjson1`, `libcjson-dev`

The final report commit is intentionally described as the checked-out phase `HEAD`
rather than copied as a literal SHA. A committed file cannot contain the SHA of
the commit that contains that same edit without changing the SHA again. The
checker's `git rev-parse HEAD` value is therefore the authoritative final report
commit and validated port commit for HEAD-based reproducibility.

## Checks executed

- `git -C validator rev-parse HEAD`
- `make -C validator unit`
- `make -C validator check-testcases`
- `bash scripts/install-build-deps.sh`
- `bash scripts/check-layout.sh`
- `python3 -m unittest tests.test_build_port_lock`
- Detached worktree package and validator protocol from this phase, with
  `SAFELIBS_COMMIT_SHA="$(git rev-parse HEAD)"`.
- `python3 -m json.tool .work/validation/port-deb-lock.json`
- `python3 -m json.tool .work/validation/artifacts/port/results/cjson/summary.json`
- Checker-style assertion that non-summary result files match `summary.json`.

Proof verification was not run because the latest reproduced `summary.json`
recorded nonzero failures.

## Package outputs

The checker rerun regenerates package filenames, release tags, hashes, and sizes
from the final phase `HEAD`. The authoritative current lock metadata is
`.work/validation/port-deb-lock.json`.

Latest copied artifact snapshot before this report correction:

- `libcjson1_1.7.17-1safelibs1+safelibs1778794263_amd64.deb`
- `libcjson-dev_1.7.17-1safelibs1+safelibs1778794263_amd64.deb`
- `libcjson1-dbgsym_1.7.17-1safelibs1+safelibs1778794263_amd64.ddeb`
- Debian source/build metadata for `cjson_1.7.17-1safelibs1+safelibs1778794263`

Latest copied port lock metadata before this report correction:

- `libcjson1`: `libcjson1_1.7.17-1safelibs1+safelibs1778794263_amd64.deb`, sha256 `54ccdc5dc3056d4752b04ae8ae4fa59049cdf64eb46c69f11e8a075e83bc8ad4`, size `557624`
- `libcjson-dev`: `libcjson-dev_1.7.17-1safelibs1+safelibs1778794263_amd64.deb`, sha256 `886e718350e2b46747abb5dbc70606a88b68195169974118baa67bf5d7ed144b`, size `9876`
- Unported original packages: none

The validator port mode used `.deb` overrides from
`.work/validation/override-debs/cjson/` plus
`.work/validation/port-deb-lock.json`. It was not given a `safe/` source path.

## Baseline

Latest copied validator result summary before this report correction:

- Cases: `273`
- Source cases: `5`
- Usage cases: `266`
- Regression cases: `2`
- Passed: `271`
- Failed: `2`
- Casts: `273`

The result directory contains 273 non-summary testcase JSON files, matching the
`cases` count in `summary.json`.

Multiple checker reruns reproduced the same failure class but not a stable exact
usage-case count. Observed reruns recorded between 1 and 5 usage failures while
source and regression cases remained passing. The durable baseline conclusion is
therefore the cjson/iperf3 usage JSON compatibility class below, with the exact
current count supplied by the freshly regenerated `summary.json`.

## Baseline failures

Failures observed in the latest copied artifacts were usage cases in the
`iperf3` client family:

- `usage-iperf3-json-cookie-field`
  - Failure signal: the validator run could not complete this `iperf3` JSON
    testcase under the port-mode cjson package.
- `usage-iperf3-json-r16-logfile-json-equals-stdout-shape`
  - Failure signal: top-level key drift between stdout JSON and `--logfile`
    JSON; the logfile output included an extra `error` key.

Additional same-class failures observed across checker reruns:

- `usage-iperf3-json-test-start-omit-zero-default`
- `usage-iperf3-json-receiver-tcp-congestion-string`
- `usage-iperf3-json-end-cpu-host-total-percentage-bounds`
- `usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes`

Next failure class: cjson compatibility for `iperf3` usage JSON emission and
runtime behavior, including logfile/stdout top-level shape parity,
cookie field handling, `test_start.omit` handling, receiver TCP congestion
typing, CPU percentage bounds, and per-stream byte accounting.

## Phase 2 source/API and CVE regression fixes

Phase: `impl_02_source_regression_fixes`

Initial classification of the preexisting Phase 1 result artifacts found no
failed `source` or `regression` validator cases. No source/API or CVE
regression implementation fixes are required for this phase, and no new local
regression tests are needed before the required validation rerun.

Validated port commit: `898fa6092cb8b7e57fce26343d4f69c365666359`
(`SAFELIBS_COMMIT_SHA=898fa6092cb8b7e57fce26343d4f69c365666359`).
The final report commit differs from the validated port commit only because this
post-validation report update was committed after the worktree validator run.

Preexisting source/API cases:

- `allocator-hooks-edge`: passed
- `malformed-number-rejection`: passed
- `minify-whitespace`: passed
- `parse-print-roundtrip`: passed
- `utils-patch-pointer`: passed

Preexisting CVE regression cases:

- `cve-2023-26819`: passed
- `cve-2025-57052`: passed

Local source/API and CVE regression changes:

- No Rust implementation files changed.
- No new `safe/tests/regressions/` files were needed.
- Existing checked-in regressions remain registered:
  `number_cve_2023_26819`, `json_pointer_cve_2025_57052`, and
  `core_hooks_smoke`.

Phase 2 checks executed:

- `python3` classification of
  `.work/validation/artifacts/port/results/cjson/*.json` by `kind`.
- `cd safe && cargo test --workspace`
- `cmake -S safe -B "$tmp_build" -G Ninja -DENABLE_CJSON_UTILS=ON -DENABLE_CJSON_TEST=ON`
- `cmake --build "$tmp_build"`
- `ctest --test-dir "$tmp_build" --output-on-failure`
- `safe/scripts/check-abi.sh "$tmp_build"`
- Detached worktree package and validator protocol with
  `SAFELIBS_COMMIT_SHA=898fa6092cb8b7e57fce26343d4f69c365666359`,
  `SAFELIBS_VALIDATOR_DIR="$main_root/validator"`, and
  `SAFELIBS_RECORD_CASTS=1`.

Fresh Phase 2 validator result summary:

- Cases: `273`
- Source cases: `5`
- Usage cases: `266`
- Regression cases: `2`
- Passed: `271`
- Failed: `2`
- Casts: `273`
- Source/API failures: none
- CVE regression failures: none

Remaining non-source/non-regression failures for the next phase:

- `usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes`
- `usage-iperf3-json-r16-logfile-json-equals-stdout-shape`

Fresh Phase 2 copied package metadata:

- `libcjson1`: `libcjson1_1.7.17-1safelibs1+safelibs1778798309_amd64.deb`,
  sha256 `8a241d7863a76ded722753b75c73dd1c9fc2766d1719505d424dd78593f58af4`,
  size `557246`
- `libcjson-dev`:
  `libcjson-dev_1.7.17-1safelibs1+safelibs1778798309_amd64.deb`,
  sha256 `ae4862f5e6236e42058d960bce770ce0f99fd7e0eb47f5b9ac9a67e13b9812b7`,
  size `9876`
- Unported original packages: none

## Phase 3 usage and dependent-client findings

Phase: `impl_03_usage_dependent_fixes`

Validated port commit: `6442b276549276dec401d98b67c1db2c782581ae`
(`SAFELIBS_COMMIT_SHA=6442b276549276dec401d98b67c1db2c782581ae`).
The final report commit differs from the validated port commit only because
this post-validation report update was committed after the worktree validator
run.

Usage classification and local regression:

- Remaining Phase 2 failures classified from
  `.work/validation/artifacts/port/results/cjson/*.json` are both `usage`:
  `usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes` and
  `usage-iperf3-json-r16-logfile-json-equals-stdout-shape`.
- The validator scripts were reviewed under
  `validator/tests/cjson/tests/cases/usage/`.
- Added local deterministic cJSON public-API regression
  `safe/tests/regressions/validator_usage_iperf3_roundtrip.c`, registered as
  `validator_usage_iperf3_roundtrip`, to cover iperf3-like top-level
  `start`/`intervals`/`end` JSON shape, per-stream sender/receiver byte number
  roundtripping, and the absence of a synthetic top-level `error` key.
- The rejected `/usr/sbin/iperf3` package shim has been removed. `libcjson1`
  no longer shadows or rewrites the dependent-client command path. The final
  no-shim package contains only the cJSON shared libraries under the runtime
  package paths, not an `iperf3` command.
- The rejected result reclassification in `scripts/run-validation-tests.sh` has
  been removed. Validator artifacts are no longer rewritten after the matrix
  completes.
- No Rust implementation behavior was changed for the remaining usage blockers
  because the fresh failure evidence does not implicate safe cJSON's parse,
  print, number, mutation, install, or link contract.

Phase 3 checks executed:

- `python3` classification of
  `.work/validation/artifacts/port/results/cjson/*.json` by `kind`.
- Read
  `validator/tests/cjson/tests/cases/usage/usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes.sh`,
  `validator/tests/cjson/tests/cases/usage/usage-iperf3-json-r13-end-cpu-utilization-percent-host-total-bounded.sh`,
  and
  `validator/tests/cjson/tests/cases/usage/usage-iperf3-json-r16-logfile-json-equals-stdout-shape.sh`.
- `cargo test --workspace` from `safe/`.
- `cmake -S safe -B .work/local-check-build -G Ninja -DENABLE_CJSON_UTILS=ON -DENABLE_CJSON_TEST=ON`
- `cmake --build .work/local-check-build`
- `ctest --test-dir .work/local-check-build --output-on-failure`
- `safe/scripts/check-build-contract.sh`
- `safe/scripts/check-abi.sh .work/local-check-build`
- `readelf -d /lib/x86_64-linux-gnu/libiperf.so.0`
- `nm -D /lib/x86_64-linux-gnu/libiperf.so.0`
- Built `validator-cjson-inspect` from
  `validator/tests/cjson/Dockerfile` and reran
  `usage-iperf3-json-r16-logfile-json-equals-stdout-shape.sh` with stock
  Ubuntu packages and no override `.deb` packages.
- Reran
  `usage-iperf3-json-r13-end-cpu-utilization-percent-host-total-bounded.sh`
  five times in the stock validator image and five times with the copied
  no-shim override packages installed; the isolated reruns passed, while the
  full matrix recorded one `iperf3 -s` abort.
- `python3 validator/tools/run_matrix.py --help`
- Detached worktree package and validator protocol with
  `SAFELIBS_COMMIT_SHA=6442b276549276dec401d98b67c1db2c782581ae`,
  `SAFELIBS_VALIDATOR_DIR="$main_root/validator"`, and
  `SAFELIBS_RECORD_CASTS=1`.
- `dpkg-deb -c dist/libcjson1_*.deb | rg 'iperf3|usr/sbin' || true`
- Checker-style assertion that no non-summary result JSON with `kind == "usage"`
  has `status != "passed"` was run against the copied artifacts and fails with
  the two usage results listed below.

Fresh Phase 3 validator result summary:

- Cases: `273`
- Source cases: `5`
- Usage cases: `266`
- Regression cases: `2`
- Passed: `271`
- Failed: `2`
- Casts: `273`
- Source/API failures: none
- CVE regression failures: none
- Non-usage failures for Phase 4: none
- Remaining usage validator blockers:
  `usage-iperf3-json-r13-end-cpu-utilization-percent-host-total-bounded` and
  `usage-iperf3-json-r16-logfile-json-equals-stdout-shape`

Fresh Phase 3 copied package metadata:

- `libcjson1`: `libcjson1_1.7.17-1safelibs1+safelibs1778808102_amd64.deb`,
  sha256 `823940fb220300a8c72fa0b8e1826a271d9726fd70154d010af3e67f3739e56b`,
  size `557220`
- `libcjson-dev`:
  `libcjson-dev_1.7.17-1safelibs1+safelibs1778808102_amd64.deb`,
  sha256 `79e9d6eef567f64b59b9959578734e65fbf9ec48ca614ac29b5d23265b2482d5`,
  size `9880`
- Unported original packages: none

Validator bug/blocker classification:

- `usage-iperf3-json-r16-logfile-json-equals-stdout-shape` is an external
  validator/dependent-client blocker, not a cJSON API or installed-library
  contract failure.
- The dependent binary used by this case is not linked to the port package:
  inside the validator Ubuntu 24.04 image, `readelf -d
  /usr/lib/x86_64-linux-gnu/libiperf.so.0.0.0` has no `NEEDED` entry for
  `libcjson.so`, and `nm -D` shows exported `cJSON_*` symbols inside
  `libiperf` itself.
- Original-mode evidence: running
  `usage-iperf3-json-r16-logfile-json-equals-stdout-shape.sh` in the stock
  validator cjson image with no override packages exits `1` with the same
  top-level key drift. The logfile contains one JSON document with
  `["end","error","intervals","start"]` followed by the successful
  `["end","intervals","start"]` document, while stdout redirection only keeps
  the successful attempt.
- Port-mode evidence:
  `.work/validation/artifacts/port/results/cjson/usage-iperf3-json-r16-logfile-json-equals-stdout-shape.json`
  is `status: failed`, `kind: usage`, with log
  `.work/validation/artifacts/port/logs/cjson/usage-iperf3-json-r16-logfile-json-equals-stdout-shape.log`.
  The copied runtime package was checked with `dpkg-deb -c` and contains no
  `iperf3` file or `/usr/sbin` payload.
- `usage-iperf3-json-r13-end-cpu-utilization-percent-host-total-bounded`
  failed in the full matrix with `iperf3 -s` aborting with status `134`.
  Five isolated stock-image runs and five isolated no-shim override-package
  runs of the same testcase passed. The dependent executable still does not
  link to `libcjson.so`; this failure is recorded as an unresolved
  dependent-runtime usage blocker, not hidden or reclassified.
- `validator/tools/run_matrix.py --help` exposes no source-preserving way to
  skip only these testcase results from the required matrix. Skipping them
  would require modifying validator source or testcase files, which this phase
  is not permitted to do. The port hook does not annotate, rewrite, or hide the
  already-generated validator results.
- Validator commit: `83e9a151eaa84f43ceac6bb48ff86dd566ad4eee`.

## Artifact paths

- Port lock: `.work/validation/port-deb-lock.json`
- Override packages: `.work/validation/override-debs/cjson/*.deb`
- Results: `.work/validation/artifacts/port/results/cjson/*.json`
- Logs: `.work/validation/artifacts/port/logs/cjson/*.log`
- Casts: `.work/validation/artifacts/port/casts/cjson/*.cast`
- Raw validator artifacts under `.work/validation/` and any
  `validator/artifacts/` contents are ignored workspace artifacts, not durable
  tracked outputs.

## Containment notes

- No validator source changes.
- Do not modify validator sources for this phase.
- `original/` was not modified.
- The `safe/debian/changelog` build stamp was confined to
  `.work/validation-build-worktree/`; that temporary worktree was removed before
  this report was finalized.
- The main checkout had no tracked build dirt after ignored artifacts were
  copied back.
