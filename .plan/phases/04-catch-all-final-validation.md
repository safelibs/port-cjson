# Catch-All Remaining Fixes And Final Report

## Phase Name
Catch-All Remaining Fixes And Final Report

## Implement Phase ID
`impl_04_catch_all_final_validation`

## Preexisting Inputs
- Commits and `validator-report.md` updates from Phases 1-3.
- `validator/` checkout, already updated and recorded.
- `original/` as comparison source only; do not edit or regenerate upstream code.
- Existing and newly added regression tests.
- Existing `tests/`, `tests/upstream/`, and `tests/port/` artifacts from the port template, including any checked-in upstream tests. Consume these checked-in tests in place; do not rediscover or regenerate them.
- Checked-in `safe/tests/CMakeLists.txt` registrations for upstream-style C tests, relink tests, fuzz-corpus compatibility tests, dependent smoke tests, and regressions.
- Safe workspace/build context from prior phases: two Rust member crates, `cdylib` and `staticlib` outputs, CMake wrapping of Rust static archives into ABI-compatible shared libraries, Debian dependencies, and `dpkg-buildpackage` rooted in `safe/`.
- Current `scripts/run-validation-tests.sh`.
- Current `scripts/lib/build_port_lock.py`.
- Current `scripts/build-debs.sh` and `scripts/lib/build-deb-common.sh`; package builds must remain confined to `.work/validation-build-worktree/` because `stamp_safelibs_changelog` rewrites tracked Debian metadata.
- `dist/` artifacts from previous phases if present.
- `.work/validation/` artifacts from previous phases if present.

## New Outputs
- Any final safe-port, packaging, or validator-hook fixes needed after Phases 2-3.
- `validator-report.md` rewritten into final form, including validator commit, checks executed, failures found, fixes applied, skipped checks if any, and final clean run/proof status.
- Fresh `.work/validation/artifacts/proof/cjson-port-validation-proof.json`.
- Raw validator run artifacts may also exist under ignored `validator/artifacts/`; they are allowed as workspace artifacts but must not replace tracked report conclusions.
- One or more git commits for this phase, ending with a committed final report.

## File Changes
- `validator-report.md` is mandatory.
- `.gitignore` should already ignore `/validator/`; touch it only if the Phase 1 contract was missed.
- Candidate catch-all script files if the validator interface changed:
  - `scripts/build-debs.sh`
  - `scripts/lib/build-deb-common.sh`
  - `scripts/run-validation-tests.sh`
  - `scripts/lib/build_port_lock.py`
  - `tests/test_build_port_lock.py`
- Candidate packaging files if package metadata caused validator failures:
  - `packaging/package.env`
  - `safe/debian/*`
  - `safe/CMakeLists.txt`
  - `safe/library_config/*`
- Candidate packaging files include, specifically, `safe/debian/control`, `safe/debian/rules`, `safe/debian/libcjson-dev.install`, `safe/debian/libcjson1.install`, `safe/debian/libcjson1.symbols`, `safe/library_config/libcjson.pc.in`, `safe/library_config/libcjson_utils.pc.in`, `safe/library_config/cJSONConfig.cmake.in`, and `safe/library_config/cJSONConfigVersion.cmake.in`.
- Candidate ABI files:
  - `safe/abi/libcjson.map`
  - `safe/abi/libcjson_utils.map`
  Touch them only for a proven exported symbol contract issue and keep `safe/scripts/check-abi.sh` passing.
- Candidate safe implementation and test files only for failures not covered by Phases 2-3:
  - `safe/crates/libcjson/src/abi.rs`
  - `safe/crates/libcjson/src/hooks.rs`
  - `safe/crates/libcjson/src/parse.rs`
  - `safe/crates/libcjson/src/number.rs`
  - `safe/crates/libcjson/src/string.rs`
  - `safe/crates/libcjson/src/print.rs`
  - `safe/crates/libcjson/src/minify.rs`
  - `safe/crates/libcjson/src/list.rs`
  - `safe/crates/libcjson/src/mutate.rs`
  - `safe/crates/libcjson/src/create.rs`
  - `safe/crates/libcjson/src/delete.rs`
  - `safe/crates/libcjson/src/duplicate.rs`
  - `safe/crates/libcjson/src/compare.rs`
  - `safe/crates/libcjson/src/typecheck.rs`
  - `safe/crates/libcjson/src/error.rs`
  - `safe/crates/libcjson_utils/src/lib.rs`
  - `safe/crates/libcjson_utils/src/pointer.rs`
  - `safe/crates/libcjson_utils/src/patch.rs`
  - `safe/crates/libcjson_utils/src/merge_patch.rs`
  - `safe/crates/libcjson_utils/src/sort.rs`
  - `safe/tests/CMakeLists.txt`
  - `safe/tests/regressions/*.c`
- Workspace and crate manifests are catch-all build-system candidates only when required by a final validator or local build failure:
  - `safe/Cargo.toml`
  - `safe/crates/libcjson/Cargo.toml`
  - `safe/crates/libcjson_utils/Cargo.toml`
- `original/` remains comparison-only upstream source and must not be modified.
- `validator/` remains an external checkout and must not be modified or committed.
- Do not weaken or remove checked-in upstream-style tests, relink tests, fuzz-corpus compatibility tests, existing regressions, ABI maps, Debian packaging metadata, package metadata, or checked-in `tests/` artifacts to produce a final pass.
- Do not commit raw artifacts from `.work/validation/`, `dist/`, logs, Debian package files, or `validator/artifacts/`; durable conclusions and skipped-check justifications belong in `validator-report.md`.

## Implementation Details
1. Start from the current report and validator artifacts. Re-run the full local stack from a clean main-checkout build state so stale `.work/validation` or `dist/` contents cannot mask a problem.
2. Preserve the established build and validation boundary while doing final fixes:
   - `safe/` remains a two-crate Rust workspace whose member manifests build `cdylib` and `staticlib` artifacts.
   - CMake continues to build `safe-libcjson` and `safe-libcjson-utils` and wrap Rust static archives into ABI-compatible shared libraries.
   - Debian package builds continue to use the declared dependencies from `safe/debian/control` and `dpkg-buildpackage` rooted in `safe/`.
   - `safe/tests/CMakeLists.txt` continues to register the checked-in upstream-style C tests, relink tests, fuzz-corpus compatibility tests, dependent smoke tests, and regressions.
3. The validator `port` mode consumes `.deb` overrides and a generated port lock. It does not need, and should not be given, a path to `safe/`; source files under `safe/` are only the implementation and local-test location.
4. Before package or validator runs, commit any final source, test, packaging, script, and report changes that should be validated. The committed SHA is the validation candidate and must be used as `SAFELIBS_COMMIT_SHA`.
5. Run package and validator steps only through this validation worktree protocol:

   ```sh
   bash -lc '
   set -euo pipefail
   main_root="$PWD"
   validated_sha="$(git rev-parse HEAD)"
   validation_tree="$main_root/.work/validation-build-worktree"
   rm -rf "$main_root/dist" "$main_root/.work/validation" "$validation_tree"
   git worktree prune
   cleanup_validation_tree() {
     git worktree remove --force "$validation_tree" >/dev/null 2>&1 || rm -rf "$validation_tree"
   }
   trap cleanup_validation_tree EXIT
   git worktree add --detach "$validation_tree" "$validated_sha"
   validation_status=0
   (
     cd "$validation_tree"
     SAFELIBS_COMMIT_SHA="$validated_sha" bash scripts/build-debs.sh
     SAFELIBS_VALIDATOR_DIR="$main_root/validator" \
     SAFELIBS_RECORD_CASTS=1 \
     SAFELIBS_COMMIT_SHA="$validated_sha" \
     bash scripts/run-validation-tests.sh
   ) || validation_status=$?
   mkdir -p "$main_root/.work"
   rm -rf "$main_root/dist" "$main_root/.work/validation"
   if [ -d "$validation_tree/dist" ]; then cp -a "$validation_tree/dist" "$main_root/dist"; fi
   if [ -d "$validation_tree/.work/validation" ]; then cp -a "$validation_tree/.work/validation" "$main_root/.work/validation"; fi
   exit "$validation_status"
   '
   ```

6. After the validator hook returns, parse `summary.json` and every non-summary result JSON before deciding whether the matrix is clean.
7. If any result has `status` other than `passed`, classify it by `kind`, `testcase_id`, `exit_code`, and `log_path` into one of these buckets:
   - Missed source/regression root cause.
   - Missed usage/dependent root cause.
   - Packaging/install/ABI issue.
   - Validator lock/override integration issue.
   - Validator bug.
8. For missed safe-port failures, add or extend a minimal regression test under `safe/tests/regressions/`, update `safe/tests/CMakeLists.txt`, fix the underlying Rust code, and rerun local plus validator checks without removing existing upstream-style, relink, fuzz-corpus, dependent smoke, or regression tests.
9. For packaging or ABI failures, fix the actual package contract. Keep `scripts/lib/build_port_lock.py` aligned with validator's `port-deb-lock` schema and update `tests/test_build_port_lock.py` with any schema changes.
10. If the validator itself is wrong, do not modify `validator/`. Document the exact test id, validator commit, original-mode evidence if applicable, port-mode evidence, the reason the check is being skipped, and whether a source-preserving skip or proof of remaining cases was possible. If no source-preserving skip exists, leave final status blocked by validator bug instead of claiming a clean run.
11. After copied ignored artifacts are in place, inspect the main checkout for tracked dirt. If package validation dirtied a tracked file such as `safe/debian/changelog`, fix the worktree protocol or hook containment. Do not use `git restore`, `git checkout --`, or other destructive cleanup in the main checkout to hide build side effects.
12. Finalize `validator-report.md` with:
   - Validator URL and exact commit.
   - Port commits, including the final `Validated port commit` used as `SAFELIBS_COMMIT_SHA` and the report commit if different.
   - All commands run.
   - Canonical packages and built debs.
   - cjson case counts by kind.
   - Baseline failures.
   - Fixes applied, with file paths and test names.
   - Skipped checks and justifications, if any.
   - Final validator matrix status from `summary.json`, including `passed`, `failed`, `source_cases`, `usage_cases`, `regression_cases`, and total `cases`.
   - Proof artifact path and proof result.
   - Statement that `validator/` was not modified.
   - Statement that any raw `.work/validation/` or `validator/artifacts/` contents are ignored workspace artifacts, not tracked deliverables.
13. Commit all final changes before yielding. If no changes are needed after rerunning, update the report timestamp/status or make an explicit empty commit. A report-only final commit after validation is acceptable only if it changes no package inputs and clearly names the validated commit.

## Verification Phases

### `check_04_final_validator_software_tester`
- `phase_id`: `check_04_final_validator_software_tester`
- `type`: `check`
- `bounce_target`: `impl_04_catch_all_final_validation`
- `purpose`: run the complete local and validator verification stack from a clean build state and verify proof artifacts.
- `commands`:

```sh
git show --stat --oneline HEAD
git status --short
git -C validator status --short
git -C validator rev-parse HEAD
bash scripts/check-layout.sh
python3 -m unittest tests.test_build_port_lock
rg -n 'relink|fuzz|dependents|regressions|add_safe_unity' safe/tests/CMakeLists.txt
(cd safe && cargo test --workspace)
tmp_build="$(mktemp -d)"; cmake -S safe -B "$tmp_build" -G Ninja -DENABLE_CJSON_UTILS=ON -DENABLE_CJSON_TEST=ON
cmake --build "$tmp_build"
ctest --test-dir "$tmp_build" --output-on-failure
safe/scripts/check-build-contract.sh
safe/scripts/check-abi.sh "$tmp_build"
bash -lc '
set -euo pipefail
main_root="$PWD"
validated_sha="$(git rev-parse HEAD)"
validation_tree="$main_root/.work/validation-build-worktree"
rm -rf "$main_root/dist" "$main_root/.work/validation" "$validation_tree"
git worktree prune
cleanup_validation_tree() {
  git worktree remove --force "$validation_tree" >/dev/null 2>&1 || rm -rf "$validation_tree"
}
trap cleanup_validation_tree EXIT
git worktree add --detach "$validation_tree" "$validated_sha"
validation_status=0
(
  cd "$validation_tree"
  SAFELIBS_COMMIT_SHA="$validated_sha" bash scripts/build-debs.sh
  SAFELIBS_VALIDATOR_DIR="$main_root/validator" \
  SAFELIBS_RECORD_CASTS=1 \
  SAFELIBS_COMMIT_SHA="$validated_sha" \
  bash scripts/run-validation-tests.sh
) || validation_status=$?
mkdir -p "$main_root/.work"
rm -rf "$main_root/dist" "$main_root/.work/validation"
if [ -d "$validation_tree/dist" ]; then cp -a "$validation_tree/dist" "$main_root/dist"; fi
if [ -d "$validation_tree/.work/validation" ]; then cp -a "$validation_tree/.work/validation" "$main_root/.work/validation"; fi
exit "$validation_status"
'
python3 -c 'import json; from pathlib import Path; p=Path(".work/validation/artifacts/port/results/cjson"); s=json.load(open(p/"summary.json")); cases=[f for f in p.glob("*.json") if f.name!="summary.json"]; assert len(cases) == s["cases"], (len(cases), s); assert s["failed"] == 0 and s["source_cases"] >= 5 and s["usage_cases"] >= 246 and s["regression_cases"] >= 2 and s["cases"] >= 253, s; print(s)'
python3 validator/tools/verify_proof_artifacts.py --config validator/repositories.yml --tests-root validator/tests --artifact-root .work/validation/artifacts --proof-output .work/validation/artifacts/proof/cjson-port-validation-proof.json --mode port --library cjson --min-source-cases 5 --min-usage-cases 246 --min-regression-cases 2 --min-cases 253 --require-casts
python3 -m json.tool .work/validation/port-deb-lock.json >/dev/null
python3 -m json.tool .work/validation/artifacts/proof/cjson-port-validation-proof.json >/dev/null
grep -E 'Final result|Clean validator run|Validator commit|Checks executed|Failures found|Fixes applied' validator-report.md
```

### `check_04_final_senior_tester`
- `phase_id`: `check_04_final_senior_tester`
- `type`: `check`
- `bounce_target`: `impl_04_catch_all_final_validation`
- `purpose`: final architectural review for linear history, clean validator run, report completeness, and absence of validator-suite modifications.
- `commands`:

```sh
git log --oneline --decorate -8
git show --name-status --format=fuller HEAD
git status --short --ignored
git -C validator status --short
git -C validator rev-parse HEAD
git diff -- validator
grep -E 'Final result|Validator commit|Checks executed|Failures found|Fixes applied|Skipped validator checks|Clean validator run' validator-report.md
python3 -c 'import json; from pathlib import Path; p=Path(".work/validation/artifacts/port/results/cjson"); s=json.load(open(p/"summary.json")); cases=[f for f in p.glob("*.json") if f.name!="summary.json"]; assert len(cases) == s["cases"] and s["failed"] == 0, (len(cases), s); print(s)'
python3 -m json.tool .work/validation/port-deb-lock.json >/dev/null
python3 -m json.tool .work/validation/artifacts/proof/cjson-port-validation-proof.json >/dev/null
```

## Success Criteria
- The complete local stack passes: layout, unit lock test, cargo tests, CMake build, CTest, ABI check, and build contract check.
- Existing checked-in upstream-style tests, relink tests, fuzz-corpus compatibility tests, dependent smoke tests, and regressions remain registered in `safe/tests/CMakeLists.txt`.
- `scripts/build-debs.sh`, run inside `.work/validation-build-worktree/`, produces canonical `.deb` artifacts copied back to the main checkout's ignored `dist/`.
- The validation worktree protocol runs `scripts/run-validation-tests.sh` against `SAFELIBS_VALIDATOR_DIR=$PWD/validator` from the main checkout's absolute validator path.
- Validator `port` mode consumes `.deb` overrides and the port lock only; no `safe/` source path is passed to the validator.
- `.work/validation/artifacts/port/results/cjson/summary.json` records zero failed cjson cases unless a validator bug is proven and documented as an explicit blocker.
- Validator proof verification passes with cjson thresholds of at least `5 source`, `246 usage`, `2 regression`, `253 total`, and `--require-casts` when casts were recorded.
- `validator-report.md` is complete and reflects the actual final commands and results.
- No validator source changes are present.
- The main checkout has no tracked dirt from package building, especially no `safe/debian/changelog` modification caused by `scripts/build-debs.sh`.
- A clean main checkout is achieved by preventing package side effects outside `.work/validation-build-worktree/`; the phase must not use `git restore`, `git checkout --`, or destructive cleanup in the main checkout.

## Git Commit Requirement
The implementer must commit all work for this phase to git before yielding to the verifier phases. If no final source, packaging, or script changes are needed, the implementer must still commit a final `validator-report.md` update or make an explicit empty phase-boundary commit.
