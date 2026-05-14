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

Preexisting source/API cases:

- `allocator-hooks-edge`: passed
- `malformed-number-rejection`: passed
- `minify-whitespace`: passed
- `parse-print-roundtrip`: passed
- `utils-patch-pointer`: passed

Preexisting CVE regression cases:

- `cve-2023-26819`: passed
- `cve-2025-57052`: passed

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
