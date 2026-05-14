# Source API And CVE Regression Validator Failures

## Phase Name
Source API And CVE Regression Validator Failures

## Implement Phase ID
`impl_02_source_regression_fixes`

## Preexisting Inputs
- Phase 1 committed baseline report and phase-boundary commit.
- `validator-report.md` baseline failure table.
- `validator/` checkout at the commit recorded in `validator-report.md`.
- `.work/validation/artifacts/port/results/cjson/*.json` and logs from Phase 1 if still present.
- `original/` as comparison source only; do not edit or regenerate upstream code.
- Existing `tests/`, `tests/upstream/`, and `tests/port/` artifacts from the port template, including any checked-in upstream tests. Consume these checked-in tests in place; do not rediscover or regenerate them.
- Safe workspace/build context from Phase 1: two Rust member crates, `cdylib` and `staticlib` outputs, CMake wrapping of Rust static archives into ABI-compatible shared libraries, Debian dependencies, and `dpkg-buildpackage` rooted in `safe/`.
- `safe/tests/regressions/number_cve_2023_26819.c`.
- `safe/tests/regressions/json_pointer_cve_2025_57052.c`.
- `safe/tests/regressions/core_hooks_smoke.c`.
- Existing regression registrations in `safe/tests/CMakeLists.txt`.
- Checked-in `safe/tests/CMakeLists.txt` registrations for upstream-style C tests, relink tests, fuzz-corpus compatibility tests, and regressions.
- Core Rust modules under `safe/crates/libcjson/src/`, including ABI layout, hooks, parse, number, string, print, minify, list/tree mutation, creation/deletion, duplicate/compare, type checking, and error pointer behavior.
- Utils Rust modules under `safe/crates/libcjson_utils/src/`, including public ABI imports, pointer, patch, merge patch, and sort behavior.
- ABI maps `safe/abi/libcjson.map` and `safe/abi/libcjson_utils.map` as compatibility constraints.

## New Outputs
- Minimal C regression tests under `safe/tests/regressions/` for failing source or regression validator cases not already covered.
- Updates to `safe/tests/CMakeLists.txt` registering any new regression tests.
- Safe-port Rust fixes under `safe/crates/libcjson/src/` or `safe/crates/libcjson_utils/src/`.
- `validator-report.md` updated with source/regression failures fixed, tests added, commands run, remaining failures, and validated commit details.
- One or more git commits for this phase, ending with committed source/regression fix results.

## File Changes
- Candidate new tests:
  - `safe/tests/regressions/validator_allocator_hooks_edge.c`
  - `safe/tests/regressions/validator_malformed_number_rejection.c`
  - `safe/tests/regressions/validator_minify_whitespace.c`
  - `safe/tests/regressions/validator_parse_print_roundtrip.c`
  - `safe/tests/regressions/validator_utils_patch_pointer.c`
  - Or focused names matching the actual failing validator test ids.
- Mandatory registration for any new tests: `safe/tests/CMakeLists.txt`.
- Candidate implementation files by failure:
  - `safe/crates/libcjson/src/abi.rs` for C ABI layout and constants if a validator failure proves an ABI layout mismatch.
  - `safe/crates/libcjson/src/hooks.rs` for allocator hook behavior.
  - `safe/crates/libcjson/src/parse.rs`, `safe/crates/libcjson/src/number.rs`, and `safe/crates/libcjson/src/error.rs` for malformed-number rejection and parse-end behavior.
  - `safe/crates/libcjson/src/string.rs` and `safe/crates/libcjson/src/print.rs` for parse/print roundtrip, escaping, preallocated print, and formatting failures.
  - `safe/crates/libcjson/src/minify.rs` for whitespace and comment minification failures.
  - `safe/crates/libcjson/src/list.rs`, `safe/crates/libcjson/src/mutate.rs`, `safe/crates/libcjson/src/create.rs`, `safe/crates/libcjson/src/delete.rs`, `safe/crates/libcjson/src/duplicate.rs`, `safe/crates/libcjson/src/compare.rs`, and `safe/crates/libcjson/src/typecheck.rs` for public API compatibility and tree ownership behavior.
  - `safe/crates/libcjson_utils/src/lib.rs` for utils public ABI and cross-library imports from core cJSON symbols.
  - `safe/crates/libcjson_utils/src/pointer.rs` and `safe/crates/libcjson_utils/src/patch.rs` for pointer and patch failures.
  - `safe/crates/libcjson_utils/src/merge_patch.rs` and `safe/crates/libcjson_utils/src/sort.rs` for merge patch or object sorting regressions.
- ABI files are compatibility constraints for this phase:
  - `safe/abi/libcjson.map`
  - `safe/abi/libcjson_utils.map`
  Touch them only when the validator failure proves the exported symbol contract is wrong, and keep `safe/scripts/check-abi.sh` passing.
- Workspace and crate manifests are normally read-only for this phase:
  - `safe/Cargo.toml`
  - `safe/crates/libcjson/Cargo.toml`
  - `safe/crates/libcjson_utils/Cargo.toml`
  Touch them only if a build-system fix is required for a source/regression testcase.
- Do not modify `original/`; it is comparison-only upstream source.
- Do not weaken or remove checked-in upstream-style tests, relink tests, fuzz-corpus compatibility tests, existing regressions, ABI maps, Debian packaging metadata, or package metadata to make validator failures disappear.
- Do not commit raw artifacts from `.work/validation/`, `dist/`, logs, Debian package files, or `validator/artifacts/`; durable conclusions and any skipped-check justification must be written to `validator-report.md`.
- `validator-report.md`.

## Implementation Details
1. Classify Phase 1 failures from per-testcase result JSON by `kind`. This phase owns failures whose `kind` is `source` or `regression`.
2. Read the relevant validator scripts under `validator/tests/cjson/tests/cases/source/*.sh` and `validator/tests/cjson/tests/cases/regression/*.sh`. Extract the exact cJSON API behavior under test.
3. Add the smallest equivalent C regression under `safe/tests/regressions/`. The regression must assert the API behavior directly rather than merely imitating validator success.
4. Prefer one local test per root cause when several validator cases expose the same bug. If a case is already covered by `number_cve_2023_26819.c` or `json_pointer_cve_2025_57052.c`, extend the existing test minimally instead of adding a duplicate.
5. Register core tests with `add_safe_unity_test(...)` and utils-dependent tests with `add_safe_unity_utils_test(...)` in `safe/tests/CMakeLists.txt`, preserving the existing grouping pattern and the existing upstream-style, relink, fuzz-corpus, and regression registrations.
6. Fix the underlying safe implementation:
   - Preserve upstream `cJSON_InitHooks` semantics and consistent `cJSON_malloc`/`cJSON_free` hook usage.
   - Preserve hardened numeric token validation while matching upstream-compatible parse error pointer behavior.
   - Keep `cJSON_Minify` in-place C-string mutation behavior and preserve string contents while removing layout whitespace/comments.
   - Validate parse/print traversal, escaping, numeric printing, and null termination.
   - Keep `decode_array_index_from_pointer` as the single array-index parser and route lookup, detach, and patch operations through it consistently.
   - Preserve the Rust/C ABI build contract: `cdylib` and `staticlib` artifacts from both member crates, CMake `safe-libcjson` and `safe-libcjson-utils` targets, and wrapped shared libraries that continue to satisfy the ABI maps.
7. Do not modify files in `validator/`. If a validator case is demonstrably wrong, document the validator commit, test id, original-mode evidence if applicable, port-mode evidence, and reason the check is being skipped in `validator-report.md`. If the current validator runner cannot skip that one testcase without modifying validator source, document the limitation and treat it as an external blocker unless a source-preserving invocation exists at implementation time.
8. Run local tests in the main checkout. Before any package or validator run, update `validator-report.md` with the intended fixes and commit all Phase 2 source, test, packaging, script, and report changes. The committed SHA is the Phase 2 validation candidate and must be used as `SAFELIBS_COMMIT_SHA`. Validator `port` mode still consumes only the `.deb` overrides and port lock; do not add a `safe/` path to the validator invocation.
9. Run package and validator steps only through this validation worktree protocol:

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

10. Parse `summary.json` and every non-summary per-testcase JSON after the run. All `source` and `regression` failures must be resolved before this phase can pass.
11. Verify that the main checkout is clean after copied ignored artifacts are in place. If the validation run dirtied tracked files, especially `safe/debian/changelog`, correct the worktree protocol or build hook containment. Do not use `git restore`, `git checkout --`, or destructive cleanup in the main checkout to hide package-building side effects.
12. Update `validator-report.md` with fixed test ids, new local regression names, changed Rust files, remaining non-source/non-regression failures, the `Validated port commit`, and whether the final report commit differs. Commit that report update before yielding.
13. If there were no source/regression failures, update `validator-report.md` with "no source/regression fixes required" and commit that report update, or make an explicit empty commit.

## Verification Phases

### `check_02_source_regression_software_tester`
- `phase_id`: `check_02_source_regression_software_tester`
- `type`: `check`
- `bounce_target`: `impl_02_source_regression_fixes`
- `purpose`: verify every validator source/regression failure has a minimal local regression and that local Rust/C tests pass before rerunning the cjson validator matrix.
- `commands`:

```sh
git show --name-only --format=fuller HEAD
grep -E 'Source/API|CVE|regression|allocator-hooks-edge|malformed-number-rejection|minify-whitespace|parse-print-roundtrip|utils-patch-pointer|cve-2023-26819|cve-2025-57052' validator-report.md
rg -n 'relink|fuzz|regressions|add_safe_unity' safe/tests/CMakeLists.txt
(cd safe && cargo test --workspace)
tmp_build="$(mktemp -d)"; cmake -S safe -B "$tmp_build" -G Ninja -DENABLE_CJSON_UTILS=ON -DENABLE_CJSON_TEST=ON
cmake --build "$tmp_build"
ctest --test-dir "$tmp_build" --output-on-failure
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
python3 -c 'import json; from pathlib import Path; p=Path(".work/validation/artifacts/port/results/cjson"); bad=[]; [bad.append((r["kind"], r["testcase_id"], r["log_path"])) for f in p.glob("*.json") if f.name!="summary.json" for r in [json.load(open(f))] if r["status"]!="passed" and r["kind"] in {"source","regression"}]; assert not bad, bad; print("source/regression failures:", bad)'
```

### `check_02_source_regression_senior_tester`
- `phase_id`: `check_02_source_regression_senior_tester`
- `type`: `check`
- `bounce_target`: `impl_02_source_regression_fixes`
- `purpose`: review that fixes are minimal, local to cjson-safe, include regression tests, and do not weaken compatibility or safety checks.
- `commands`:

```sh
git diff HEAD~1..HEAD -- safe/crates safe/tests safe/CMakeLists.txt validator-report.md
git show --stat --oneline HEAD
rg -n 'validator|cve|allocator|number|pointer|patch|minify|roundtrip' safe/tests/regressions safe/tests/CMakeLists.txt validator-report.md
git -C validator status --short
git status --short
```

## Success Criteria
- Each fixed validator source/regression test id maps to a local regression test or a documented validator bug.
- `cd safe && cargo test --workspace` passes.
- CMake configure/build with `-DENABLE_CJSON_UTILS=ON -DENABLE_CJSON_TEST=ON` passes.
- `ctest --test-dir <build> --output-on-failure` passes.
- `safe/scripts/check-abi.sh <build>` passes.
- Existing checked-in upstream-style tests, relink tests, fuzz-corpus compatibility tests, and regressions remain registered in `safe/tests/CMakeLists.txt`.
- The validation worktree run has no remaining failed `source` or `regression` cjson results.
- Any remaining usage or packaging failures are documented for Phase 3.
- The main checkout has no tracked dirt from package building, especially no `safe/debian/changelog` modification caused by `scripts/build-debs.sh`.
- A clean main checkout is achieved by preventing package side effects outside `.work/validation-build-worktree/`; the phase must not use `git restore`, `git checkout --`, or destructive cleanup in the main checkout.

## Git Commit Requirement
The implementer must commit all work for this phase to git before yielding to the verifier phases. If no source/regression fix is required, the implementer must still commit a `validator-report.md` update or make an explicit empty phase-boundary commit.
