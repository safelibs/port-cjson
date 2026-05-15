# cjson final validator report

Phase: `impl_04_catch_all_final_validation`

Report updated: `2026-05-15T06:20:57Z`

## Final result

Final result: blocked by two original validator/dependent `iperf3` usage cases.

Clean validator run: not achieved without changing validator tests, wrapping or
altering the dependent `iperf3` executable, or post-processing validator result
JSON. The final validation artifacts are left in the raw failed state produced
by the original validator checkout.

- Validator repository: https://github.com/safelibs/validator
- Validator commit: `83e9a151eaa84f43ceac6bb48ff86dd566ad4eee`
- Validated port commit: `4fd5b83c19292248c900aaee3c315485b37796c9`
- `SAFELIBS_COMMIT_SHA`: `4fd5b83c19292248c900aaee3c315485b37796c9`
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
  `SAFELIBS_COMMIT_SHA=4fd5b83c19292248c900aaee3c315485b37796c9`.
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

- `libcjson1_1.7.17-1safelibs1+safelibs1778825447_amd64.deb`
  - sha256: `638da5a7ac909795d0963fd68593c8851e65a82ccafefe22379ede4937cea856`
  - size: `557238`
- `libcjson-dev_1.7.17-1safelibs1+safelibs1778825447_amd64.deb`
  - sha256: `9b1e98a63198c832c9f67e383f05dfac1e0f004e99c561830ff43fde71666b69`
  - size: `9882`
- Additional build artifacts: `libcjson1-dbgsym_*.ddeb`,
  `cjson_*.dsc`, `cjson_*.debian.tar.xz`, `cjson_*.buildinfo`,
  `cjson_*.changes`, and `cjson_1.7.17.orig.tar.xz`.

Generated port lock:

- Path: `.work/validation/port-deb-lock.json`
- Release tag: `build-4fd5b83c1929`
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
- `failed`: `2`
- `casts`: `273`

The result directory contains 273 non-summary testcase JSON files, matching
`summary.json`.

## Failures found

Remaining failures:

- `usage-iperf3-json-blksize-field`
  - Kind: `usage`
  - Exit code: `134`
  - Log path:
    `.work/validation/artifacts/port/logs/cjson/usage-iperf3-json-blksize-field.log`
  - Bucket: validator/dependent-client issue.
  - Evidence: the validator log shows the `iperf3 -s -1` server process aborting
    inside the dependent `iperf3` testcase.
- `usage-iperf3-json-r16-logfile-json-equals-stdout-shape`
  - Kind: `usage`
  - Exit code: `1`
  - Log path:
    `.work/validation/artifacts/port/logs/cjson/usage-iperf3-json-r16-logfile-json-equals-stdout-shape.log`
  - Bucket: validator/dependent-client issue.
  - Evidence: the validator testcase compares stdout JSON keys with a logfile
    that contains an initial connection-error JSON object followed by the
    successful JSON object.

These failures are not cjson port source failures. In the validator image after
installing the port overrides, `ldd /usr/bin/iperf3` lists `libiperf.so.0` and
does not list `libcjson.so.1`; `objdump -T /usr/lib/*/libiperf.so*` shows
`libiperf` exports `cJSON_Print`, `cJSON_Parse`, `cJSON_CreateObject`, and
`cJSON_Delete` itself. A direct original-case probe in a throwaway validator
image reproduced the `r16` logfile failure 10/10 times.

## Fixes applied

- `scripts/run-validation-tests.sh`
  - Removed result JSON rewriting and summary rewriting.
  - Leaves failed validator testcase results unchanged.
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

Skipped validator checks and justifications: none.

No legitimate source-preserving skip is available in the current validator
interface. `run_matrix.py` has no per-case skip flag, and
`verify_proof_artifacts.py --tests-root validator/tests` requires an exact
result JSON for every testcase in the original manifest. The proof schema
accepts only `passed` and `failed`, so encoding a skip would require mutating
failed results or changing the test suite. This phase therefore remains blocked
instead of claiming a clean run.

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
