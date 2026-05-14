# cjson validator baseline report

Phase: `impl_01_validator_baseline`

## Baseline identity

- Validator repository: https://github.com/safelibs/validator
- Validator commit: `d1c08d01cd50b34a7aeb62c5630e28df0eb6cd97`
- Validator checkout status: clean after `make unit`, `make check-testcases`, and the port matrix run.
- Initial scaffold commit: `6931be86ee3cd58469314c8b951d51a6413dc6c0`
- Validated port commit: `444180c22188c48d21a43dfad0fd4340bc873d9e`
- Current validation artifact commit: `444180c22188c48d21a43dfad0fd4340bc873d9e`
- Current validation release tag: `build-444180c22188`
- Report commit: `e059b758d835eb876282beaacf6fd8a44d62d7b2`
- Report SHA metadata correction commit: `444180c22188c48d21a43dfad0fd4340bc873d9e`
- Canonical packages: `libcjson1`, `libcjson-dev`

The current copied validation artifacts were regenerated from commit
`444180c22188c48d21a43dfad0fd4340bc873d9e` so this report records that artifact
snapshot rather than the earlier scaffold-only run.

## Checks executed

- `git clone https://github.com/safelibs/validator validator`
- `git -C validator rev-parse HEAD`
- `make -C validator unit`
- `make -C validator check-testcases`
- `bash scripts/install-build-deps.sh`
- `bash scripts/check-layout.sh`
- `python3 -m unittest tests.test_build_port_lock`
- Detached worktree package and validator protocol from this phase, using `SAFELIBS_COMMIT_SHA=444180c22188c48d21a43dfad0fd4340bc873d9e`.
- `python3 -m json.tool .work/validation/port-deb-lock.json`
- `python3 -m json.tool .work/validation/artifacts/port/results/cjson/summary.json`
- Checker-style assertion that 253 non-summary result files match `summary.json`.

Proof verification was not run because `summary.json` recorded `failed: 2`.

## Package outputs

Built package artifacts copied back under ignored `dist/`:

- `libcjson1_1.7.17-1safelibs1+safelibs1778733136_amd64.deb`
- `libcjson-dev_1.7.17-1safelibs1+safelibs1778733136_amd64.deb`
- `libcjson1-dbgsym_1.7.17-1safelibs1+safelibs1778733136_amd64.ddeb`
- Debian source/build metadata for `cjson_1.7.17-1safelibs1+safelibs1778733136`

Port lock metadata in `.work/validation/port-deb-lock.json`:

- `libcjson1`: `libcjson1_1.7.17-1safelibs1+safelibs1778733136_amd64.deb`, sha256 `a0ce4682001cd3a311eb5ea05e1bba59574b0852891150da795c09c68f094aee`, size `557262`
- `libcjson-dev`: `libcjson-dev_1.7.17-1safelibs1+safelibs1778733136_amd64.deb`, sha256 `e509111edce721b30c46b74bd3a1f7d4ee94843b5f0693e7ec11e8ebe7c12b92`, size `9878`
- Unported original packages: none

The validator port mode used `.deb` overrides from `.work/validation/override-debs/cjson/` plus `.work/validation/port-deb-lock.json`. It was not given a `safe/` source path.

## Baseline

Current validator result summary from `.work/validation/artifacts/port/results/cjson/summary.json`:

- Cases: `253`
- Source cases: `5`
- Usage cases: `246`
- Regression cases: `2`
- Passed: `251`
- Failed: `2`
- Casts: `253`

The result directory contains 253 non-summary testcase JSON files, matching the `cases` count in `summary.json`.

## Baseline failures

Failures: `2` usage cases in the current copied artifacts; source and regression cases passed.

- `usage-iperf3-json-r16-logfile-json-equals-stdout-shape`
  - Client: `iperf3`
  - Exit code: `1`
  - Log: `.work/validation/artifacts/port/logs/cjson/usage-iperf3-json-r16-logfile-json-equals-stdout-shape.log`
  - Failure signal: top-level key drift between stdout JSON and `--logfile` JSON; the logfile output included an extra `error` key.
- `usage-iperf3-json-test-start-omit-zero-default`
  - Client: `iperf3`
  - Exit code: `134`
  - Log: `.work/validation/artifacts/port/logs/cjson/usage-iperf3-json-test-start-omit-zero-default.log`
  - Failure signal: the `iperf3 -s -1` server process aborted before the test could validate `start.test_start.omit == 0`.

The senior checker previously observed a current-artifact rerun with `failed: 3`
for the same `iperf3` usage failure class. That run included one additional
failure not present in the copied artifacts above:

- `usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes`
  - Client: `iperf3`
  - Failure signal from checker output: the per-stream receiver/sender byte
    closeness predicate failed under port-mode cjson JSON output.

Next failure class: cjson compatibility for `iperf3` usage JSON emission and runtime behavior, including logfile/stdout top-level shape parity, `test_start.omit` handling, and per-stream byte accounting.

## Artifact paths

- Port lock: `.work/validation/port-deb-lock.json`
- Override packages: `.work/validation/override-debs/cjson/*.deb`
- Results: `.work/validation/artifacts/port/results/cjson/*.json`
- Logs: `.work/validation/artifacts/port/logs/cjson/*.log`
- Casts: `.work/validation/artifacts/port/casts/cjson/*.cast`
- Raw validator artifacts under `.work/validation/` and any `validator/artifacts/` contents are ignored workspace artifacts, not durable tracked outputs.

## Containment notes

- No validator source changes.
- Do not modify validator sources for this phase.
- `original/` was not modified.
- The `safe/debian/changelog` build stamp was confined to `.work/validation-build-worktree/`; that temporary worktree was removed before this report was finalized.
- The main checkout had no tracked build dirt after ignored artifacts were copied back.
