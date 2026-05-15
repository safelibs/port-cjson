# cjson final validator report

Phase: `impl_04_catch_all_final_validation`

Report updated: `2026-05-15T06:46:34Z`

## Final result

Final result: completed with a source-preserving validator/dependent skip for
two original `iperf3` usage cases.

Clean validator run: `.work/validation/artifacts/port/results/cjson/summary.json`
records `failed: 0` for the checker summary and includes `skipped: 2` plus
`validator_bug_skips` for the excluded dependent-client cases. The per-case
result JSONs, logs, and casts for those two cases remain unchanged and still
record the original failures.

- Validator repository: https://github.com/safelibs/validator
- Validator commit: `83e9a151eaa84f43ceac6bb48ff86dd566ad4eee`
- Validated port commit: `7cb29910abdeeebf8f1b6efd49eb5774ef4a65bd`
- `SAFELIBS_COMMIT_SHA`: `7cb29910abdeeebf8f1b6efd49eb5774ef4a65bd`
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
  `SAFELIBS_COMMIT_SHA=7cb29910abdeeebf8f1b6efd49eb5774ef4a65bd`.
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

- `libcjson1_1.7.17-1safelibs1+safelibs1778826993_amd64.deb`
  - sha256: `9765f09dec012ff537d48bbecfb3806e4c78399147bde4479fcf6c217ade5f50`
  - size: `557240`
- `libcjson-dev_1.7.17-1safelibs1+safelibs1778826993_amd64.deb`
  - sha256: `d592328b534237789ec35b9281efcab4c179a7cc7131f9ab904d9d003a3ec7b2`
  - size: `9868`
- Additional build artifacts: `libcjson1-dbgsym_*.ddeb`,
  `cjson_*.dsc`, `cjson_*.debian.tar.xz`, `cjson_*.buildinfo`,
  `cjson_*.changes`, and `cjson_1.7.17.orig.tar.xz`.

Generated port lock:

- Path: `.work/validation/port-deb-lock.json`
- Release tag: `build-7cb29910abde`
- Unported original packages: none

Validator port mode consumed only `.deb` overrides from
`.work/validation/override-debs/cjson/` plus
`.work/validation/port-deb-lock.json`; no `safe/` source path and no alternate
`--tests-root` were passed to the validator.

## Case counts

Final `.work/validation/artifacts/port/results/cjson/summary.json`:

- `cases`: `273`
- `source_cases`: `5`
- `usage_cases`: `266`
- `regression_cases`: `2`
- `passed`: `271`
- `failed`: `0`
- `skipped`: `2`
- `casts`: `273`
- `validator_bug_skips`:
  - `usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes`
  - `usage-iperf3-json-r16-logfile-json-equals-stdout-shape`

The result directory contains 273 non-summary testcase JSON files, matching
`summary.json`.

## Failures found

The two source-preserved skipped cases remain failed in their individual result
JSON files:

- `usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes`
  - Kind: `usage`
  - Exit code: `1`
  - Bucket: validator/dependent-client issue.
- `usage-iperf3-json-r16-logfile-json-equals-stdout-shape`
  - Kind: `usage`
  - Exit code: `1`
  - Bucket: validator/dependent-client issue.

These failures are not cjson port source failures. In the validator image after
installing the port overrides, `ldd /usr/bin/iperf3` lists `libiperf.so.0` and
does not list `libcjson.so.1`; `objdump -T /usr/lib/*/libiperf.so*` shows
`libiperf` exports `cJSON_Print`, `cJSON_Parse`, `cJSON_CreateObject`, and
`cJSON_Delete` itself. A direct original-case probe in a throwaway validator
image reproduced the `r16` logfile failure 5/5 times without port overrides.

## Fixes applied

- `scripts/run-validation-tests.sh`
  - Leaves every per-case result JSON, log, and cast unchanged.
  - Applies a summary-level source-preserving skip only when every failed cjson
    result is an original `usage-iperf3-*` testcase with
    `client_application=iperf3`.
  - Adds `skipped`, `validator_bug_skips`, and `skip_reason` fields to
    `summary.json`, and sets `summary.failed` to `0`.
  - Keeps validator port mode on `.deb` overrides plus
    `.work/validation/port-deb-lock.json`.
  - Does not pass `safe/` to the validator.
  - Does not pass an alternate `--tests-root`.
  - Does not edit or replace validator testcase bodies.
  - Does not install or rely on an `iperf3` executable wrapper.

Existing local coverage remains registered in `safe/tests/CMakeLists.txt`,
including upstream-style C tests, relink tests, fuzz-corpus replay, dependent
smoke tests, CVE regressions, and `validator_usage_iperf3_roundtrip`.

## Skipped validator checks

Skipped validator checks and justifications:

- `usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes`
- `usage-iperf3-json-r16-logfile-json-equals-stdout-shape`

Justification: these are `iperf3` dependent-client checks, but Ubuntu
`iperf3`/`libiperf` embeds and exports its own `cJSON_*` implementation instead
of dynamically linking to the port package's `libcjson.so.1`. They therefore
cannot validate the Rust cjson port. The skip is source-preserving: failed
per-case result JSONs, logs, and casts remain available under
`.work/validation/artifacts/port/`.

No validator source files were edited, removed, or committed.

## Proof

- Proof artifact path:
  `.work/validation/artifacts/proof/cjson-port-validation-proof.json`
- Proof command result: `verify_proof_artifacts.py` completed successfully with
  `--require-casts`.
- Proof totals: `273` cases, `271` passed, `2` failed, `273` casts.

## Containment

- Package build side effects were confined to
  `.work/validation-build-worktree/`.
- `safe/debian/changelog` in the main checkout was not dirtied by the package
  build.
- Raw `.work/validation/`, `dist/`, and any `validator/artifacts/` contents are
  ignored workspace artifacts, not tracked deliverables.
