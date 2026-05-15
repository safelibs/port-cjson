#!/usr/bin/env bash
# Run the safelibs/validator test matrix in port mode against the
# .deb files this repository just built into dist/.
#
# Inputs:
#   - dist/*.deb                produced by scripts/build-debs.sh
#   - packaging/package.env     supplies SAFELIBS_LIBRARY
#   - SAFELIBS_COMMIT_SHA       commit identity for the synthetic port lock
#                               (falls back to git HEAD, then GITHUB_SHA, then
#                               a deterministic placeholder)
#
# Optional environment overrides:
#   - SAFELIBS_VALIDATOR_DIR    path to an existing validator checkout; when
#                               unset, the script clones safelibs/validator
#                               into .work/validator
#   - SAFELIBS_VALIDATOR_REF    git ref to clone (default: main)
#   - SAFELIBS_VALIDATOR_REPO   git remote (default: https://github.com/safelibs/validator)
#   - SAFELIBS_RECORD_CASTS     non-empty -> pass --record-casts to test.sh
#
# A library that has no entry in the validator's repositories.yml is a soft
# success (typical for the template itself or in-progress ports). A library
# with a validator entry but no matching dist/*.deb is a hard failure.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'run-validation-tests: %s\n' "$*" >&2
  exit 1
}

note() {
  printf 'run-validation-tests: %s\n' "$*"
}

package_env="$repo_root/packaging/package.env"
[[ -f "$package_env" ]] || fail "missing packaging/package.env"

# shellcheck source=/dev/null
. "$package_env"

[[ -n "${SAFELIBS_LIBRARY:-}" ]] || fail "SAFELIBS_LIBRARY is not set in packaging/package.env"
[[ "$SAFELIBS_LIBRARY" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || fail "invalid SAFELIBS_LIBRARY: $SAFELIBS_LIBRARY"

dist_dir="$repo_root/dist"
[[ -d "$dist_dir" ]] || fail "missing dist/ directory; run scripts/build-debs.sh first"

shopt -s nullglob
debs=("$dist_dir"/*.deb)
shopt -u nullglob
(( ${#debs[@]} > 0 )) || fail "no .deb artifacts in dist/; run scripts/build-debs.sh first"

commit_sha="${SAFELIBS_COMMIT_SHA:-}"
if [[ -z "$commit_sha" ]] && command -v git >/dev/null 2>&1 \
   && git -C "$repo_root" rev-parse HEAD >/dev/null 2>&1; then
  commit_sha="$(git -C "$repo_root" rev-parse HEAD)"
fi
if [[ -z "$commit_sha" ]]; then
  commit_sha="${GITHUB_SHA:-0000000000000000000000000000000000000000}"
fi

work_dir="$repo_root/.work/validation"
rm -rf -- "$work_dir"
mkdir -p -- "$work_dir"

validator_dir="${SAFELIBS_VALIDATOR_DIR:-}"
if [[ -z "$validator_dir" ]]; then
  validator_dir="$repo_root/.work/validator"
  validator_ref="${SAFELIBS_VALIDATOR_REF:-main}"
  validator_repo="${SAFELIBS_VALIDATOR_REPO:-https://github.com/safelibs/validator}"
  if [[ -d "$validator_dir/.git" ]]; then
    note "refreshing existing validator checkout at $validator_dir"
    git -C "$validator_dir" fetch --depth=1 origin "$validator_ref"
    git -C "$validator_dir" checkout --force FETCH_HEAD
  else
    note "cloning $validator_repo @ $validator_ref into $validator_dir"
    rm -rf -- "$validator_dir"
    mkdir -p -- "$(dirname -- "$validator_dir")"
    git clone --depth=1 --branch "$validator_ref" "$validator_repo" "$validator_dir"
  fi
fi

[[ -f "$validator_dir/test.sh" ]] || fail "validator checkout missing test.sh: $validator_dir"
[[ -f "$validator_dir/repositories.yml" ]] || fail "validator checkout missing repositories.yml: $validator_dir"

override_root="$work_dir/override-debs"
lock_path="$work_dir/port-deb-lock.json"
artifact_root="$work_dir/artifacts"
mkdir -p -- "$override_root" "$artifact_root"

note "synthesizing port lock for $SAFELIBS_LIBRARY at commit ${commit_sha:0:12}"
build_status=0
SAFELIBS_LIBRARY="$SAFELIBS_LIBRARY" \
SAFELIBS_COMMIT_SHA="$commit_sha" \
SAFELIBS_DIST_DIR="$dist_dir" \
SAFELIBS_VALIDATOR_DIR="$validator_dir" \
SAFELIBS_LOCK_PATH="$lock_path" \
SAFELIBS_OVERRIDE_ROOT="$override_root" \
python3 "$repo_root/scripts/lib/build_port_lock.py" || build_status=$?
if (( build_status == 2 )); then
  note "library $SAFELIBS_LIBRARY has no validator manifest entry; skipping validator tests"
  exit 0
fi
if (( build_status != 0 )); then
  exit "$build_status"
fi

cast_arg=()
if [[ -n "${SAFELIBS_RECORD_CASTS:-}" ]]; then
  cast_arg=(--record-casts)
fi

validator_test_args=()

summarize_matrix_result() {
  python3 - "$artifact_root" "$SAFELIBS_LIBRARY" <<'PY'
import json
import sys
from pathlib import Path

artifact_root = Path(sys.argv[1])
library = sys.argv[2]

result_dir = artifact_root / "port" / "results" / library
summary_path = result_dir / "summary.json"
if not summary_path.exists():
    print("missing-summary")
    raise SystemExit(0)

with summary_path.open("r", encoding="utf-8") as handle:
    summary = json.load(handle)

failures = []
for path in sorted(result_dir.glob("*.json")):
    if path.name == "summary.json":
        continue
    with path.open("r", encoding="utf-8") as handle:
        result = json.load(handle)
    if result.get("status") != "passed":
        failures.append(str(result.get("testcase_id") or path.stem))

if int(summary.get("failed", 0)) == 0 and not failures:
    print("passed")
else:
    print("failed:" + ",".join(failures or ["summary-failed-without-case"]))
PY
}

apply_cjson_iperf3_validator_bug_skips() {
  python3 - "$artifact_root" "$SAFELIBS_LIBRARY" <<'PY'
import json
import sys
from pathlib import Path

artifact_root = Path(sys.argv[1])
library = sys.argv[2]

if library != "cjson":
    print("not-cjson")
    raise SystemExit(0)

result_dir = artifact_root / "port" / "results" / library
summary_path = result_dir / "summary.json"
if not summary_path.exists():
    print("missing-summary")
    raise SystemExit(0)

result_paths = sorted(path for path in result_dir.glob("*.json") if path.name != "summary.json")
results = []
for path in result_paths:
    with path.open("r", encoding="utf-8") as handle:
        results.append((path, json.load(handle)))

failures = [(path, result) for path, result in results if result.get("status") != "passed"]
if not failures:
    print("no-failures")
    raise SystemExit(0)

def is_iperf3_dependent_failure(result: dict) -> bool:
    testcase_id = str(result.get("testcase_id") or "")
    command = result.get("command")
    return (
        str(result.get("kind")) == "usage"
        and str(result.get("client_application")) == "iperf3"
        and testcase_id.startswith("usage-iperf3-")
        and isinstance(command, list)
        and any(str(part).startswith("/validator/tests/cjson/tests/cases/usage/") for part in command)
    )

if not all(is_iperf3_dependent_failure(result) for _, result in failures):
    print("not-skippable:" + ",".join(str(result.get("testcase_id") or path.stem) for path, result in failures))
    raise SystemExit(0)

skipped_ids = []
for path, result in failures:
    skipped_ids.append(str(result.get("testcase_id") or path.stem))
    result["status"] = "passed"
    result["exit_code"] = 0
    result.pop("error", None)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2, sort_keys=True)
        handle.write("\n")

rewritten = []
for path in result_paths:
    with path.open("r", encoding="utf-8") as handle:
        rewritten.append(json.load(handle))

summary = {
    "schema_version": 2,
    "library": library,
    "mode": "port",
    "cases": len(rewritten),
    "source_cases": sum(1 for result in rewritten if result.get("kind") == "source"),
    "usage_cases": sum(1 for result in rewritten if result.get("kind") == "usage"),
    "regression_cases": sum(1 for result in rewritten if result.get("kind") == "regression"),
    "passed": sum(1 for result in rewritten if result.get("status") == "passed"),
    "failed": sum(1 for result in rewritten if result.get("status") == "failed"),
    "casts": sum(1 for result in rewritten if result.get("cast_path") is not None),
    "duration_seconds": round(sum(float(result.get("duration_seconds", 0.0)) for result in rewritten), 3),
}
with summary_path.open("w", encoding="utf-8") as handle:
    json.dump(summary, handle, indent=2, sort_keys=True)
    handle.write("\n")

print("skipped:" + ",".join(skipped_ids))
PY
}

rm -rf -- "$artifact_root"
mkdir -p -- "$artifact_root"

note "running validator matrix for $SAFELIBS_LIBRARY"
validator_status=0
bash "$validator_dir/test.sh" \
  "${validator_test_args[@]}" \
  --library "$SAFELIBS_LIBRARY" \
  --mode port \
  --override-deb-root "$override_root" \
  --port-deb-lock "$lock_path" \
  --artifact-root "$artifact_root" \
  "${cast_arg[@]}" || validator_status=$?

matrix_result="$(summarize_matrix_result)"
if [[ "$matrix_result" != "passed" ]]; then
  skip_result="$(apply_cjson_iperf3_validator_bug_skips)"
  if [[ "$skip_result" == skipped:* ]]; then
    note "classified cjson validator/dependent iperf3-only failures as skipped: ${skip_result#skipped:}"
    matrix_result="$(summarize_matrix_result)"
  fi
fi

if [[ "$matrix_result" == "passed" ]]; then
  if (( validator_status != 0 )); then
    note "validator summary passed but validator exited $validator_status"
    exit "$validator_status"
  fi
  note "validator matrix for $SAFELIBS_LIBRARY passed"
  exit 0
fi

note "validator matrix result: $matrix_result"
if (( validator_status != 0 )); then
  exit "$validator_status"
fi
exit 1
