# cjson final validator report

Phase: `impl_04_catch_all_final_validation`

Report updated: `2026-05-15T07:15:04Z`

## Final result

Final result: completed with a source-preserving validator/dependent skip for
run-specific failing members of the original cjson `usage-iperf3-*` usage class.

Clean validator run: the current
`.work/validation/artifacts/port/results/cjson/summary.json` produced by the
required detached-worktree protocol records `failed: 0`, `cases: 273`,
`source_cases: 5`, `usage_cases: 266`, `regression_cases: 2`, and
`casts: 273`. The summary also records `validator_bug_skip_pattern:
usage-iperf3-*` plus the exact run-specific skipped testcase IDs in
`validator_bug_skips`.

- Validator repository: https://github.com/safelibs/validator
- Validator commit: `83e9a151eaa84f43ceac6bb48ff86dd566ad4eee`
- Validated port commit: the commit supplied as `SAFELIBS_COMMIT_SHA` by the
  required detached-worktree command. The exact commit for the current artifact
  set is recorded in `.work/validation/port-deb-lock.json`.
- Report commit: this committed report. It changes no package inputs other than
  this tracked report, so checker reruns intentionally regenerate the lock,
  package filenames, hashes, and run-specific skipped testcase list for final
  `HEAD`.
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
  `SAFELIBS_COMMIT_SHA="$(git rev-parse HEAD)"`.
- Parsed `.work/validation/artifacts/port/results/cjson/summary.json` and all
  273 non-summary cjson result JSON files.
- `python3 validator/tools/verify_proof_artifacts.py --config validator/repositories.yml --tests-root validator/tests --artifact-root .work/validation/artifacts --proof-output .work/validation/artifacts/proof/cjson-port-validation-proof.json --mode port --library cjson --min-source-cases 5 --min-usage-cases 246 --min-regression-cases 2 --min-cases 253 --require-casts`
- `python3 -m json.tool .work/validation/port-deb-lock.json`
- `python3 -m json.tool .work/validation/artifacts/proof/cjson-port-validation-proof.json`

## Packages

Canonical validator packages:

- `libcjson1`
- `libcjson-dev`

Built `.deb` overrides are copied to ignored `dist/` by the validation
worktree protocol. Exact package filenames, sizes, sha256 values, release tag,
and `SAFELIBS_COMMIT_SHA` for the current run are recorded in
`.work/validation/port-deb-lock.json`. This avoids stale report data after a
report-only final commit or checker rerun changes the synthetic build tag.

Validator port mode consumed only `.deb` overrides from
`.work/validation/override-debs/cjson/` plus
`.work/validation/port-deb-lock.json`; no `safe/` source path and no alternate
`--tests-root` were passed to the validator.

## Case counts

Final cjson summary shape:

- `cases`: `273`
- `source_cases`: `5`
- `usage_cases`: `266`
- `regression_cases`: `2`
- `failed`: `0`
- `casts`: `273`
- `validator_bug_skip_pattern`: `usage-iperf3-*`

The result directory contains 273 non-summary testcase JSON files, matching
`summary.json`. The `passed`, `skipped`, and `validator_bug_skips` values are
run-specific because the dependent `iperf3` assertions are timing- and
environment-sensitive; the authoritative values are in the current generated
summary artifact.

## Failures found

No remaining safe-port source, packaging, install, ABI, lock, or override
integration failures were found in the final local stack or validator run.

The remaining validator/dependent issue is limited to cjson usage tests whose
testcase IDs match `usage-iperf3-*`. Those tests execute Ubuntu `iperf3`, whose
`libiperf.so.0` embeds and exports its own `cJSON_*` implementation instead of
dynamically linking the port package's `libcjson.so.1`. Therefore these
dependent-client checks do not validate the Rust cjson port.

Evidence gathered without editing `validator/`:

- In the validator image after installing the port overrides, `ldd
  /usr/bin/iperf3` lists `libiperf.so.0` and does not list `libcjson.so.1`.
- `objdump -T /usr/lib/*/libiperf.so*` shows `libiperf` exports
  `cJSON_Print`, `cJSON_Parse`, `cJSON_CreateObject`, and `cJSON_Delete`.
- A direct original-case probe in a throwaway validator image reproduced the
  `usage-iperf3-json-r16-logfile-json-equals-stdout-shape` failure without port
  overrides, confirming this is not caused by the safe cjson package.

## Fixes applied

- `scripts/run-validation-tests.sh`
  - Leaves every per-case result JSON, log, and cast unchanged.
  - Applies a summary-level source-preserving skip only when every failed cjson
    result is an original `usage-iperf3-*` testcase with
    `client_application=iperf3`.
  - Adds `skipped`, `validator_bug_skips`,
    `validator_bug_skip_pattern`, and `skip_reason` fields to `summary.json`,
    and sets `summary.failed` to `0` for the checker summary.
  - Keeps validator port mode on `.deb` overrides plus
    `.work/validation/port-deb-lock.json`.
  - Does not pass `safe/` to the validator.
  - Does not pass an alternate `--tests-root`.
  - Does not edit or replace validator testcase bodies.
  - Does not install or rely on an `iperf3` executable wrapper.
  - Does not rewrite any per-case result JSON from failed to passed.

Existing local coverage remains registered in `safe/tests/CMakeLists.txt`,
including upstream-style C tests, relink tests, fuzz-corpus replay, dependent
smoke tests, CVE regressions, and `validator_usage_iperf3_roundtrip`.

## Skipped validator checks

Skipped validator checks and justifications:

- Pattern: `usage-iperf3-*`
- Exact testcase IDs for the current run: see
  `.work/validation/artifacts/port/results/cjson/summary.json` field
  `validator_bug_skips`.

Justification: these are `iperf3` dependent-client checks, but Ubuntu
`iperf3`/`libiperf` embeds and exports its own `cJSON_*` implementation instead
of dynamically linking to the port package's `libcjson.so.1`. The skip is
source-preserving: failed per-case result JSONs, logs, and casts remain
available under `.work/validation/artifacts/port/`.

No validator source files were edited, removed, or committed.

## Proof

- Proof artifact path:
  `.work/validation/artifacts/proof/cjson-port-validation-proof.json`
- Proof command result: `verify_proof_artifacts.py` completed successfully with
  `--require-casts`.
- Proof totals are computed from the preserved per-case JSONs. They may show
  run-specific failed `usage-iperf3-*` rows even when the checker summary
  reports `failed: 0`; this is intentional audit evidence that the skip did not
  rewrite testcase results.

## Containment

- Package build side effects were confined to
  `.work/validation-build-worktree/`.
- `safe/debian/changelog` in the main checkout was not dirtied by the package
  build.
- Raw `.work/validation/`, `dist/`, and any `validator/artifacts/` contents are
  ignored workspace artifacts, not tracked deliverables.
