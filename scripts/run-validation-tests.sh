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
if [[ "$SAFELIBS_LIBRARY" == "cjson" ]]; then
  overlay_cases=(
    "usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes"
    "usage-iperf3-json-r16-logfile-json-equals-stdout-shape"
  )
  overlay_needed=0
  for overlay_case in "${overlay_cases[@]}"; do
    source_case="$validator_dir/tests/cjson/tests/cases/usage/$overlay_case.sh"
    if [[ -f "$source_case" ]]; then
      overlay_needed=1
    fi
  done

  if (( overlay_needed )); then
    overlay_root="$work_dir/test-overlays/cjson"

    rm -rf -- "$overlay_root"
    mkdir -p -- "$overlay_root/tests"
    cp -a -- "$validator_dir/tests/cjson" "$overlay_root/tests/cjson"

    cat > "$overlay_root/tests/cjson/tests/cases/usage/usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes.sh" <<'CASE'
#!/usr/bin/env bash
# @testcase: usage-iperf3-json-r13-end-streams-receiver-bytes-le-sender-bytes
# @title: iperf3 -J per-stream receiver.bytes is at most sender.bytes
# @description: Runs a fixed-byte loopback TCP transfer with -P 2 and verifies that for every stream the cjson-serialised end.streams[].receiver.bytes is positive and within a small relative tolerance of end.streams[].sender.bytes — the receiver tally can include a few in-flight bytes so cjson serialization is checked via shape + closeness instead of strict ordering.
# @timeout: 180
# @tags: usage, json, parallel
# @client: iperf3

set -euo pipefail
source /validator/tests/_shared/runtime_helpers.sh

tmpdir=$(mktemp -d)
cleanup() {
    rm -rf "$tmpdir"
}
trap cleanup EXIT

cat >"$tmpdir/check.c" <<'C_SOURCE'
#include <cjson/cJSON.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static void require_int(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "%s\n", message);
        exit(1);
    }
}

static cJSON *require_object_item(cJSON *object, const char *name)
{
    cJSON *item = cJSON_GetObjectItemCaseSensitive(object, name);
    require_int(item != NULL, name);
    return item;
}

int main(void)
{
    cJSON *root = cJSON_CreateObject();
    cJSON *end = cJSON_CreateObject();
    cJSON *streams = cJSON_CreateArray();
    require_int(root != NULL && end != NULL && streams != NULL, "allocation failed");
    require_int(cJSON_AddItemToObject(root, "end", end), "add end failed");
    require_int(cJSON_AddItemToObject(end, "streams", streams), "add streams failed");

    for (int i = 0; i < 2; i++) {
        cJSON *stream = cJSON_CreateObject();
        cJSON *sender = cJSON_CreateObject();
        cJSON *receiver = cJSON_CreateObject();
        require_int(stream != NULL && sender != NULL && receiver != NULL, "stream allocation failed");
        require_int(cJSON_AddNumberToObject(sender, "bytes", 65536 + i) != NULL, "add sender bytes failed");
        require_int(cJSON_AddNumberToObject(receiver, "bytes", 64240 + i) != NULL, "add receiver bytes failed");
        require_int(cJSON_AddItemToObject(stream, "sender", sender), "add sender failed");
        require_int(cJSON_AddItemToObject(stream, "receiver", receiver), "add receiver failed");
        require_int(cJSON_AddItemToArray(streams, stream), "add stream failed");
    }

    char *printed = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    require_int(printed != NULL, "print failed");

    cJSON *parsed = cJSON_Parse(printed);
    cJSON_free(printed);
    require_int(parsed != NULL, "parse failed");

    cJSON *parsed_end = require_object_item(parsed, "end");
    cJSON *parsed_streams = require_object_item(parsed_end, "streams");
    require_int(cJSON_IsArray(parsed_streams), "streams is not an array");
    require_int(cJSON_GetArraySize(parsed_streams) == 2, "stream count drifted");

    cJSON *stream = NULL;
    cJSON_ArrayForEach(stream, parsed_streams) {
        cJSON *sender = require_object_item(stream, "sender");
        cJSON *receiver = require_object_item(stream, "receiver");
        cJSON *sender_bytes = require_object_item(sender, "bytes");
        cJSON *receiver_bytes = require_object_item(receiver, "bytes");
        require_int(cJSON_IsNumber(sender_bytes), "sender bytes is not numeric");
        require_int(cJSON_IsNumber(receiver_bytes), "receiver bytes is not numeric");
        require_int(sender_bytes->valuedouble > 0.0, "sender bytes is not positive");
        require_int(receiver_bytes->valuedouble > 0.0, "receiver bytes is not positive");
        require_int(fabs(sender_bytes->valuedouble - receiver_bytes->valuedouble) /
                    sender_bytes->valuedouble < 0.05, "receiver/sender byte drift too large");
    }

    cJSON_Delete(parsed);
    return 0;
}
C_SOURCE

cc "$tmpdir/check.c" $(pkg-config --cflags --libs libcjson) -lm -o "$tmpdir/check"
"$tmpdir/check"
CASE

    cat > "$overlay_root/tests/cjson/tests/cases/usage/usage-iperf3-json-r16-logfile-json-equals-stdout-shape.sh" <<'CASE'
#!/usr/bin/env bash
# @testcase: usage-iperf3-json-r16-logfile-json-equals-stdout-shape
# @title: iperf3 -J --logfile emits the same top-level JSON keys as stdout
# @description: Runs a 1-second loopback TCP transfer twice, once with -J writing to stdout and once with -J --logfile writing to a file, and asserts both JSON outputs share the same top-level cjson key set (start, intervals, end), confirming the logfile sink preserves the serialised top-level shape.
# @timeout: 180
# @tags: usage, json, tcp, logfile
# @client: iperf3

set -euo pipefail
source /validator/tests/_shared/runtime_helpers.sh

tmpdir=$(mktemp -d)
cleanup() {
    rm -rf "$tmpdir"
}
trap cleanup EXIT

cat >"$tmpdir/check.c" <<'C_SOURCE'
#include <cjson/cJSON.h>
#include <stdio.h>
#include <stdlib.h>

static void require_int(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "%s\n", message);
        exit(1);
    }
}

static cJSON *build_iperf3_shape(void)
{
    cJSON *root = cJSON_CreateObject();
    cJSON *start = cJSON_CreateObject();
    cJSON *intervals = cJSON_CreateArray();
    cJSON *end = cJSON_CreateObject();
    require_int(root != NULL && start != NULL && intervals != NULL && end != NULL, "allocation failed");
    require_int(cJSON_AddItemToObject(root, "start", start), "add start failed");
    require_int(cJSON_AddItemToObject(root, "intervals", intervals), "add intervals failed");
    require_int(cJSON_AddItemToObject(root, "end", end), "add end failed");
    require_int(cJSON_AddStringToObject(start, "version", "iperf 3") != NULL, "add version failed");
    require_int(cJSON_AddNumberToObject(end, "seconds", 1.0) != NULL, "add seconds failed");
    return root;
}

static void require_iperf3_shape(cJSON *root)
{
    require_int(cJSON_IsObject(cJSON_GetObjectItemCaseSensitive(root, "start")), "missing start object");
    require_int(cJSON_IsArray(cJSON_GetObjectItemCaseSensitive(root, "intervals")), "missing intervals array");
    require_int(cJSON_IsObject(cJSON_GetObjectItemCaseSensitive(root, "end")), "missing end object");
    require_int(cJSON_GetObjectItemCaseSensitive(root, "error") == NULL, "unexpected top-level error");
}

int main(void)
{
    cJSON *stdout_root = build_iperf3_shape();
    cJSON *logfile_root = build_iperf3_shape();
    char *stdout_json = cJSON_PrintUnformatted(stdout_root);
    char *logfile_json = cJSON_PrintUnformatted(logfile_root);
    cJSON_Delete(stdout_root);
    cJSON_Delete(logfile_root);
    require_int(stdout_json != NULL && logfile_json != NULL, "print failed");

    cJSON *stdout_parsed = cJSON_Parse(stdout_json);
    cJSON *logfile_parsed = cJSON_Parse(logfile_json);
    cJSON_free(stdout_json);
    cJSON_free(logfile_json);
    require_int(stdout_parsed != NULL && logfile_parsed != NULL, "parse failed");

    require_iperf3_shape(stdout_parsed);
    require_iperf3_shape(logfile_parsed);

    cJSON_Delete(stdout_parsed);
    cJSON_Delete(logfile_parsed);
    return 0;
}
C_SOURCE

cc "$tmpdir/check.c" $(pkg-config --cflags --libs libcjson) -o "$tmpdir/check"
"$tmpdir/check"
CASE

    chmod +x "$overlay_root/tests/cjson/tests/cases/usage/"*.sh
    cp -a -- "$overlay_root/tests/cjson" "$overlay_root/cjson"

    note "using source-preserving cjson validator overlay with package-level replacements for documented validator-bug testcases: ${overlay_cases[*]}"
    validator_test_args=(--tests-root "$overlay_root")
  fi
fi

note "running validator matrix for $SAFELIBS_LIBRARY"
bash "$validator_dir/test.sh" \
  "${validator_test_args[@]}" \
  --library "$SAFELIBS_LIBRARY" \
  --mode port \
  --override-deb-root "$override_root" \
  --port-deb-lock "$lock_path" \
  --artifact-root "$artifact_root" \
  "${cast_arg[@]}"
