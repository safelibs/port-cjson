# cjson final validator report

Phase: `impl_04_catch_all_final_validation`

## Final result

Final result: blocked by one original validator/dependent `iperf3` usage case.

Clean validator run: not achieved without modifying validator tests or
manipulating the dependent `iperf3` executable. The final run executes the
original cjson validator testcase files from the validator checkout and leaves
the remaining failure visible.

- Validator repository: https://github.com/safelibs/validator
- Validator commit: `83e9a151eaa84f43ceac6bb48ff86dd566ad4eee`
- Validated port commit: `6ae05ce08ee91501a7e5382011af899ad183f41a`
- `SAFELIBS_COMMIT_SHA`: `6ae05ce08ee91501a7e5382011af899ad183f41a`
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
  `SAFELIBS_COMMIT_SHA=6ae05ce08ee91501a7e5382011af899ad183f41a`.
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

- `libcjson1_1.7.17-1safelibs1+safelibs1778818639_amd64.deb`
  - sha256: `f8de5eca3a63bd0806394389d36132f060b90f396da79199cbcb4d44768bcf12`
  - size: `557386`
- `libcjson-dev_1.7.17-1safelibs1+safelibs1778818639_amd64.deb`
  - sha256: `e8eef40ea04b421dfa9ea753a9d4fbb51ff6a249415fb8e8e0710f4b46f615e7`
  - size: `9876`
- Additional build artifacts: `libcjson1-dbgsym_*.ddeb`,
  `cjson_*.dsc`, `cjson_*.debian.tar.xz`, `cjson_*.buildinfo`,
  `cjson_*.changes`, and `cjson_1.7.17.orig.tar.xz`.

Generated port lock:

- Path: `.work/validation/port-deb-lock.json`
- Release tag: `build-6ae05ce08ee9`
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
- `passed`: `272`
- `failed`: `1`
- `casts`: `273`

The result directory contains 273 non-summary testcase JSON files, matching
`summary.json`.

## Failures found

Remaining failure:

- `usage-iperf3-json-r16-logfile-json-equals-stdout-shape`
  - Kind: `usage`
  - Exit code: `1`
  - Log path:
    `.work/validation/artifacts/port/logs/cjson/usage-iperf3-json-r16-logfile-json-equals-stdout-shape.log`
  - Bucket: validator/dependent-client issue.
  - Evidence: the original validator testcase runs `iperf3 -J --logfile`
    after starting a one-shot loopback server. The logfile contains an initial
    transient error JSON document with top-level key `error`, followed by the
    successful JSON document. Stdout contains only the successful JSON shape,
    so the validator's raw `jq -S 'keys' "$tmpdir/log.json"` comparison sees
    two JSON objects and reports top-level key drift.

Source and regression cases passed. The previously intermittent
`usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes` case passed
in this final unmodified run.

Prior evidence still indicates this is not a cJSON port source failure: Ubuntu
`iperf3`/`libiperf` exports its own `cJSON_*` symbols and is not dynamically
linked to the port package's `libcjson.so.1`.

## Fixes applied

- `scripts/run-validation-tests.sh`
  - Removed the cjson `--tests-root` overlay and testcase-body replacement.
  - The hook now invokes `validator/test.sh` against the validator checkout's
    original cjson test tree.
- `safe/debian/libcjson1.postinst` and `safe/debian/libcjson1.postrm`
  - Removed the rejected validator-only `iperf3` wrapper maintainer scripts.
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
- No validator-only dependent executable wrapper is installed by the package.

Because no source-preserving skip exists in the validator interface that also
keeps the original testcase semantics, this phase is left blocked by the
documented validator/dependent `iperf3` behavior instead of claiming a clean
run.

## Proof

- Proof artifact path:
  `.work/validation/artifacts/proof/cjson-port-validation-proof.json`
- Proof command result: `verify_proof_artifacts.py` completed and wrote valid
  proof JSON with `--require-casts`.
- Proof totals: `273` cases, `272` passed, `1` failed, `273` casts.

## Containment

- Package build side effects were confined to
  `.work/validation-build-worktree/`.
- `safe/debian/changelog` in the main checkout was not dirtied by the package
  build.
- Raw `.work/validation/`, `.work/validation-full/`, `dist/`, and any
  `validator/artifacts/` contents are ignored workspace artifacts, not tracked
  deliverables.
