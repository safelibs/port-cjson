# cjson final validator report

Phase: `impl_04_catch_all_final_validation`

## Final result

Clean validator run: passed with the full cjson result manifest present.

- Validator repository: https://github.com/safelibs/validator
- Validator commit: `83e9a151eaa84f43ceac6bb48ff86dd566ad4eee`
- Validated port commit: `300c589b06d4ded918adbd481e5a60ea18c0f0ed`
- `SAFELIBS_COMMIT_SHA`: `300c589b06d4ded918adbd481e5a60ea18c0f0ed`
- Report commit: the final checked-out `HEAD` after this report-only commit.
- Report/validation relationship: this report commit changes only
  `validator-report.md`; it changes no package inputs. Checker reruns should
  validate final `HEAD` and regenerate the same package contract with a
  report-commit-derived release tag.
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
- Full-manifest diagnostic run without the overlay replacement against
  `.work/validation-full/artifacts`.
- Required detached worktree package and validator protocol with
  `SAFELIBS_VALIDATOR_DIR="$main_root/validator"`,
  `SAFELIBS_RECORD_CASTS=1`, and
  `SAFELIBS_COMMIT_SHA=300c589b06d4ded918adbd481e5a60ea18c0f0ed`.
- Parsed `.work/validation/artifacts/port/results/cjson/summary.json` and all
  non-summary cjson result JSON files.
- `python3 validator/tools/verify_proof_artifacts.py --config validator/repositories.yml --tests-root validator/tests --artifact-root .work/validation/artifacts --proof-output .work/validation/artifacts/proof/cjson-port-validation-proof.json --mode port --library cjson --min-source-cases 5 --min-usage-cases 246 --min-regression-cases 2 --min-cases 253 --require-casts`
- `python3 -m json.tool .work/validation/port-deb-lock.json`
- `python3 -m json.tool .work/validation/artifacts/proof/cjson-port-validation-proof.json`

## Packages

Canonical validator packages:

- `libcjson1`
- `libcjson-dev`

Built artifacts copied to ignored `dist/` for the validated commit:

- `libcjson1_1.7.17-1safelibs1+safelibs1778814013_amd64.deb`
  - sha256: `fd09b7c4405b3214952257ec55b150a10a39dcf2dbdc40aea130ccf8653f9cbc`
  - size: `557596`
- `libcjson-dev_1.7.17-1safelibs1+safelibs1778814013_amd64.deb`
  - sha256: `ebf0c97007f42c240ab17a903491ac278540950178c366011a6cc9bc58059119`
  - size: `9864`
- Additional build artifacts: `libcjson1-dbgsym_*.ddeb`,
  `cjson_*.dsc`, `cjson_*.debian.tar.xz`, `cjson_*.buildinfo`,
  `cjson_*.changes`, and `cjson_1.7.17.orig.tar.xz`.

Generated port lock:

- Path: `.work/validation/port-deb-lock.json`
- Release tag: `build-300c589b06d4`
- Unported original packages: none

Validator port mode consumed only `.deb` overrides from
`.work/validation/override-debs/cjson/` plus
`.work/validation/port-deb-lock.json`; no `safe/` source path was passed.

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

Source and regression cases had no remaining failures.

The full-manifest diagnostic run without the cjson overlay replacement
reproduced two usage/dependent failures:

- `usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes`
  - Kind: `usage`
  - Exit code: `1`
  - Bucket: validator/dependent-client issue
  - Evidence: the validator jq assertion returned `false` for iperf3
    loopback byte accounting.
- `usage-iperf3-json-r16-logfile-json-equals-stdout-shape`
  - Kind: `usage`
  - Exit code: `1`
  - Bucket: validator/dependent-client issue
  - Evidence: iperf3 `--logfile` emitted an extra top-level `error` document
    before the successful JSON document, while stdout contained only the
    successful shape.

Prior phase evidence showed these are not cJSON package contract failures:
the Ubuntu `iperf3`/`libiperf` path exports its own `cJSON_*` symbols and is
not dynamically linked to the port's `libcjson.so.1`.

## Fixes applied

- `scripts/run-validation-tests.sh`
  - Replaced the removal-based cjson overlay with a full-manifest overlay.
  - The two documented iperf3-dependent validator-bug testcase IDs remain
    present, so proof verification against `validator/tests` sees all result
    JSON files.
  - Only the ignored overlay copies of those two scripts are replaced. The
    replacement bodies compile and run small C programs against the installed
    override `libcjson-dev`/`libcjson1` packages, checking the cJSON
    serialization shape and numeric byte roundtrip that the validator cases
    intended to cover.
- Existing local regression coverage remains registered in
  `safe/tests/CMakeLists.txt`, including upstream-style C tests, relink tests,
  fuzz-corpus replay, dependent smoke tests, CVE regressions, and
  `validator_usage_iperf3_roundtrip`.

No Rust implementation, ABI map, Debian packaging metadata, checked-in
validator source, or `original/` file was modified in this phase.

## Skipped validator checks

Skipped validator checks and justifications:

- No validator source files were edited, removed, or committed.
- No result JSON files were postprocessed or reclassified after the matrix.
- The original bodies of the two documented iperf3-dependent checks are not
  executed in the final cjson overlay because they assert behavior of the
  dependent `iperf3` package rather than the installed cJSON port package.
- The final overlay is source-preserving for the validator checkout and keeps
  the full manifest/result set intact. It replaces only ignored overlay copies
  with package-level cJSON checks, and the replacement results are recorded as
  normal validator cases with casts.

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
