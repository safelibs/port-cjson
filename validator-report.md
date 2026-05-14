# cjson validator baseline report

Phase: `impl_01_validator_baseline`

## Baseline identity

- Validator repository: https://github.com/safelibs/validator
- Validator commit: `d1c08d01cd50b34a7aeb62c5630e28df0eb6cd97`
- Validator checkout status: clean after `make unit`, `make check-testcases`, and the port matrix run.
- Validated port commit: `6931be86ee3cd58469314c8b951d51a6413dc6c0`
- Validated release tag: `build-6931be86ee3c`
- Report commit: `e059b758d835eb876282beaacf6fd8a44d62d7b2` (completed baseline report commit; different from the validated port commit because package validation ran after the scaffold commit).
- Canonical packages: `libcjson1`, `libcjson-dev`

## Checks executed

- `git clone https://github.com/safelibs/validator validator`
- `git -C validator rev-parse HEAD`
- `make -C validator unit`
- `make -C validator check-testcases`
- `bash scripts/install-build-deps.sh`
- `bash scripts/check-layout.sh`
- `python3 -m unittest tests.test_build_port_lock`
- Detached worktree package and validator protocol from this phase, using `SAFELIBS_COMMIT_SHA=6931be86ee3cd58469314c8b951d51a6413dc6c0`.
- `python3 -m json.tool .work/validation/port-deb-lock.json`
- `python3 -m json.tool .work/validation/artifacts/port/results/cjson/summary.json`
- Checker-style assertion that 253 non-summary result files match `summary.json`.

Proof verification was not run because `summary.json` recorded `failed: 2`.

## Package outputs

Built package artifacts copied back under ignored `dist/`:

- `libcjson1_1.7.17-1safelibs1+safelibs1778731185_amd64.deb`
- `libcjson-dev_1.7.17-1safelibs1+safelibs1778731185_amd64.deb`
- `libcjson1-dbgsym_1.7.17-1safelibs1+safelibs1778731185_amd64.ddeb`
- Debian source/build metadata for `cjson_1.7.17-1safelibs1+safelibs1778731185`

Port lock metadata in `.work/validation/port-deb-lock.json`:

- `libcjson1`: `libcjson1_1.7.17-1safelibs1+safelibs1778731185_amd64.deb`, sha256 `723cfc0a1c4b5c0c8de4bd4278d1b4e8c3e018557dfea0d34e568eb6f4044c75`, size `557596`
- `libcjson-dev`: `libcjson-dev_1.7.17-1safelibs1+safelibs1778731185_amd64.deb`, sha256 `95f05db3b06ede800c44a787dc0a6605202358faf3f53a80c92d51feeda37cce`, size `9872`
- Unported original packages: none

The validator port mode used `.deb` overrides from `.work/validation/override-debs/cjson/` plus `.work/validation/port-deb-lock.json`. It was not given a `safe/` source path.

## Baseline

Validator result summary from `.work/validation/artifacts/port/results/cjson/summary.json`:

- Cases: `253`
- Source cases: `5`
- Usage cases: `246`
- Regression cases: `2`
- Passed: `251`
- Failed: `2`
- Casts: `253`

The result directory contains 253 non-summary testcase JSON files, matching the `cases` count in `summary.json`.

## Baseline failures

Failures: `2` usage cases.

Two port-mode usage cases failed; source and regression cases passed.

- `usage-iperf3-json-end-cpu-host-total-percentage-bounds`
  - Client: `iperf3`
  - Exit code: `1`
  - Log: `.work/validation/artifacts/port/logs/cjson/usage-iperf3-json-end-cpu-host-total-percentage-bounds.log`
  - Failure signal: the validator jq predicate for `.end.cpu_utilization_percent.host_total` being a `0..100` number evaluated to `false`.
- `usage-iperf3-json-r16-logfile-json-equals-stdout-shape`
  - Client: `iperf3`
  - Exit code: `1`
  - Log: `.work/validation/artifacts/port/logs/cjson/usage-iperf3-json-r16-logfile-json-equals-stdout-shape.log`
  - Failure signal: top-level key drift between stdout JSON and `--logfile` JSON; the logfile output included an extra `error` key.

Next failure class: cjson compatibility for `iperf3` usage JSON emission, specifically numeric CPU utilization bounds and logfile/stdout top-level shape parity.

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
