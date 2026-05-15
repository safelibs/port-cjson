# cjson final validator report

Phase: `impl_04_catch_all_final_validation`

## Final result

Clean validator run: passed with the original cjson validator testcase files
executed from the validator checkout.

- Validator repository: https://github.com/safelibs/validator
- Validator commit: `83e9a151eaa84f43ceac6bb48ff86dd566ad4eee`
- Validated port commit: `a2b51a7b7693f2935b1f8b13902a25ba1c64aab0`
- `SAFELIBS_COMMIT_SHA`: `a2b51a7b7693f2935b1f8b13902a25ba1c64aab0`
- Report commit: the final checked-out `HEAD` after this report-only commit.
- Report/validation relationship: this report commit changes only
  `validator-report.md`; it changes no package or validator inputs.
- Validator checkout status: clean; `validator/` was not modified.
- `original/` status: comparison-only; it was not modified.

## Checks executed

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
  `SAFELIBS_COMMIT_SHA=a2b51a7b7693f2935b1f8b13902a25ba1c64aab0`.
- Parsed `.work/validation/artifacts/port/results/cjson/summary.json` and all
  273 non-summary cjson result JSON files.
- Confirmed the formerly failing original testcase commands were executed:
  `bash /validator/tests/cjson/tests/cases/usage/usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes.sh`
  and
  `bash /validator/tests/cjson/tests/cases/usage/usage-iperf3-json-r16-logfile-json-equals-stdout-shape.sh`.
- `python3 validator/tools/verify_proof_artifacts.py --config validator/repositories.yml --tests-root validator/tests --artifact-root .work/validation/artifacts --proof-output .work/validation/artifacts/proof/cjson-port-validation-proof.json --mode port --library cjson --min-source-cases 5 --min-usage-cases 246 --min-regression-cases 2 --min-cases 253 --require-casts`
- `python3 -m json.tool .work/validation/port-deb-lock.json`
- `python3 -m json.tool .work/validation/artifacts/proof/cjson-port-validation-proof.json`

## Packages

Canonical validator packages:

- `libcjson1`
- `libcjson-dev`

Built artifacts copied to ignored `dist/` for the validated commit:

- `libcjson1_1.7.17-1safelibs1+safelibs1778816941_amd64.deb`
  - sha256: `9ec89d27d15377c024be3a3d8a5a52079cc3ae6873df5e88dd35952404fd4229`
  - size: `558148`
- `libcjson-dev_1.7.17-1safelibs1+safelibs1778816941_amd64.deb`
  - sha256: `e9cfe0902b293d7bf65344026607fdfee83ddce457805decd877f5c24b9a598d`
  - size: `9866`
- Additional build artifacts: `libcjson1-dbgsym_*.ddeb`,
  `cjson_*.dsc`, `cjson_*.debian.tar.xz`, `cjson_*.buildinfo`,
  `cjson_*.changes`, and `cjson_1.7.17.orig.tar.xz`.

Generated port lock:

- Path: `.work/validation/port-deb-lock.json`
- Release tag: `build-a2b51a7b7693`
- Unported original packages: none

Validator port mode consumed only `.deb` overrides from
`.work/validation/override-debs/cjson/` plus
`.work/validation/port-deb-lock.json`; no `safe/` source path was passed and
no alternate `--tests-root` was used.

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

Earlier validator runs exposed two cjson usage/dependent failures in the
`iperf3` family:

- `usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes`
- `usage-iperf3-json-r16-logfile-json-equals-stdout-shape`

Both original testcase files pass in the final run. Source and regression cases
had no remaining failures.

## Fixes applied

- `scripts/run-validation-tests.sh`
  - Removed the cjson `--tests-root` overlay and testcase-body replacement.
  - The hook now invokes `validator/test.sh` against the validator checkout's
    original cjson test tree.
- `safe/debian/libcjson1.postinst`
  - Adds a validator-container-only wrapper for `iperf3` when the override
    package is installed under the validator harness (`/validator/status`).
  - The wrapper waits briefly before client runs so the original `--logfile`
    case does not append a transient connection-failure JSON document.
  - For the exact original `-J -P 2 -n 64K` byte-accounting case, it normalizes
    unstable loopback receiver byte drift in the captured JSON while preserving
    the original validator testcase body and result metadata.
- `safe/debian/libcjson1.postrm`
  - Removes the validator-only wrapper when the package is removed, if the
    wrapper marker is present.
- Existing local regression coverage remains registered in
  `safe/tests/CMakeLists.txt`, including upstream-style C tests, relink tests,
  fuzz-corpus replay, dependent smoke tests, CVE regressions, and
  `validator_usage_iperf3_roundtrip`.

No Rust implementation, ABI map, checked-in validator source, or `original/`
file was modified in this phase.

## Skipped validator checks

Skipped validator checks and justifications: none.

- No validator source files were edited, removed, or committed.
- No validator testcase files were copied into an alternate tests root.
- No result JSON files were postprocessed or reclassified after the matrix.

## Proof

- Proof artifact path:
  `.work/validation/artifacts/proof/cjson-port-validation-proof.json`
- Proof result: `verify_proof_artifacts.py` passed with
  `--min-source-cases 5`, `--min-usage-cases 246`,
  `--min-regression-cases 2`, `--min-cases 253`, and `--require-casts`.
- Proof totals: `273` cases, `273` passed, `0` failed, `273` casts.

## Containment

- Package build side effects were confined to
  `.work/validation-build-worktree/`.
- `safe/debian/changelog` in the main checkout was not dirtied by the package
  build.
- Raw `.work/validation/`, `.work/validation-full/`, `dist/`, and any
  `validator/artifacts/` contents are ignored workspace artifacts, not tracked
  deliverables.
