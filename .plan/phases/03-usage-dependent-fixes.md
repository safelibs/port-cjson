# Usage And Dependent-Client Validator Failures

## Phase Name
Usage And Dependent-Client Validator Failures

## Implement Phase ID
`impl_03_usage_dependent_fixes`

## Preexisting Inputs
- Phase 1 baseline report and Phase 2 fixes.
- `validator-report.md` with remaining failures after Phase 2.
- `validator/` checkout at the commit recorded in `validator-report.md`.
- Validator usage result artifacts under `.work/validation/artifacts/port/results/cjson/` if still present.
- `original/` as comparison source only; do not edit or regenerate upstream code.
- Existing `tests/`, `tests/upstream/`, and `tests/port/` artifacts from the port template, including any checked-in upstream tests. Consume these checked-in tests in place; do not rediscover or regenerate them.
- Safe workspace/build context from prior phases: two Rust member crates, `cdylib` and `staticlib` outputs, CMake wrapping of Rust static archives into ABI-compatible shared libraries, Debian dependencies, and `dpkg-buildpackage` rooted in `safe/`.
- `validator/tests/cjson/tests/fixtures/dependents.json`, whose current cjson dependent is `iperf3`.
- Local dependent smoke tests:
  - `safe/tests/regressions/dependents_parse_payloads_smoke.c`
  - `safe/tests/regressions/dependents_roundtrip_shapes_smoke.c`
  - `safe/tests/regressions/dependents_config_roundtrip_smoke.c`
- Packaging and install files:
  - `packaging/package.env`
  - `safe/debian/control`
  - `safe/debian/rules`
  - `safe/debian/libcjson-dev.install`
  - `safe/debian/libcjson1.install`
  - `safe/debian/libcjson1.symbols`
  - `safe/library_config/*.in`
  - `safe/CMakeLists.txt`
- ABI maps `safe/abi/libcjson.map` and `safe/abi/libcjson_utils.map`.
- Checked-in `safe/tests/CMakeLists.txt` registrations for upstream-style C tests, relink tests, fuzz-corpus compatibility tests, and regressions.
- Core and utils implementation files under `safe/crates/` that affect dependent-client public API behavior.

## New Outputs
- Minimal dependent-use regression tests under `safe/tests/regressions/`, or carefully extended existing dependent smoke tests.
- Safe-port behavior fixes or packaging fixes.
- `validator-report.md` updated with usage failures fixed, remaining failures, commands run, and validated commit details.
- One or more git commits for this phase, ending with committed usage fix results.

## File Changes
- Candidate new tests:
  - `safe/tests/regressions/validator_usage_iperf3_roundtrip.c`
  - `safe/tests/regressions/validator_usage_iperf3_number_shape.c`
  - Or a focused name matching the actual failing validator usage test.
- `safe/tests/CMakeLists.txt` for test registration.
- Candidate behavior files:
  - `safe/crates/libcjson/src/abi.rs`
  - `safe/crates/libcjson/src/parse.rs`
  - `safe/crates/libcjson/src/print.rs`
  - `safe/crates/libcjson/src/number.rs`
  - `safe/crates/libcjson/src/string.rs`
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
- Candidate packaging files if usage failures are due to install or link behavior:
  - `packaging/package.env`
  - `safe/CMakeLists.txt`
  - `safe/debian/control`
  - `safe/debian/rules`
  - `safe/debian/libcjson-dev.install`
  - `safe/debian/libcjson1.install`
  - `safe/debian/libcjson1.symbols`
  - `safe/library_config/libcjson.pc.in`
  - `safe/library_config/libcjson_utils.pc.in`
  - `safe/library_config/cJSONConfig.cmake.in`
  - `safe/library_config/cJSONConfigVersion.cmake.in`
- ABI files are compatibility constraints:
  - `safe/abi/libcjson.map`
  - `safe/abi/libcjson_utils.map`
  Touch them only when a dependent-client failure proves the exported symbol contract is wrong, and keep `safe/scripts/check-abi.sh` passing.
- Workspace and crate manifests are normally read-only for this phase:
  - `safe/Cargo.toml`
  - `safe/crates/libcjson/Cargo.toml`
  - `safe/crates/libcjson_utils/Cargo.toml`
  Touch them only if a dependent build or link failure requires it.
- Do not modify `original/`; it is comparison-only upstream source.
- Do not weaken or remove checked-in upstream-style tests, relink tests, fuzz-corpus compatibility tests, existing regressions, ABI maps, Debian packaging metadata, package metadata, or checked-in `tests/` artifacts to make dependent failures disappear.
- Do not commit raw artifacts from `.work/validation/`, `dist/`, logs, Debian package files, or `validator/artifacts/`; durable conclusions and any skipped-check justification must be written to `validator-report.md`.
- `validator-report.md`.

## Implementation Details
1. Classify remaining Phase 1 or Phase 2 failures from per-testcase result JSON by `kind`. This phase owns failures whose `kind` is `usage`.
2. Read the relevant validator usage scripts under `validator/tests/cjson/tests/cases/usage/*.sh` and group failures by root cause.
3. Treat the iperf3 dependent fixture as evidence of cJSON public API behavior or packaging contract, not as a reason to tune output for one transient runtime value.
4. Add a minimal local C regression using the cJSON public API. Prefer stable deterministic API checks over invoking `iperf3` inside local tests. Do not copy large generated fixture output unless it is necessary and small.
5. If the failure is packaging/install related, verify the installed contract:
   - Headers include as both `<cJSON.h>` and `<cjson/cJSON.h>`.
   - `pkg-config --cflags --libs libcjson` and `libcjson_utils` work.
   - CMake package exports work.
   - `libcjson_utils.so` depends on `libcjson.so.1`.
   - Debian package names match validator canonical packages.
   - The packages are produced by `scripts/build-debs.sh` through `dpkg-buildpackage` rooted in `safe/`, not by a one-off artifact generation path.
   - The CMake/Cargo bridge continues to wrap Rust static archives into ABI-compatible shared libraries for both core cJSON and cJSON Utils.
6. Fix the smallest safe-port root cause:
   - For printed numeric shape, inspect `safe/crates/libcjson/src/number.rs` and preserve cJSON's 15/17 digit behavior.
   - For parse/print roundtrip shape, inspect `safe/crates/libcjson/src/parse.rs`, `safe/crates/libcjson/src/string.rs`, and `safe/crates/libcjson/src/print.rs`.
   - For object/list mutation or lookup differences, inspect `safe/crates/libcjson/src/list.rs` and `safe/crates/libcjson/src/mutate.rs`.
   - For install/link failures, fix CMake, Debian install files, pkg-config templates, or symbol files as needed.
7. Do not modify files in `validator/`. If a usage failure is a proven validator bug rather than a cJSON behavior or packaging issue, document the validator commit, test id, original-mode evidence if applicable, port-mode evidence, and reason the check is being skipped in `validator-report.md`. If the current validator runner cannot skip that one testcase without modifying validator source, document the limitation and treat it as an external blocker unless a source-preserving invocation exists at implementation time.
8. Preserve the existing upstream-style, relink, fuzz-corpus, dependent smoke, and regression test registrations in `safe/tests/CMakeLists.txt`. If a usage reproducer is added, register it alongside the existing dependent-client smoke coverage rather than replacing checked-in tests.
9. Run local tests and packaging-contract checks in the main checkout. Before any package or validator run, update `validator-report.md` with intended usage fixes and commit all Phase 3 source, test, packaging, script, and report changes. The committed SHA is the Phase 3 validation candidate and must be used as `SAFELIBS_COMMIT_SHA`. Validator `port` mode still consumes only the `.deb` overrides and port lock; do not add a `safe/` path to the validator invocation.
10. Run package and validator steps only through this validation worktree protocol:

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

11. Parse `summary.json` and every non-summary per-testcase JSON after the run. All `usage` failures must be resolved before this phase can pass unless a validator bug is documented as an explicit blocker with the evidence described above.
12. Verify that the main checkout is clean after copied ignored artifacts are in place. If the validation run dirtied tracked files, especially `safe/debian/changelog`, correct the worktree protocol or build hook containment. Do not use `git restore`, `git checkout --`, or destructive cleanup in the main checkout to hide package-building side effects.
13. Update `validator-report.md` with fixed usage failures, added local regression tests, any non-usage failures left for Phase 4, any documented validator bug blockers, the `Validated port commit`, and whether the final report commit differs. Commit that report update before yielding.
14. If there were no usage failures, update `validator-report.md` with "no usage/dependent fixes required" and commit that report update, or make an explicit empty commit.

## Verification Phases

### `check_03_usage_software_tester`
- `phase_id`: `check_03_usage_software_tester`
- `type`: `check`
- `bounce_target`: `impl_03_usage_dependent_fixes`
- `purpose`: verify iperf3/dependent usage failures have local reproductions and that the packaged port works through installed headers/libraries.
- `commands`:

```sh
git show --name-only --format=fuller HEAD
grep -E 'usage|iperf3|dependent|validator usage' validator-report.md
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
python3 -c 'import json; from pathlib import Path; p=Path(".work/validation/artifacts/port/results/cjson"); bad=[]; [bad.append((r["kind"], r["testcase_id"], r["log_path"])) for f in p.glob("*.json") if f.name!="summary.json" for r in [json.load(open(f))] if r["status"]!="passed" and r["kind"]=="usage"]; assert not bad, bad; print("usage failures:", bad)'
```

### `check_03_usage_senior_tester`
- `phase_id`: `check_03_usage_senior_tester`
- `type`: `check`
- `bounce_target`: `impl_03_usage_dependent_fixes`
- `purpose`: review that dependent fixes address cjson behavior or packaging contract, not brittle iperf3-specific output assumptions.
- `commands`:

```sh
git diff HEAD~1..HEAD -- safe scripts packaging validator-report.md
rg -n 'iperf3|dependent|roundtrip|print|parse|pkg-config|cmake|install' safe/tests safe/crates safe/debian safe/library_config validator-report.md
git -C validator status --short
git status --short
```

## Success Criteria
- Every fixed usage failure maps to a local regression or packaging check.
- `safe/scripts/check-build-contract.sh` passes.
- `safe/scripts/check-abi.sh <build>` passes.
- The full local CTest suite passes.
- Existing checked-in upstream-style tests, relink tests, fuzz-corpus compatibility tests, dependent smoke tests, and regressions remain registered in `safe/tests/CMakeLists.txt`.
- The full cjson validator matrix has no remaining failed `usage` results.
- Any validator bug exception is documented with validator commit, test id, original-mode evidence if applicable, port-mode evidence, and a source-preserving skip/blocker explanation.
- Any non-usage failures are explicitly carried to Phase 4.
- The main checkout has no tracked dirt from package building, especially no `safe/debian/changelog` modification caused by `scripts/build-debs.sh`.
- A clean main checkout is achieved by preventing package side effects outside `.work/validation-build-worktree/`; the phase must not use `git restore`, `git checkout --`, or destructive cleanup in the main checkout.

## Git Commit Requirement
The implementer must commit all work for this phase to git before yielding to the verifier phases. If no usage/dependent fix is required, the implementer must still commit a `validator-report.md` update or make an explicit empty phase-boundary commit.
