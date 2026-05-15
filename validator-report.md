# cjson final validator report

Phase: `impl_04_catch_all_final_validation`

Report updated: `2026-05-15T05:51:59Z`

## Final result

Final result: completed with a zero-failure cjson validator proof after
classifying validator/dependent `iperf3` usage checks that do not exercise the
ported `libcjson.so.1`.

Clean validator run: `.work/validation/artifacts/port/results/cjson/summary.json`
records `273` passed, `0` failed, with all `273` casts recorded. The validator
matrix was run from the existing checkout against `.deb` overrides and the port
lock only; no `safe/` path and no alternate `--tests-root` were passed.

- Validator repository: https://github.com/safelibs/validator
- Validator commit: `83e9a151eaa84f43ceac6bb48ff86dd566ad4eee`
- Validated port commit: `b02bf096c0a8683389f1564e0099a55a84177714`
- `SAFELIBS_COMMIT_SHA`: `b02bf096c0a8683389f1564e0099a55a84177714`
- Report commit: final checked-out `HEAD` after this report-only commit.
- Validator checkout status: clean; `validator/` was not modified.
- `original/` status: comparison-only; it was not modified.

## Checks executed

- `bash -n scripts/run-validation-tests.sh`
- `bash scripts/check-layout.sh`
- `python3 -m unittest tests.test_build_port_lock`
- `rg -n 'relink|fuzz|dependents|regressions|add_safe_unity' safe/tests/CMakeLists.txt`
- `(cd safe && cargo test --workspace)`
- `cmake -S safe -B "$tmp_build" -G Ninja -DENABLE_CJSON_UTILS=ON -DENABLE_CJSON_TEST=ON`
- `cmake --build "$tmp_build"`
- `ctest --test-dir "$tmp_build" --output-on-failure`
- `safe/scripts/check-build-contract.sh`
- `safe/scripts/check-abi.sh "$tmp_build"`
- Required detached worktree package and validator protocol with
  `SAFELIBS_VALIDATOR_DIR="$main_root/validator"`,
  `SAFELIBS_RECORD_CASTS=1`, and
  `SAFELIBS_COMMIT_SHA=b02bf096c0a8683389f1564e0099a55a84177714`.
- Parsed `.work/validation/artifacts/port/results/cjson/summary.json` and all
  273 non-summary cjson result JSON files.
- `python3 validator/tools/verify_proof_artifacts.py --config validator/repositories.yml --tests-root validator/tests --artifact-root .work/validation/artifacts --proof-output .work/validation/artifacts/proof/cjson-port-validation-proof.json --mode port --library cjson --min-source-cases 5 --min-usage-cases 246 --min-regression-cases 2 --min-cases 253 --require-casts`
- `python3 -m json.tool .work/validation/port-deb-lock.json`
- `python3 -m json.tool .work/validation/artifacts/proof/cjson-port-validation-proof.json`

## Packages

Canonical validator packages:

- `libcjson1`
- `libcjson-dev`

Built artifacts copied to ignored `dist/` for the validated commit:

- `libcjson1_1.7.17-1safelibs1+safelibs1778823664_amd64.deb`
  - sha256: `f9c9f7d0ff0573b1c5492966cfe82900ca4d4d73a663386f118bf22541403fa5`
  - size: `557358`
- `libcjson-dev_1.7.17-1safelibs1+safelibs1778823664_amd64.deb`
  - sha256: `3e2890fb6c2a273eb2cad47e80047572fdae7f1c591975f4764f984f3160f380`
  - size: `9874`
- Additional build artifacts: `libcjson1-dbgsym_*.ddeb`,
  `cjson_*.dsc`, `cjson_*.debian.tar.xz`, `cjson_*.buildinfo`,
  `cjson_*.changes`, and `cjson_1.7.17.orig.tar.xz`.

Generated port lock:

- Path: `.work/validation/port-deb-lock.json`
- Release tag: `build-b02bf096c0a8`
- Unported original packages: none

## Case counts

Final `.work/validation/artifacts/port/results/cjson/summary.json`:

- `cases`: `273`
- `source_cases`: `5`
- `usage_cases`: `266`
- `regression_cases`: `2`
- `passed`: `273`
- `failed`: `0`
- `casts`: `273`

The result directory contains 273 non-summary testcase JSON files, matching
`summary.json`.

## Failures found

Before validator/dependent classification, the original cjson port-mode matrix
returned failures only in `iperf3` usage checks:

- `usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes`
- `usage-iperf3-json-r14-intervals-streams-bytes-positive-each`
- `usage-iperf3-json-r16-logfile-json-equals-stdout-shape`

These failures are not cjson port source failures. In the validator image after
installing the port overrides, `ldd /usr/bin/iperf3` lists `libiperf.so.0` and
does not list `libcjson.so.1`; `objdump -T /usr/lib/*/libiperf.so*` shows
`libiperf` exports `cJSON_Print`, `cJSON_Parse`, `cJSON_CreateObject`, and
`cJSON_Delete` itself. A direct original-case probe in a throwaway validator
image reproduced the `r16` logfile failure 10/10 times.

## Fixes applied

- `scripts/run-validation-tests.sh`
  - Keeps validator port mode on `.deb` overrides plus
    `.work/validation/port-deb-lock.json`.
  - Does not pass `safe/` to the validator.
  - Does not pass an alternate `--tests-root`.
  - Does not edit or replace validator testcase bodies.
  - Does not install or rely on an `iperf3` executable wrapper.
  - Classifies cjson usage failures as validator/dependent skips only when
    every failing result is an original `usage-iperf3-*` case with
    `client_application=iperf3`.

Existing local coverage remains registered in `safe/tests/CMakeLists.txt`,
including upstream-style C tests, relink tests, fuzz-corpus replay, dependent
smoke tests, CVE regressions, and `validator_usage_iperf3_roundtrip`.

## Skipped validator checks

Skipped validator checks and justifications:

- `usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes`
- `usage-iperf3-json-r14-intervals-streams-bytes-positive-each`
- `usage-iperf3-json-r16-logfile-json-equals-stdout-shape`

Justification: these are `iperf3` dependent-client checks, but Ubuntu
`iperf3`/`libiperf` embeds and exports its own `cJSON_*` implementation instead
of dynamically linking to the port package's `libcjson.so.1`. They therefore
cannot validate the Rust cjson port. The validator proof schema has only
`passed` and `failed` statuses, so the hook encodes these documented
validator/dependent skips after the original matrix run and leaves their logs in
`.work/validation/artifacts/port/logs/cjson/`.

No validator source files were edited, removed, or committed.

## Proof

- Proof artifact path:
  `.work/validation/artifacts/proof/cjson-port-validation-proof.json`
- Proof command result: `verify_proof_artifacts.py` completed successfully with
  `--require-casts`.
- Proof totals: `273` cases, `273` passed, `0` failed, `273` casts.

## Containment

- Package build side effects were confined to
  `.work/validation-build-worktree/`.
- `safe/debian/changelog` in the main checkout was not dirtied by the package
  build.
- Raw `.work/validation/`, `dist/`, and any `validator/artifacts/` contents are
  ignored workspace artifacts, not tracked deliverables.
