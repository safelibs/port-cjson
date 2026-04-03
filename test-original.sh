#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_TAG="${CJSON_ORIGINAL_TEST_IMAGE:-cjson-original-test:ubuntu24.04}"
ONLY=""

usage() {
  cat <<'EOF'
usage: test-original.sh [--only <source-package>]

Runs a Docker-based compatibility matrix for the Ubuntu 24.04 cJSON dependents
recorded in dependents.json, using the packaged safe cJSON build.

--only limits execution to a single source package from dependents.json.
EOF
}

while (($#)); do
  case "$1" in
    --only)
      ONLY="${2:?missing value for --only}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

command -v docker >/dev/null 2>&1 || {
  echo "docker is required to run $0" >&2
  exit 1
}

docker build -t "$IMAGE_TAG" - <<'DOCKERFILE'
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      autoconf \
      automake \
      build-essential \
      ca-certificates \
      cargo \
      cmake \
      debhelper \
      dpkg-dev \
      file \
      jq \
      libtool \
      meson \
      netcat-openbsd \
      ninja-build \
      pkg-config \
      python3 \
      python3-pkg-resources \
      ripgrep \
      rustc \
      util-linux \
 && rm -rf /var/lib/apt/lists/*
DOCKERFILE

docker run \
  --rm \
  -i \
  -e "CJSON_TEST_ONLY=$ONLY" \
  -v "$ROOT":/work:ro \
  "$IMAGE_TAG" \
  bash -s <<'CONTAINER_SCRIPT'
set -Eeuo pipefail

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

READ_ONLY_ROOT=/work
ROOT=/tmp/cjson-work
ONLY="${CJSON_TEST_ONLY:-}"
APT_UPDATED=0
CJSON_MULTIARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
CJSON_LIBDIR="/usr/lib/$CJSON_MULTIARCH"
CURRENT_DEPENDENT=""
CURRENT_FAILURE_CLASS=""
CURRENT_FAILURE_STAGE=""
FAILURE_CONTEXT_REPORTED=0
declare -A BUILD_DEPS_READY=()
declare -A SOURCE_DIRS=()

log() {
  printf '\n==> %s\n' "$1"
}

die() {
  report_failure_context 1
  printf 'error: %s\n' "$*" >&2
  exit 1
}

set_failure_context() {
  CURRENT_DEPENDENT="$1"
  CURRENT_FAILURE_CLASS="$2"
  CURRENT_FAILURE_STAGE="$3"
  FAILURE_CONTEXT_REPORTED=0
}

clear_failure_context() {
  CURRENT_DEPENDENT=""
  CURRENT_FAILURE_CLASS=""
  CURRENT_FAILURE_STAGE=""
  FAILURE_CONTEXT_REPORTED=0
}

report_failure_context() {
  local rc="${1:-1}"

  if [[ "$rc" -eq 0 || -z "$CURRENT_DEPENDENT" || -z "$CURRENT_FAILURE_CLASS" || "$FAILURE_CONTEXT_REPORTED" -eq 1 ]]; then
    return 0
  fi

  printf 'failure classification: dependent=%s class=%s stage=%s\n' \
    "$CURRENT_DEPENDENT" "$CURRENT_FAILURE_CLASS" "$CURRENT_FAILURE_STAGE" >&2
  FAILURE_CONTEXT_REPORTED=1
}

trap 'rc=$?; report_failure_context "$rc"; exit "$rc"' ERR

with_failure_context() {
  local dependent="$1"
  local failure_class="$2"
  local failure_stage="$3"
  shift 3

  set_failure_context "$dependent" "$failure_class" "$failure_stage"
  "$@"
  clear_failure_context
}

assert_dependents_inventory() {
  python3 - "$ROOT/dependents.json" <<'PY'
import json
import sys
from pathlib import Path

expected = [
    "freerdp3",
    "librist",
    "monado",
    "mosquitto",
    "ocp",
    "oidc-agent",
    "pgagroal",
    "qad",
    "snibbetracker",
    "opm-common",
    "iperf3",
    "epic5",
]

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
actual = [entry["source_package"] for entry in data["dependents"]]

if actual != expected:
    raise SystemExit(
        f"unexpected dependents.json source package list: expected {expected}, found {actual}"
    )
PY
}

assert_only_filter() {
  if [[ -z "$ONLY" ]]; then
    return 0
  fi

  python3 - "$ONLY" "$ROOT/dependents.json" <<'PY'
import json
import sys
from pathlib import Path

name = sys.argv[1]
data = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
known = {entry["source_package"] for entry in data["dependents"]}
if name not in known:
    raise SystemExit(f"unknown --only source package: {name}")
PY
}

should_run() {
  local pkg="$1"
  [[ -z "$ONLY" || "$ONLY" == "$pkg" ]]
}

apt_refresh() {
  if [[ "$APT_UPDATED" -eq 0 ]]; then
    apt-get update >/dev/null
    APT_UPDATED=1
  fi
}

install_packages() {
  apt_refresh
  apt-get install -y --no-install-recommends "$@" >/dev/null
}

install_build_deps() {
  local pkg="$1"

  if [[ -n "${BUILD_DEPS_READY[$pkg]:-}" ]]; then
    return 0
  fi

  log "$pkg: installing build dependencies"
  apt_refresh
  apt-get build-dep -y "$pkg" >/dev/null
  BUILD_DEPS_READY[$pkg]=1
}

fetch_source() {
  local pkg="$1"
  local src_root="/tmp/dependent-sources/$pkg"
  local source_dir=""

  if [[ -n "${SOURCE_DIRS[$pkg]:-}" ]]; then
    printf '%s\n' "${SOURCE_DIRS[$pkg]}"
    return 0
  fi

  log "$pkg: fetching source package" >&2
  apt_refresh
  rm -rf "$src_root"
  mkdir -p "$src_root"
  (
    cd "$src_root"
    apt-get source "$pkg" >/dev/null
  )

  source_dir="$(find "$src_root" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "$source_dir" ]] || die "failed to unpack source package for $pkg"

  SOURCE_DIRS[$pkg]="$source_dir"
  printf '%s\n' "$source_dir"
}

run_logged() {
  local log_file="$1"
  shift

  if ! "$@" >"$log_file" 2>&1; then
    cat "$log_file" >&2
    return 1
  fi
}

run_bash_logged() {
  local log_file="$1"
  local script="$2"

  if ! bash -lc "$script" >"$log_file" 2>&1; then
    cat "$log_file" >&2
    return 1
  fi
}

prepare_writable_root() {
  log "Copying repository into a writable workspace"
  rm -rf "$ROOT"
  mkdir -p "$ROOT"
  cp -a "$READ_ONLY_ROOT/." "$ROOT/"
}

assert_owned_by_package() {
  local package_name="$1"
  local path="$2"
  local canonical_path=""

  if dpkg -S "$path" 2>/dev/null | grep -E "^${package_name}(:[[:alnum:]-]+)?: " >/dev/null; then
    return 0
  fi

  canonical_path="$(readlink -f "$path")"
  if dpkg -S "$canonical_path" 2>/dev/null | grep -E "^${package_name}(:[[:alnum:]-]+)?: " >/dev/null; then
    return 0
  fi

  echo "expected $path to be owned by $package_name" >&2
  dpkg -S "$path" >&2 || true
  if [[ "$canonical_path" != "$path" ]]; then
    dpkg -S "$canonical_path" >&2 || true
  fi
  return 1
}

assert_safe_packages_installed() {
  local runtime_matches=()
  local utils_matches=()
  local path=""
  local dev_paths=(
    "/usr/include/cjson/cJSON.h"
    "/usr/include/cjson/cJSON_Utils.h"
    "$CJSON_LIBDIR/libcjson.so"
    "$CJSON_LIBDIR/libcjson_utils.so"
    "$CJSON_LIBDIR/pkgconfig/libcjson.pc"
    "$CJSON_LIBDIR/pkgconfig/libcjson_utils.pc"
    "$CJSON_LIBDIR/cmake/cJSON/cJSONConfig.cmake"
    "$CJSON_LIBDIR/cmake/cJSON/cJSONConfigVersion.cmake"
    "$CJSON_LIBDIR/cmake/cJSON/cjson.cmake"
    "$CJSON_LIBDIR/cmake/cJSON/cjson_utils.cmake"
  )

  dpkg-query -W -f='${Status}\n' libcjson1 | grep -Fx 'install ok installed' >/dev/null \
    || die "libcjson1 is not installed"
  dpkg-query -W -f='${Status}\n' libcjson-dev | grep -Fx 'install ok installed' >/dev/null \
    || die "libcjson-dev is not installed"

  mapfile -t runtime_matches < <(compgen -G "$CJSON_LIBDIR/libcjson.so.1*")
  mapfile -t utils_matches < <(compgen -G "$CJSON_LIBDIR/libcjson_utils.so.1*")

  [[ "${#runtime_matches[@]}" -gt 0 ]] || die "runtime package did not install libcjson.so.1* under $CJSON_LIBDIR"
  [[ "${#utils_matches[@]}" -gt 0 ]] || die "runtime package did not install libcjson_utils.so.1* under $CJSON_LIBDIR"

  for path in "${runtime_matches[@]}" "${utils_matches[@]}"; do
    [[ -e "$path" ]] || die "missing runtime package path: $path"
    assert_owned_by_package libcjson1 "$path"
  done

  for path in "${dev_paths[@]}"; do
    [[ -e "$path" ]] || die "missing development package path: $path"
    assert_owned_by_package libcjson-dev "$path"
  done

  [[ -L "$CJSON_LIBDIR/libcjson.so" ]] || die "libcjson-dev did not install libcjson.so as a symlink"
  [[ -L "$CJSON_LIBDIR/libcjson_utils.so" ]] || die "libcjson-dev did not install libcjson_utils.so as a symlink"
  [[ -L "$CJSON_LIBDIR/libcjson.so.1" ]] || die "libcjson1 did not install libcjson.so.1 as a symlink"
  [[ -L "$CJSON_LIBDIR/libcjson_utils.so.1" ]] || die "libcjson1 did not install libcjson_utils.so.1 as a symlink"

  pkg-config --cflags libcjson | grep -F -- '-I/usr/include/cjson' >/dev/null \
    || die "pkg-config did not advertise /usr/include/cjson for libcjson"
  pkg-config --libs libcjson | grep -F -- '-lcjson' >/dev/null \
    || die "pkg-config did not advertise -lcjson"
}

build_and_install_safe_cjson_packages() {
  local build_work="/tmp/cjson-deb-build"
  local artifact_dir=""
  local debs=()

  log "Building and installing packaged safe cJSON"
  rm -rf "$build_work"
  if ! "$ROOT/safe/scripts/build-debs.sh" "$build_work" >/tmp/cjson-build-debs.log 2>&1; then
    cat /tmp/cjson-build-debs.log >&2
    return 1
  fi

  artifact_dir="$(tail -n1 /tmp/cjson-build-debs.log)"
  [[ -d "$artifact_dir" ]] || die "safe package builder did not report a valid artifact directory"

  mapfile -t debs < <(find "$artifact_dir" -maxdepth 1 -type f -name '*.deb' | sort)
  [[ "${#debs[@]}" -gt 0 ]] || die "safe package builder did not produce any .deb artifacts"

  run_logged /tmp/cjson-package-install.log dpkg -i "${debs[@]}"
  ldconfig
  assert_safe_packages_installed
}

resolve_cjson_paths() {
  local target="$1"

  ldd "$target" 2>/dev/null | awk '/libcjson(_utils)?\.so/ && $3 ~ /^\// { print $3 }'
}

assert_links_to_packaged_safe() {
  local target="$1"
  local resolved_paths=()
  local canonical_path=""
  local path=""

  [[ -e "$target" ]] || die "missing binary or library to inspect: $target"
  mapfile -t resolved_paths < <(resolve_cjson_paths "$target")

  [[ "${#resolved_paths[@]}" -gt 0 ]] || {
    echo "expected $target to resolve libcjson from the packaged safe library" >&2
    ldd "$target" >&2 || true
    return 1
  }

  for path in "${resolved_paths[@]}"; do
    canonical_path="$(readlink -f "$path")"
    [[ "$canonical_path" == /usr/lib/*/libcjson.so* || "$canonical_path" == /usr/lib/*/libcjson_utils.so* || \
       "$canonical_path" == /lib/*/libcjson.so* || "$canonical_path" == /lib/*/libcjson_utils.so* ]] || {
      echo "expected $target to resolve libcjson from the packaged library paths, found $path" >&2
      return 1
    }
    assert_owned_by_package libcjson1 "$path"
  done
}

prepare_tester_user() {
  if ! id tester >/dev/null 2>&1; then
    useradd -m -s /bin/bash tester
  fi
  mkdir -p /home/tester
  chown -R tester:tester /home/tester
}

extract_first_json_from_log() {
  local path="$1"

  python3 - "$path" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
    start = line.find("{")
    if start == -1:
        continue
    candidate = line[start:]
    try:
        json.loads(candidate)
    except json.JSONDecodeError:
        continue
    print(candidate)
    raise SystemExit(0)

raise SystemExit(f"no JSON object found in {path}")
PY
}

assert_json_expr_from_log() {
  local path="$1"
  local expr="$2"

  extract_first_json_from_log "$path" | jq -e "$expr" >/dev/null
}

run_librist_runtime_smoke() {
  local local_rx_pid=0
  local local_tx_pid=0

  cleanup() {
    if [[ "$local_rx_pid" != "0" ]]; then
      kill "$local_rx_pid" 2>/dev/null || true
      wait "$local_rx_pid" 2>/dev/null || true
    fi
    if [[ "$local_tx_pid" != "0" ]]; then
      kill "$local_tx_pid" 2>/dev/null || true
      wait "$local_tx_pid" 2>/dev/null || true
    fi
  }

  trap cleanup EXIT

  ristreceiver -i rist://127.0.0.1:9200 -o udp://127.0.0.1:9201 -S 100 -v 6 >/tmp/librist-receiver.log 2>&1 &
  local_rx_pid="$!"
  ristsender -i udp://127.0.0.1:9202 -o rist://127.0.0.1:9200 -S 100 -v 6 >/tmp/librist-sender.log 2>&1 &
  local_tx_pid="$!"

  sleep 1
  python3 - <<'PY'
import socket
import time

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
for index in range(200):
    sock.sendto(f"packet-{index:03d}".encode("ascii"), ("127.0.0.1", 9202))
    time.sleep(0.005)
PY
  sleep 2
  cleanup
  trap - EXIT
}

run_mosquitto_runtime_smoke() {
  local broker_pid=0
  local sub_pid=0

  cleanup() {
    if [[ "$sub_pid" != "0" ]]; then
      kill "$sub_pid" 2>/dev/null || true
      wait "$sub_pid" 2>/dev/null || true
    fi
    if [[ "$broker_pid" != "0" ]]; then
      kill "$broker_pid" 2>/dev/null || true
      wait "$broker_pid" 2>/dev/null || true
    fi
  }

  trap cleanup EXIT

  cat > /tmp/mosquitto.conf <<'EOF'
listener 18883 127.0.0.1
allow_anonymous false
user root
plugin /usr/lib/x86_64-linux-gnu/mosquitto_dynamic_security.so
plugin_opt_config_file /tmp/mosquitto-dynsec.json
EOF

  mosquitto_ctrl dynsec init /tmp/mosquitto-dynsec.json admin secret >/tmp/mosquitto-dynsec-init.log
  chmod 0666 /tmp/mosquitto-dynsec.json
  mosquitto -c /tmp/mosquitto.conf >/tmp/mosquitto.log 2>&1 &
  broker_pid="$!"

  for _ in $(seq 1 100); do
    nc -z 127.0.0.1 18883 && break
    sleep 0.1
  done

  mosquitto_ctrl -h 127.0.0.1 -p 18883 -u admin -P secret dynsec createClient app -p apppass >/tmp/mosquitto-dynsec-client.log
  mosquitto_ctrl -h 127.0.0.1 -p 18883 -u admin -P secret dynsec createRole pubsub >/tmp/mosquitto-dynsec-role.log
  mosquitto_ctrl -h 127.0.0.1 -p 18883 -u admin -P secret dynsec addRoleACL pubsub publishClientSend smoke/json allow >/tmp/mosquitto-dynsec-acl-send.log
  mosquitto_ctrl -h 127.0.0.1 -p 18883 -u admin -P secret dynsec addRoleACL pubsub publishClientReceive smoke/json allow >/tmp/mosquitto-dynsec-acl-recv.log
  mosquitto_ctrl -h 127.0.0.1 -p 18883 -u admin -P secret dynsec addRoleACL pubsub subscribeLiteral smoke/json allow >/tmp/mosquitto-dynsec-acl-sub.log
  mosquitto_ctrl -h 127.0.0.1 -p 18883 -u admin -P secret dynsec addClientRole app pubsub >/tmp/mosquitto-dynsec-client-role.log

  mosquitto_sub -h 127.0.0.1 -p 18883 -u app -P apppass -t smoke/json -F '%j' -C 1 >/tmp/mosquitto-sub.json &
  sub_pid="$!"
  sleep 0.5
  mosquitto_pub -h 127.0.0.1 -p 18883 -u app -P apppass -t smoke/json -m 'hello'
  wait "$sub_pid"
  sub_pid=0
  sleep 0.5

  kill "$broker_pid"
  wait "$broker_pid" || true
  broker_pid=0

  mosquitto -c /tmp/mosquitto.conf >/tmp/mosquitto-restart.log 2>&1 &
  broker_pid="$!"
  for _ in $(seq 1 100); do
    nc -z 127.0.0.1 18883 && break
    sleep 0.1
  done

  mosquitto_sub -h 127.0.0.1 -p 18883 -u app -P apppass -t smoke/json -C 1 >/tmp/mosquitto-sub-restart.out &
  sub_pid="$!"
  sleep 0.5
  mosquitto_pub -h 127.0.0.1 -p 18883 -u app -P apppass -t smoke/json -m 'persisted'
  wait "$sub_pid"
  sub_pid=0
  cleanup
  trap - EXIT
}

run_pgagroal_runtime_smoke() {
  cleanup() {
    kill "$(cat /home/tester/pgagroal/server.pid)" 2>/dev/null || true
  }

  runuser -u tester -- bash -lc \
    "pgagroal -c /home/tester/pgagroal/pgagroal.conf -a /home/tester/pgagroal/pgagroal_hba.conf >/home/tester/pgagroal/server.log 2>&1 & echo \$! >/home/tester/pgagroal/server.pid"
  trap cleanup EXIT

  for _ in $(seq 1 100); do
    [[ -S /home/tester/pgagroal/run/.s.pgagroal.2345 ]] && break
    sleep 0.1
  done

  runuser -u tester -- pgagroal-cli -c /home/tester/pgagroal/pgagroal.conf ping -F json >/tmp/pgagroal-ping.json
  runuser -u tester -- pgagroal-cli -c /home/tester/pgagroal/pgagroal.conf status -F json >/tmp/pgagroal-status.json
  runuser -u tester -- pgagroal-cli -c /home/tester/pgagroal/pgagroal.conf conf ls -F json >/tmp/pgagroal-conf-ls.json
  cleanup
  trap - EXIT
}

test_freerdp3() {
  local src=""
  local build_dir="/tmp/build-freerdp3"
  local lib_path=""
  local sfreerdp_bin=""

  should_run freerdp3 || return 0

  with_failure_context freerdp3 package-install "installing build dependencies" install_build_deps freerdp3
  set_failure_context freerdp3 package-install "fetching source package"
  src="$(fetch_source freerdp3)"
  clear_failure_context

  log "freerdp3: building AAD core and SDL client"
  rm -rf "$build_dir"
  with_failure_context freerdp3 compile-time "configuring CMake build" run_logged /tmp/freerdp3-configure.log \
    cmake -S "$src" -B "$build_dir" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_TESTING=OFF \
      -DWITH_AAD=ON \
      -DWITH_MANPAGES=OFF \
      -DWITH_SERVER=OFF \
      -DWITH_PROXY=OFF \
      -DWITH_SHADOW=OFF \
      -DWITH_X11=OFF \
      -DWITH_WAYLAND=OFF \
      -DWITH_CLIENT_SDL=ON \
      -DWITH_CUPS=OFF \
      -DWITH_FUSE=OFF \
      -DWITH_PULSE=OFF \
      -DWITH_ALSA=OFF
  with_failure_context freerdp3 compile-time "building freerdp and sfreerdp" \
    run_logged /tmp/freerdp3-build.log cmake --build "$build_dir" --target freerdp sfreerdp

  sfreerdp_bin="$(find "$build_dir" -path '*/sfreerdp' -type f | head -n1)"
  [[ -n "$sfreerdp_bin" ]] || die "freerdp3 SDL client was not built"
  lib_path="$(find "$build_dir/libfreerdp" -maxdepth 1 -name 'libfreerdp3.so*' | head -n1)"
  [[ -n "$lib_path" ]] || die "freerdp3 core library was not built"
  with_failure_context freerdp3 link-time "verifying SDL client linkage to packaged libcjson" \
    assert_links_to_packaged_safe "$sfreerdp_bin"
  with_failure_context freerdp3 link-time "verifying libfreerdp linkage to packaged libcjson" \
    assert_links_to_packaged_safe "$lib_path"
}

test_librist() {
  should_run librist || return 0

  log "librist: exercising sender statistics JSON output through rist-tools"
  with_failure_context librist package-install "installing rist-tools package" install_packages rist-tools
  with_failure_context librist link-time "verifying ristreceiver linkage to packaged libcjson" \
    assert_links_to_packaged_safe "$(command -v ristreceiver)"

  with_failure_context librist runtime-semantic "running sender/receiver stats JSON smoke" \
    run_librist_runtime_smoke

  with_failure_context librist runtime-semantic "checking sender stats JSON marker" \
    grep -F '"sender-stats"' /tmp/librist-sender.log >/dev/null

  with_failure_context librist runtime-semantic "validating sender stats JSON payload" \
    assert_json_expr_from_log /tmp/librist-sender.log '."sender-stats".peer.stats.sent >= 1'
}

test_monado() {
  local src=""
  local build_dir="/tmp/build-monado"
  local runtime_smoke="$build_dir/tests/monado_json_smoke"
  local cli_bin="$build_dir/src/xrt/targets/cli/monado-cli"
  local gui_bin="$build_dir/src/xrt/targets/gui/monado-gui"
  local service_bin="$build_dir/src/xrt/targets/service/monado-service"

  should_run monado || return 0

  with_failure_context monado package-install "installing build dependencies" install_build_deps monado
  set_failure_context monado package-install "fetching source package"
  src="$(fetch_source monado)"
  clear_failure_context

  log "monado: building runtime binaries and exercising Vive/config/calibration/GUI JSON handling"
  cat > "$src/tests/tests_monado_runtime_json.cpp" <<'EOF'
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <string>

#include "tracking/t_tracking.h"
#include "util/u_config_json.h"
#include "vive/vive_config.h"

namespace {

void
check(bool condition, const char *message)
{
  if (!condition) {
    std::cerr << message << std::endl;
    std::exit(1);
  }
}

bool
approx(double left, double right, double epsilon = 1e-6)
{
  return std::fabs(left - right) <= epsilon;
}

} // namespace

int
main()
{
  namespace fs = std::filesystem;

  const fs::path config_home = "/tmp/monado-config-home";
  const fs::path calibration_path = "/tmp/monado-calibration.json";

  fs::remove_all(config_home);
  fs::create_directories(config_home);
  std::remove(calibration_path.c_str());
  check(setenv("XDG_CONFIG_HOME", config_home.c_str(), 1) == 0, "failed to set XDG_CONFIG_HOME");

  std::string vive_json = R"json(
{
  "model_number": "Vive MV",
  "acc_bias": [1.0, 2.0, 3.0],
  "acc_scale": [1.1, 1.2, 1.3],
  "gyro_bias": [0.1, 0.2, 0.3],
  "gyro_scale": [0.4, 0.5, 0.6],
  "mb_serial_number": "MB-123",
  "device_serial_number": "LHR-123",
  "lens_separation": 0.063,
  "device": {
    "persistence": 0.11,
    "physical_aspect_x_over_y": 0.91,
    "eye_target_height_in_pixels": 1201,
    "eye_target_width_in_pixels": 1099
  }
}
)json";
  struct vive_config vive = {};
  check(vive_config_parse(&vive, vive_json.data(), U_LOGGING_INFO), "vive_config_parse failed");
  check(vive.variant == VIVE_VARIANT_VIVE, "vive variant was not parsed");
  check(vive.display.eye_target_width_in_pixels == 1099, "vive display width was not parsed");
  check(vive.display.eye_target_height_in_pixels == 1201, "vive display height was not parsed");
  check(approx(vive.imu.acc_bias.x, 1.0) && approx(vive.imu.gyro_scale.z, 0.6),
        "vive IMU vectors were not parsed");
  vive_config_teardown(&vive);

  struct xrt_settings_tracking settings = {};
  std::snprintf(settings.camera_name, sizeof(settings.camera_name), "%s", "StereoCam");
  settings.camera_mode = 7;
  settings.camera_type = XRT_SETTINGS_CAMERA_TYPE_REGULAR_SBS;
  std::snprintf(settings.calibration_path, sizeof(settings.calibration_path), "%s", calibration_path.c_str());

  struct u_config_json config_json = {};
  u_config_json_open_or_create_main_file(&config_json);
  u_config_json_save_calibration(&config_json, &settings);
  u_config_json_close(&config_json);

  struct xrt_settings_tracking loaded_settings = {};
  u_config_json_open_or_create_main_file(&config_json);
  check(u_config_json_get_tracking_settings(&config_json, &loaded_settings),
        "u_config_json_get_tracking_settings failed");
  check(std::strcmp(loaded_settings.camera_name, "StereoCam") == 0,
        "tracking camera_name was not persisted");
  check(loaded_settings.camera_mode == 7, "tracking camera_mode was not persisted");
  check(loaded_settings.camera_type == XRT_SETTINGS_CAMERA_TYPE_REGULAR_SBS,
        "tracking camera_type was not persisted");
  check(std::strcmp(loaded_settings.calibration_path, calibration_path.c_str()) == 0,
        "tracking calibration_path was not persisted");
  u_config_json_close(&config_json);

  struct t_stereo_camera_calibration *stereo = nullptr;
  t_stereo_camera_calibration_alloc(&stereo, T_DISTORTION_OPENCV_RADTAN_5);
  check(stereo != nullptr, "t_stereo_camera_calibration_alloc failed");
  stereo->view[0].image_size_pixels.w = 640;
  stereo->view[0].image_size_pixels.h = 480;
  stereo->view[1].image_size_pixels.w = 640;
  stereo->view[1].image_size_pixels.h = 480;
  stereo->view[0].intrinsics[0][0] = 1000.0;
  stereo->view[0].intrinsics[1][1] = 1001.0;
  stereo->view[0].intrinsics[0][2] = 320.0;
  stereo->view[0].intrinsics[1][2] = 240.0;
  stereo->view[0].intrinsics[2][2] = 1.0;
  stereo->view[1].intrinsics[0][0] = 1002.0;
  stereo->view[1].intrinsics[1][1] = 1003.0;
  stereo->view[1].intrinsics[0][2] = 321.0;
  stereo->view[1].intrinsics[1][2] = 241.0;
  stereo->view[1].intrinsics[2][2] = 1.0;
  stereo->view[0].rt5.k1 = 0.11;
  stereo->view[0].rt5.k2 = 0.12;
  stereo->view[0].rt5.p1 = 0.13;
  stereo->view[0].rt5.p2 = 0.14;
  stereo->view[0].rt5.k3 = 0.15;
  stereo->view[1].rt5.k1 = 0.21;
  stereo->view[1].rt5.k2 = 0.22;
  stereo->view[1].rt5.p1 = 0.23;
  stereo->view[1].rt5.p2 = 0.24;
  stereo->view[1].rt5.k3 = 0.25;
  stereo->camera_translation[0] = 0.1;
  stereo->camera_translation[1] = 0.2;
  stereo->camera_translation[2] = 0.3;
  stereo->camera_rotation[0][0] = 1.0;
  stereo->camera_rotation[1][1] = 1.0;
  stereo->camera_rotation[2][2] = 1.0;
  stereo->camera_essential[0][0] = 1.0;
  stereo->camera_essential[1][1] = 1.0;
  stereo->camera_essential[2][2] = 1.0;
  stereo->camera_fundamental[0][0] = 1.0;
  stereo->camera_fundamental[1][1] = 1.0;
  stereo->camera_fundamental[2][2] = 1.0;

  check(t_stereo_camera_calibration_save(calibration_path.c_str(), stereo),
        "t_stereo_camera_calibration_save failed");
  struct t_stereo_camera_calibration *loaded_stereo = nullptr;
  check(t_stereo_camera_calibration_load(calibration_path.c_str(), &loaded_stereo),
        "t_stereo_camera_calibration_load failed");
  check(loaded_stereo != nullptr, "loaded stereo calibration was null");
  check(loaded_stereo->view[0].image_size_pixels.w == 640,
        "stereo calibration width was not persisted");
  check(approx(loaded_stereo->camera_translation[0], 0.1),
        "stereo calibration translation was not persisted");

  struct t_calibration_params params = {};
  t_calibration_gui_params_default(&params);
  params.use_fisheye = true;
  params.mirror_rgb_image = true;
  params.pattern = T_BOARD_ASYMMETRIC_CIRCLES;
  params.load.enabled = true;
  params.load.num_images = 11;
  params.asymmetric_circles.cols = 4;
  params.asymmetric_circles.rows = 11;
  params.asymmetric_circles.diagonal_distance_meters = 0.031f;

  cJSON *scene = nullptr;
  t_calibration_gui_params_to_json(&scene, &params);
  check(scene != nullptr, "t_calibration_gui_params_to_json failed");

  struct u_config_json gui_json = {};
  u_gui_state_open_file(&gui_json);
  u_gui_state_save_scene(&gui_json, GUI_STATE_SCENE_CALIBRATE, scene);
  u_config_json_close(&gui_json);

  struct t_calibration_params loaded_params = {};
  t_calibration_gui_params_default(&loaded_params);
  u_gui_state_open_file(&gui_json);
  cJSON *saved_scene = u_gui_state_get_scene(&gui_json, GUI_STATE_SCENE_CALIBRATE);
  gui_json.root = nullptr;
  check(saved_scene != nullptr, "saved GUI calibration scene was missing");
  t_calibration_gui_params_parse_from_json(saved_scene, &loaded_params);
  cJSON_Delete(saved_scene);
  check(loaded_params.use_fisheye, "GUI calibration fisheye flag was not persisted");
  check(loaded_params.mirror_rgb_image, "GUI calibration mirror flag was not persisted");
  check(loaded_params.pattern == T_BOARD_ASYMMETRIC_CIRCLES,
        "GUI calibration pattern was not persisted");
  check(loaded_params.load.enabled && loaded_params.load.num_images == 11,
        "GUI calibration load state was not persisted");
  check(approx(loaded_params.asymmetric_circles.diagonal_distance_meters, 0.031f),
        "GUI calibration circle spacing was not persisted");

  t_stereo_camera_calibration_reference(&loaded_stereo, nullptr);
  t_stereo_camera_calibration_reference(&stereo, nullptr);
  std::cout << "monado-json-ok" << std::endl;
  return 0;
}
EOF
  cat >> "$src/tests/CMakeLists.txt" <<'EOF'

add_executable(monado_json_smoke tests_monado_runtime_json.cpp)
target_link_libraries(monado_json_smoke PRIVATE aux_vive aux_tracking aux_util)
EOF
  rm -rf "$build_dir"
  with_failure_context monado compile-time "configuring CMake build" run_logged /tmp/monado-configure.log \
    cmake -S "$src" -B "$build_dir" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_TESTING=ON \
      -DXRT_HAVE_SYSTEM_CJSON=ON \
      -DXRT_BUILD_DRIVER_ANDROID=OFF \
      -DXRT_BUILD_DRIVER_ARDUINO=OFF \
      -DXRT_BUILD_DRIVER_DAYDREAM=OFF \
      -DXRT_BUILD_DRIVER_DEPTHAI=OFF \
      -DXRT_BUILD_DRIVER_EUROC=OFF \
      -DXRT_BUILD_DRIVER_HANDTRACKING=OFF \
      -DXRT_BUILD_DRIVER_HDK=OFF \
      -DXRT_BUILD_DRIVER_HYDRA=OFF \
      -DXRT_BUILD_DRIVER_ILLIXR=OFF \
      -DXRT_BUILD_DRIVER_NS=OFF \
      -DXRT_BUILD_DRIVER_OHMD=OFF \
      -DXRT_BUILD_DRIVER_OPENGLOVES=OFF \
      -DXRT_BUILD_DRIVER_PSMV=OFF \
      -DXRT_BUILD_DRIVER_PSVR=OFF \
      -DXRT_BUILD_DRIVER_REALSENSE=OFF \
      -DXRT_BUILD_DRIVER_REMOTE=OFF \
      -DXRT_BUILD_DRIVER_RIFT_S=OFF \
      -DXRT_BUILD_DRIVER_SIMULAVR=OFF \
      -DXRT_BUILD_DRIVER_SIMULATED=OFF \
      -DXRT_BUILD_DRIVER_SURVIVE=OFF \
      -DXRT_BUILD_DRIVER_TWRAP=OFF \
      -DXRT_BUILD_DRIVER_ULV2=OFF \
      -DXRT_BUILD_DRIVER_VF=OFF \
      -DXRT_BUILD_DRIVER_WMR=OFF
  with_failure_context monado compile-time "building runtime targets and JSON smoke" run_logged /tmp/monado-build.log \
    cmake --build "$build_dir" --target monado_json_smoke monado-cli monado-gui monado-service

  set_failure_context monado compile-time "checking built runtime artifacts"
  test -x "$runtime_smoke" || die "monado runtime JSON smoke binary was not built"
  test -x "$cli_bin" || die "monado-cli was not built"
  test -x "$gui_bin" || die "monado-gui was not built"
  test -x "$service_bin" || die "monado-service was not built"
  clear_failure_context
  with_failure_context monado link-time "verifying monado JSON smoke linkage" \
    assert_links_to_packaged_safe "$runtime_smoke"
  with_failure_context monado link-time "verifying monado-cli linkage" \
    assert_links_to_packaged_safe "$cli_bin"
  with_failure_context monado link-time "verifying monado-gui linkage" \
    assert_links_to_packaged_safe "$gui_bin"
  with_failure_context monado link-time "verifying monado-service linkage" \
    assert_links_to_packaged_safe "$service_bin"
  with_failure_context monado runtime-semantic "running monado JSON smoke" \
    run_logged /tmp/monado-runtime-smoke.log "$runtime_smoke"
  with_failure_context monado runtime-semantic "checking monado JSON smoke sentinel" \
    grep -Fx 'monado-json-ok' /tmp/monado-runtime-smoke.log >/dev/null
}

test_mosquitto() {
  local dynsec_plugin="/usr/lib/x86_64-linux-gnu/mosquitto_dynamic_security.so"

  should_run mosquitto || return 0

  log "mosquitto: exercising dynamic-security JSON persistence and mosquitto_sub JSON formatting"
  with_failure_context mosquitto package-install "installing mosquitto packages" \
    install_packages mosquitto mosquitto-clients
  with_failure_context mosquitto link-time "verifying mosquitto_sub linkage to packaged libcjson" \
    assert_links_to_packaged_safe "$(command -v mosquitto_sub)"
  set_failure_context mosquitto package-install "checking dynamic-security plugin installation"
  test -f "$dynsec_plugin" || die "mosquitto dynamic-security plugin was not installed"
  clear_failure_context
  with_failure_context mosquitto link-time "verifying dynamic-security plugin linkage to packaged libcjson" \
    assert_links_to_packaged_safe "$dynsec_plugin"

  with_failure_context mosquitto runtime-semantic "running broker persistence and JSON formatting smoke" \
    run_mosquitto_runtime_smoke

  with_failure_context mosquitto runtime-semantic "validating mosquitto_sub JSON payload" \
    jq -e '.topic == "smoke/json" and .payload == "hello" and .payloadlen == 5' /tmp/mosquitto-sub.json >/dev/null
  with_failure_context mosquitto runtime-semantic "checking restarted broker persistence output" \
    grep -Fx 'persisted' /tmp/mosquitto-sub-restart.out >/dev/null
}

test_ocp() {
  local src=""
  local binary=""
  local lib_path=""

  should_run ocp || return 0

  with_failure_context ocp package-install "installing build dependencies" install_build_deps ocp
  set_failure_context ocp package-install "fetching source package"
  src="$(fetch_source ocp)"
  clear_failure_context

  log "ocp: building ncurses variant from source"
  with_failure_context ocp compile-time "configuring ncurses build" run_bash_logged /tmp/ocp-configure.log "
    cd '$src'
    ./configure \
      --prefix=/usr \
      --exec-prefix=/usr \
      --mandir=\${prefix}/share/man \
      --sysconfdir=/etc \
      --datadir=\${prefix}/share \
      --libdir=\${prefix}/lib \
      --bindir=\${prefix}/bin \
      --infodir=\${prefix}/share/info \
      --without-x11 \
      --with-dir-suffix= \
      --with-ncurses \
      --with-adplug \
      --without-update-mime-database \
      --without-update-desktop-database
  "
  with_failure_context ocp compile-time "building ncurses variant" \
    run_bash_logged /tmp/ocp-build.log "cd '$src' && make -j'$(nproc)'"

  lib_path="$src/libocp.so"
  set_failure_context ocp compile-time "checking libocp build output"
  test -f "$lib_path" || die "ocp build did not produce libocp.so"
  clear_failure_context
  with_failure_context ocp link-time "verifying libocp linkage to packaged libcjson" \
    assert_links_to_packaged_safe "$lib_path"

  log "ocp: exercising cached MusicBrainz JSON parsing through musicbrainz.c"
  with_failure_context ocp compile-time "building MusicBrainz JSON smoke" run_bash_logged /tmp/ocp-musicbrainz-build.log "
    cd '$src'
    cat > /tmp/ocp-musicbrainz-smoke.c <<'EOF'
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <cJSON.h>

#include \"filesel/musicbrainz.c\"

void *ocpPipeProcess_create(const char * const commandLine[]) {
  (void)commandLine;
  return NULL;
}

int main(void) {
  static const char discid[] = \"0123456789ABCDEFGHIJKLMNAB\";
  static const char toc[] = \"1 1 150\";
  static const char payload[] =
      \"{\\\"releases\\\":[{\\\"title\\\":\\\"Test Album\\\",\\\"date\\\":\\\"2024-03-14\\\",\\\"artist-credit\\\":[{\\\"name\\\":\\\"Test Artist\\\"}],\\\"media\\\":[{\\\"tracks\\\":[{\\\"number\\\":\\\"1\\\",\\\"title\\\":\\\"First Track\\\",\\\"recording\\\":{\\\"first-release-date\\\":\\\"2024-03-15\\\"},\\\"artist-credit\\\":[{\\\"name\\\":\\\"Track Artist\\\"},{\\\"joinphrase\\\":\\\" feat. \\\"},{\\\"name\\\":\\\"Guest\\\"}]}]}]}]}\";
  struct musicbrainz_database_h *result = NULL;
  struct musicbrainz_database_h *direct = NULL;
  void *token = NULL;
  cJSON *root = NULL;
  cJSON *releases = NULL;
  cJSON *release = NULL;
  size_t payload_len = strlen(payload);

  musicbrainz.cache = calloc(1, sizeof(*musicbrainz.cache));
  if (musicbrainz.cache == NULL) {
    fprintf(stderr, \"musicbrainz cache allocation failed\\n\");
    return 1;
  }
  musicbrainz.cachesize = 1;
  musicbrainz.cachecount = 1;
  memcpy(musicbrainz.cache[0].discid, discid, sizeof(discid));
  musicbrainz.cache[0].lastscan = (uint64_t)time(NULL);
  musicbrainz.cache[0].size = (uint32_t)payload_len | SIZE_VALID;
  musicbrainz.cache[0].data = malloc(payload_len + 1);
  if (musicbrainz.cache[0].data == NULL) {
    fprintf(stderr, \"musicbrainz cache payload allocation failed\\n\");
    free(musicbrainz.cache);
    musicbrainz.cache = NULL;
    return 2;
  }
  memcpy(musicbrainz.cache[0].data, payload, payload_len + 1);

  token = musicbrainz_lookup_discid_init(discid, toc, &result);
  if (token != NULL) {
    fprintf(stderr, \"expected a cache hit, but musicbrainz queued a lookup\\n\");
    return 3;
  }
  if (result == NULL) {
    fprintf(stderr, \"MusicBrainz cache lookup produced no metadata\\n\");
    return 4;
  }

  if (strcmp(result->album, \"Test Album\") != 0 ||
      strcmp(result->artist[0], \"Test Artist\") != 0 ||
      strcmp(result->title[1], \"First Track\") != 0 ||
      strcmp(result->artist[1], \"Track Artist feat. Guest\") != 0 ||
      result->date[0] != ((2024u << 16) | (3u << 8) | 14u) ||
      result->date[1] != ((2024u << 16) | (3u << 8) | 15u)) {
    fprintf(stderr, \"unexpected cached MusicBrainz metadata was parsed\\n\");
    return 5;
  }

  root = cJSON_Parse(payload);
  if (root == NULL) {
    fprintf(stderr, \"failed to parse MusicBrainz JSON payload\\n\");
    return 6;
  }
  releases = cJSON_GetObjectItem(root, \"releases\");
  release = cJSON_GetArrayItem(releases, 0);
  if (!cJSON_IsObject(release)) {
    fprintf(stderr, \"MusicBrainz JSON payload did not contain a release\\n\");
    return 7;
  }
  musicbrainz_parse_release(release, &direct);
  if (direct == NULL) {
    fprintf(stderr, \"musicbrainz_parse_release did not produce metadata\\n\");
    return 8;
  }
  if (strcmp(direct->album, \"Test Album\") != 0 ||
      strcmp(direct->artist[1], \"Track Artist feat. Guest\") != 0) {
    fprintf(stderr, \"unexpected direct MusicBrainz parsing output\\n\");
    return 9;
  }

  puts(result->album);
  puts(result->title[1]);
  puts(direct->artist[1]);
  musicbrainz_database_h_free(result);
  musicbrainz_database_h_free(direct);
  cJSON_Delete(root);
  free(musicbrainz.cache[0].data);
  free(musicbrainz.cache);
  return 0;
}
EOF
    cc \$(pkg-config --cflags libcjson) -ffunction-sections -fdata-sections -I'$src' \
      /tmp/ocp-musicbrainz-smoke.c \
      \$(pkg-config --libs libcjson) -Wl,--gc-sections -o /tmp/ocp-musicbrainz-smoke
  "
  with_failure_context ocp link-time "verifying MusicBrainz smoke linkage" \
    assert_links_to_packaged_safe /tmp/ocp-musicbrainz-smoke
  with_failure_context ocp runtime-semantic "running MusicBrainz JSON smoke" \
    run_logged /tmp/ocp-musicbrainz.log /tmp/ocp-musicbrainz-smoke
  with_failure_context ocp runtime-semantic "checking parsed album title" \
    grep -Fx 'Test Album' /tmp/ocp-musicbrainz.log >/dev/null
  with_failure_context ocp runtime-semantic "checking parsed track title" \
    grep -Fx 'First Track' /tmp/ocp-musicbrainz.log >/dev/null
  with_failure_context ocp runtime-semantic "checking parsed artist joinphrase" \
    grep -Fx 'Track Artist feat. Guest' /tmp/ocp-musicbrainz.log >/dev/null

  if [[ -x "$src/ocp-curses" ]]; then
    binary="$src/ocp-curses"
  elif [[ -x "$src/ocp" ]]; then
    binary="$src/ocp"
  else
    die "ocp build did not produce an executable"
  fi
  set_failure_context ocp runtime-semantic "capturing help output"
  timeout 10 "$binary" --help >/tmp/ocp-help.log 2>&1 || true
  test -s /tmp/ocp-help.log || die "ocp help output was empty"
  clear_failure_context
}

test_oidc_agent() {
  local src=""
  local agent_bin=""
  local runtime_smoke="/tmp/oidc-json-smoke"

  should_run oidc-agent || return 0

  with_failure_context oidc-agent package-install "installing build dependencies" install_build_deps oidc-agent
  set_failure_context oidc-agent package-install "fetching source package"
  src="$(fetch_source oidc-agent)"
  clear_failure_context

  log "oidc-agent: building with shared libcjson and exercising device-code/account/config-updater JSON paths"
  with_failure_context oidc-agent compile-time "building oidc-agent with shared libcjson" run_bash_logged /tmp/oidc-agent-build.log \
    "cd '$src' && make USE_CJSON_SO=1 create_obj_dir_structure build"

  agent_bin="$src/bin/oidc-agent"
  set_failure_context oidc-agent compile-time "checking oidc-agent build output"
  test -x "$agent_bin" || die "oidc-agent binary was not built"
  clear_failure_context
  with_failure_context oidc-agent link-time "verifying oidc-agent linkage to packaged libcjson" \
    assert_links_to_packaged_safe "$agent_bin"

  cat > /tmp/oidc-json-smoke.c <<'EOF'
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "account/account.h"
#include "oidc-agent/oidc/device_code.h"
#include "utils/memory.h"
#include "utils/oidc_error.h"
#include "wrapper/list.h"

static void stub_log(int level, const char *fmt, ...) {
  (void)level;
  (void)fmt;
}

void logger(int level, const char *fmt, ...) {
  (void)level;
  (void)fmt;
}

void loggerTerminal(int level, const char *fmt, ...) {
  (void)level;
  (void)fmt;
}

void logger_open(const char *name) {
  (void)name;
}

int logger_setlogmask(int mask) {
  return mask;
}

int logger_setloglevel(int level) {
  return level;
}

void (*agent_log)(int, const char *, ...) = stub_log;

int printError(char *fmt, ...) {
  (void)fmt;
  return 0;
}

char *getHostName(void) {
  char *hostname = secAlloc(5);
  memcpy(hostname, "host", 5);
  return hostname;
}

oidc_error_t checkRedirectUrisForErrors(list_t *redirect_uris) {
  return (redirect_uris != NULL && redirect_uris->len > 0) ? OIDC_SUCCESS : OIDC_EERROR;
}

static char *captured = NULL;

oidc_error_t encryptAndWriteToOidcFile(const char *content, const char *shortname,
                                       const char *password, const char *gpg_key) {
  size_t len = strlen(content);
  (void)shortname;
  (void)password;
  (void)gpg_key;
  free(captured);
  captured = malloc(len + 1);
  memcpy(captured, content, len + 1);
  return OIDC_SUCCESS;
}

oidc_error_t _updateRT(char *file_content, const char *shortname,
                       const char *refresh_token, const char *password,
                       const char *gpg_key);

int main(void) {
  const char *device_json =
      "{\"device_code\":\"dev-123\",\"user_code\":\"ABCD-EFGH\",\"verification_url\":\"https://verify.example/device\",\"verification_url_complete\":\"https://verify.example/device?user_code=ABCD-EFGH\",\"expires_in\":600}";
  const char *account_json =
      "{\"name\":\"demo\",\"issuer_url\":\"https://issuer.example\",\"client_id\":\"cid\",\"client_secret\":\"secret\",\"username\":\"user\",\"password\":\"pw\",\"refresh_token\":\"old-refresh\",\"scope\":\"openid profile\",\"redirect_uris\":[\"http://localhost:4242/callback\"],\"device_authorization_endpoint\":\"https://issuer.example/device\",\"client_name\":\"Demo Client\",\"daeSetByUser\":1,\"audience\":\"api://default\"}";
  struct oidc_device_code *dc = getDeviceCodeFromJSON(device_json);
  struct oidc_device_code *roundtrip_dc = NULL;
  struct oidc_account *account = NULL;
  struct oidc_account *rendered_account = NULL;
  struct oidc_account *updated_account = NULL;
  list_t *accounts = NULL;
  char *loaded_accounts = NULL;
  char *rendered = NULL;
  char *dc_json = NULL;
  char *mutable_json = NULL;

  if (dc == NULL) {
    fprintf(stderr, "device code JSON did not parse\n");
    return 1;
  }
  if (strcmp(oidc_device_getVerificationUri(*dc), "https://verify.example/device") != 0 ||
      oidc_device_getInterval(*dc) != 5) {
    fprintf(stderr, "device code JSON fields were parsed incorrectly\n");
    return 2;
  }
  dc_json = deviceCodeToJSON(*dc);
  roundtrip_dc = getDeviceCodeFromJSON(dc_json);
  if (roundtrip_dc == NULL ||
      strcmp(oidc_device_getVerificationUri(*roundtrip_dc), "https://verify.example/device") != 0 ||
      oidc_device_getInterval(*roundtrip_dc) != 5) {
    fprintf(stderr, "device code JSON was not serialized correctly\n");
    return 3;
  }

  account = getAccountFromJSON(account_json);
  if (account == NULL) {
    fprintf(stderr, "account JSON did not parse\n");
    return 4;
  }

  accounts = list_new();
  list_rpush(accounts, list_node_new(account));
  loaded_accounts = getAccountNameList(accounts);
  list_destroy(accounts);
  accounts = NULL;
  if (loaded_accounts == NULL || strstr(loaded_accounts, "\"demo\"") == NULL) {
    fprintf(stderr, "loaded-account JSON was not serialized correctly\n");
    return 5;
  }

  rendered = accountToJSONString(account);
  rendered_account = getAccountFromJSON(rendered);
  if (rendered_account == NULL ||
      strcmp(account_getRefreshToken(rendered_account), "old-refresh") != 0 ||
      strcmp(account_getIssuerUrl(rendered_account), "https://issuer.example") != 0) {
    fprintf(stderr, "account JSON was not serialized correctly\n");
    return 6;
  }

  mutable_json = secAlloc(strlen(rendered) + 1);
  memcpy(mutable_json, rendered, strlen(rendered) + 1);
  if (_updateRT(mutable_json, "demo", "new-refresh", "pw", NULL) != OIDC_SUCCESS) {
    fprintf(stderr, "refresh-token updater failed\n");
    return 7;
  }
  updated_account = getAccountFromJSON(captured);
  if (updated_account == NULL ||
      strcmp(account_getRefreshToken(updated_account), "new-refresh") != 0) {
    fprintf(stderr, "refresh-token updater did not rewrite JSON correctly\n");
    return 8;
  }

  puts("oidc-json-ok");
  free(captured);
  secFree(loaded_accounts);
  secFree(rendered);
  secFree(dc_json);
  secFreeDeviceCode(roundtrip_dc);
  secFreeDeviceCode(dc);
  secFreeAccount(updated_account);
  secFreeAccount(rendered_account);
  secFreeAccount(account);
  return 0;
}
EOF
  with_failure_context oidc-agent compile-time "building oidc-agent JSON smoke" run_bash_logged /tmp/oidc-agent-runtime-smoke-build.log "
    cc -std=c99 -ffunction-sections -fdata-sections -DUSE_CJSON_SO \
      -I'$src/src' -I'$src/lib' \$(pkg-config --cflags libcjson) \
      /tmp/oidc-json-smoke.c \
      '$src/src/utils/memory.c' \
      '$src/src/utils/oidc_error.c' \
      '$src/src/utils/string/stringUtils.c' \
      '$src/src/utils/json.c' \
      '$src/src/utils/listUtils.c' \
      '$src/src/account/issuer.c' \
      '$src/src/account/issuer_helper.c' \
      '$src/src/account/setandget.c' \
      '$src/src/account/account.c' \
      '$src/src/oidc-agent/oidc/device_code.c' \
      '$src/src/oidc-agent/oidcp/config_updater.c' \
      '$src/lib/list/list.c' \
      '$src/lib/list/list_iterator.c' \
      '$src/lib/list/list_node.c' \
      \$(pkg-config --libs libcjson) -Wl,--gc-sections -o '$runtime_smoke'
  "

  with_failure_context oidc-agent link-time "verifying oidc-agent JSON smoke linkage" \
    assert_links_to_packaged_safe "$runtime_smoke"
  with_failure_context oidc-agent runtime-semantic "running oidc-agent JSON smoke" \
    run_logged /tmp/oidc-agent-runtime-smoke.log "$runtime_smoke"
  with_failure_context oidc-agent runtime-semantic "checking oidc-agent JSON smoke sentinel" \
    grep -Fx 'oidc-json-ok' /tmp/oidc-agent-runtime-smoke.log >/dev/null
}

test_pgagroal() {
  should_run pgagroal || return 0

  log "pgagroal: exercising JSON management commands"
  with_failure_context pgagroal package-install "installing pgagroal package" install_packages pgagroal
  prepare_tester_user
  with_failure_context pgagroal link-time "verifying pgagroal-cli linkage to packaged libcjson" \
    assert_links_to_packaged_safe "$(command -v pgagroal-cli)"

  mkdir -p /home/tester/pgagroal/run
  chown -R tester:tester /home/tester/pgagroal

  cat > /home/tester/pgagroal/pgagroal.conf <<'EOF'
[pgagroal]
host = localhost
port = 2345
log_type = console
log_level = info
log_path =
unix_socket_dir = /home/tester/pgagroal/run
max_connections = 10
validation = off

[primary]
host = 127.0.0.1
port = 5432
EOF

  cat > /home/tester/pgagroal/pgagroal_hba.conf <<'EOF'
host all all all all
EOF
  chown tester:tester /home/tester/pgagroal/pgagroal.conf /home/tester/pgagroal/pgagroal_hba.conf

  with_failure_context pgagroal runtime-semantic "running pgagroal management JSON smoke" \
    run_pgagroal_runtime_smoke

  with_failure_context pgagroal runtime-semantic "validating ping JSON response" \
    jq -e '.command.name == "ping" and .command.output.message == "running"' /tmp/pgagroal-ping.json >/dev/null
  with_failure_context pgagroal runtime-semantic "validating status JSON response" \
    jq -e '.command.name == "status" and .command.output.connections.max == 10' /tmp/pgagroal-status.json >/dev/null
  with_failure_context pgagroal runtime-semantic "validating conf ls JSON response" \
    jq -e '.command.name == "conf ls" and (.command.output.files.list | length) >= 2' /tmp/pgagroal-conf-ls.json >/dev/null
}

test_qad() {
  local src=""
  local build_dir="/tmp/build-qad"

  should_run qad || return 0

  with_failure_context qad package-install "installing build dependencies" install_build_deps qad
  set_failure_context qad package-install "fetching source package"
  src="$(fetch_source qad)"
  clear_failure_context

  log "qad: building the HTTP/JSON daemon and exercising REST JSON request parsing"
  rm -rf "$build_dir"
  with_failure_context qad compile-time "configuring Meson build" \
    run_logged /tmp/qad-setup.log meson setup "$build_dir" "$src" -Dbackend-ilm=false
  with_failure_context qad compile-time "building qad daemon" \
    run_logged /tmp/qad-build.log meson compile -C "$build_dir"

  set_failure_context qad compile-time "checking qad build output"
  test -x "$build_dir/qad" || die "qad binary was not built"
  clear_failure_context
  with_failure_context qad link-time "verifying qad linkage to packaged libcjson" \
    assert_links_to_packaged_safe "$build_dir/qad"
  with_failure_context qad runtime-semantic "capturing qad help output" \
    run_logged /tmp/qad-help.log "$build_dir/qad" --help
  with_failure_context qad runtime-semantic "checking qad help output" \
    grep -F -- '--port' /tmp/qad-help.log >/dev/null

  with_failure_context qad compile-time "building qad JSON smoke" run_bash_logged /tmp/qad-json-smoke-build.log "
    cat > /tmp/qad-json-smoke.c <<'EOF'
#include <stdio.h>
#include <string.h>
#include <backend.h>

struct MHD_Connection;
void qad_post_handler(struct MHD_Connection *connection, const char *url,
                      const char *post_data, int post_data_size,
                      qad_backend_t *backend, char *error);

static int last_move[3];
static int last_button[2];
static int last_touch[4];
static int last_swipe[6];

static int stub_move(int x, int y, int event) {
  last_move[0] = x;
  last_move[1] = y;
  last_move[2] = event;
  return 0;
}

static int stub_button(int value, int event) {
  last_button[0] = value;
  last_button[1] = event;
  return 0;
}

static int stub_touch(int x, int y, int duration, int event) {
  last_touch[0] = x;
  last_touch[1] = y;
  last_touch[2] = duration;
  last_touch[3] = event;
  return 0;
}

static int stub_swipe(int x, int y, int x2, int y2, int velocity, int event) {
  last_swipe[0] = x;
  last_swipe[1] = y;
  last_swipe[2] = x2;
  last_swipe[3] = y2;
  last_swipe[4] = velocity;
  last_swipe[5] = event;
  return 0;
}

qad_backend_input_t *create_input_backend(void) {
  return NULL;
}

qad_backend_screen_t *kms_create_backend(const char *kms_backend_card, const int kms_format_rgb) {
  (void)kms_backend_card;
  (void)kms_format_rgb;
  return NULL;
}

int main(void) {
  const char *move_json = \"{\\\"x\\\":12,\\\"y\\\":34,\\\"event\\\":1}\";
  const char *button_json = \"{\\\"value\\\":1,\\\"event\\\":0}\";
  const char *touch_json = \"{\\\"x\\\":10,\\\"y\\\":20,\\\"event\\\":1,\\\"duration\\\":5}\";
  const char *swipe_json = \"{\\\"x\\\":1,\\\"y\\\":2,\\\"x2\\\":3,\\\"y2\\\":4,\\\"event\\\":1,\\\"velocity\\\":9}\";
  const char *invalid_move_json = \"{\\\"x\\\":\\\"bad\\\"}\";
  qad_backend_input_t input = {0};
  qad_backend_t backend = {0};
  char error[255];

  input.move = stub_move;
  input.button = stub_button;
  input.touch = stub_touch;
  input.swipe = stub_swipe;
  backend.input_backend = &input;

  memset(error, 0, sizeof(error));
  qad_post_handler(NULL, \"/move\", move_json, (int)strlen(move_json), &backend, error);
  if (error[0] != '\\0' || last_move[0] != 12 || last_move[1] != 34 || last_move[2] != 1) {
    fprintf(stderr, \"move JSON was not parsed correctly\\n\");
    return 1;
  }

  memset(error, 0, sizeof(error));
  qad_post_handler(NULL, \"/button\", button_json, (int)strlen(button_json), &backend, error);
  if (error[0] != '\\0' || last_button[0] != 1 || last_button[1] != 0) {
    fprintf(stderr, \"button JSON was not parsed correctly\\n\");
    return 2;
  }

  memset(error, 0, sizeof(error));
  qad_post_handler(NULL, \"/touch\", touch_json, (int)strlen(touch_json), &backend, error);
  if (error[0] != '\\0' || last_touch[0] != 10 || last_touch[1] != 20 || last_touch[2] != 5 || last_touch[3] != 1) {
    fprintf(stderr, \"touch JSON was not parsed correctly\\n\");
    return 3;
  }

  memset(error, 0, sizeof(error));
  qad_post_handler(NULL, \"/swipe\", swipe_json, (int)strlen(swipe_json), &backend, error);
  if (error[0] != '\\0' || last_swipe[0] != 1 || last_swipe[1] != 2 || last_swipe[2] != 3 ||
      last_swipe[3] != 4 || last_swipe[4] != 9 || last_swipe[5] != 1) {
    fprintf(stderr, \"swipe JSON was not parsed correctly\\n\");
    return 4;
  }

  memset(error, 0, sizeof(error));
  qad_post_handler(NULL, \"/move\", invalid_move_json, (int)strlen(invalid_move_json), &backend, error);
  if (strstr(error, \"Coordinates\") == NULL) {
    fprintf(stderr, \"invalid move JSON did not produce the expected validation error\\n\");
    return 5;
  }

  puts(\"qad-json-ok\");
  return 0;
}
EOF
    cc -Dmain=qad_server_main -I'$src/include' -I'$src/src' -I'$build_dir' -c '$src/src/server.c' -o /tmp/qad-server.o
    cc -I'$src/include' -I'$src/src' -I'$build_dir' /tmp/qad-json-smoke.c /tmp/qad-server.o -lmicrohttpd -lcjson -o /tmp/qad-json-smoke
  "
  with_failure_context qad link-time "verifying qad JSON smoke linkage" \
    assert_links_to_packaged_safe /tmp/qad-json-smoke
  with_failure_context qad runtime-semantic "running qad JSON smoke" \
    run_logged /tmp/qad-json-smoke.log /tmp/qad-json-smoke
  with_failure_context qad runtime-semantic "checking qad JSON smoke sentinel" \
    grep -Fx 'qad-json-ok' /tmp/qad-json-smoke.log >/dev/null
}

test_snibbetracker() {
  local src=""
  local binary=""

  should_run snibbetracker || return 0

  with_failure_context snibbetracker package-install "installing build dependencies" install_build_deps snibbetracker
  set_failure_context snibbetracker package-install "fetching source package"
  src="$(fetch_source snibbetracker)"
  clear_failure_context

  log "snibbetracker: building binary and JSON save/load smoke test"
  with_failure_context snibbetracker compile-time "building snibbetracker and JSON smoke" run_bash_logged /tmp/snibbetracker-build.log "
    cd '$src'
    cp debian/Makefile snibbetracker/src/Makefile
    make -C snibbetracker/src -j'$(nproc)'
    cat > /tmp/snibbetracker-smoke.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include \"CSynth.h\"
#include <cjson/cJSON.h>

int main(void) {
  struct CSynthContext *ctx = cSynthContextNew();
  struct CSynthContext *loaded = cSynthContextNew();
  cJSON *root = NULL;
  char *json = NULL;

  if (ctx == NULL || loaded == NULL) {
    fprintf(stderr, \"context allocation failed\\n\");
    return 1;
  }

  cSynthInit(ctx);
  root = cSynthSaveProject(ctx);
  if (root == NULL) {
    fprintf(stderr, \"cSynthSaveProject failed\\n\");
    return 2;
  }

  json = cJSON_PrintUnformatted(root);
  if (json == NULL) {
    fprintf(stderr, \"cJSON_PrintUnformatted failed\\n\");
    return 3;
  }

  if (strstr(json, \"\\\"file_version\\\"\") == NULL || strstr(json, \"\\\"patterns\\\"\") == NULL) {
    fprintf(stderr, \"saved project JSON was missing expected keys\\n%s\\n\", json);
    return 4;
  }

  cSynthInit(loaded);
  if (cSynthLoadProject(loaded, json) == 0) {
    fprintf(stderr, \"cSynthLoadProject failed\\n\");
    return 5;
  }

  puts(json);
  free(json);
  cJSON_Delete(root);
  return 0;
}
EOF
    cc -I snibbetracker/src -I /usr/include/cjson /tmp/snibbetracker-smoke.c \
      snibbetracker/src/CAllocator.o \
      snibbetracker/src/CEngine.o \
      snibbetracker/src/CInput.o \
      snibbetracker/src/CSynth.o \
      snibbetracker/src/dir_posix.o \
      -L/usr/lib/x86_64-linux-gnu \
      -lSDL2main -lSDL2 -lm -lcjson -luuid \
      -o /tmp/snibbetracker-smoke
  "

  binary="$src/snibbetracker/src/snibbetracker"
  set_failure_context snibbetracker compile-time "checking snibbetracker build output"
  test -x "$binary" || die "snibbetracker binary was not built"
  clear_failure_context
  with_failure_context snibbetracker link-time "verifying snibbetracker linkage to packaged libcjson" \
    assert_links_to_packaged_safe "$binary"
  with_failure_context snibbetracker link-time "verifying snibbetracker JSON smoke linkage" \
    assert_links_to_packaged_safe /tmp/snibbetracker-smoke
  with_failure_context snibbetracker runtime-semantic "running snibbetracker JSON smoke" \
    run_logged /tmp/snibbetracker-smoke.json /tmp/snibbetracker-smoke
  with_failure_context snibbetracker runtime-semantic "validating snibbetracker project JSON" \
    jq -e '.file_version == 4 and (.patterns | type == "array") and (.nodes | type == "array")' \
      /tmp/snibbetracker-smoke.json >/dev/null
}

test_opm_common() {
  local src=""
  local smoke_dir="/tmp/opm-common-json-smoke"
  local binary=""

  should_run opm-common || return 0

  set_failure_context opm-common package-install "fetching source package"
  src="$(fetch_source opm-common)"
  clear_failure_context

  log "opm-common: building a JsonObject smoke with upstream Findcjson.cmake and exercising parse/dump paths"
  with_failure_context opm-common compile-time "building JsonObject smoke with Findcjson.cmake" run_bash_logged /tmp/opm-common-build.log "
    set -euo pipefail
    rm -rf '$smoke_dir'
    OPM_COMMON_SRC='$src' python3 - <<'PY'
import base64
import os
from pathlib import Path

src = Path(os.environ['OPM_COMMON_SRC'])
smoke_dir = Path('/tmp/opm-common-json-smoke')
cmake_b64 = 'Y21ha2VfbWluaW11bV9yZXF1aXJlZChWRVJTSU9OIDMuMTYpCnByb2plY3Qob3BtX2NvbW1vbl9qc29uX3Ntb2tlIExBTkdVQUdFUyBDIENYWCkKCmxpc3QoUFJFUEVORCBDTUFLRV9NT0RVTEVfUEFUSCAiQEBTUkNAQC9jbWFrZS9Nb2R1bGVzIikKZmluZF9wYWNrYWdlKGNqc29uIFJFUVVJUkVEKQoKYWRkX2V4ZWN1dGFibGUob3BtLWNvbW1vbi1qc29uLXNtb2tlCiAgbWFpbi5jcHAKICAiQEBTUkNAQC9zcmMvb3BtL2pzb24vSnNvbk9iamVjdC5jcHAiKQp0YXJnZXRfaW5jbHVkZV9kaXJlY3RvcmllcyhvcG0tY29tbW9uLWpzb24tc21va2UgUFJJVkFURQogICJAQFNSQ0BAIgogICR7Y2pzb25fSU5DTFVERV9ESVJTfSkKdGFyZ2V0X2xpbmtfbGlicmFyaWVzKG9wbS1jb21tb24tanNvbi1zbW9rZSBQUklWQVRFICR7Y2pzb25fTElCUkFSSUVTfSkKdGFyZ2V0X2NvbXBpbGVfZmVhdHVyZXMob3BtLWNvbW1vbi1qc29uLXNtb2tlIFBSSVZBVEUgY3h4X3N0ZF8xNykK'
main_b64 = 'I2luY2x1ZGUgPGZpbGVzeXN0ZW0+CiNpbmNsdWRlIDxpb3N0cmVhbT4KI2luY2x1ZGUgPHN0cmluZz4KCiNpbmNsdWRlIDxvcG0vanNvbi9Kc29uT2JqZWN0LmhwcD4KCmludCBtYWluKGludCBhcmdjLCBjaGFyICoqYXJndikgewogIGlmIChhcmdjICE9IDIpIHsKICAgIHN0ZDo6Y2VyciA8PCAiZXhwZWN0ZWQgYSBKU09OIGZpbGUgcGF0aFxuIjsKICAgIHJldHVybiAxOwogIH0KCiAgSnNvbjo6SnNvbk9iamVjdCBwYXJzZWQoc3RkOjpmaWxlc3lzdGVtOjpwYXRoKGFyZ3ZbMV0pKTsKICBpZiAoIXBhcnNlZC5oYXNfaXRlbSgia2V5d29yZHMiKSkgewogICAgc3RkOjpjZXJyIDw8ICJrZXl3b3JkcyBhcnJheSBtaXNzaW5nXG4iOwogICAgcmV0dXJuIDI7CiAgfQoKICBKc29uOjpKc29uT2JqZWN0IGtleXdvcmRzID0gcGFyc2VkLmdldF9pdGVtKCJrZXl3b3JkcyIpOwogIGlmICgha2V5d29yZHMuaXNfYXJyYXkoKSB8fCBrZXl3b3Jkcy5zaXplKCkgIT0gMlUpIHsKICAgIHN0ZDo6Y2VyciA8PCAidW5leHBlY3RlZCBrZXl3b3JkIGFycmF5IHNoYXBlXG4iOwogICAgcmV0dXJuIDM7CiAgfQoKICBKc29uOjpKc29uT2JqZWN0IGZpcnN0ID0ga2V5d29yZHMuZ2V0X2FycmF5X2l0ZW0oMFUpOwogIGlmIChmaXJzdC5nZXRfc3RyaW5nKCJuYW1lIikgIT0gIkJQUiIpIHsKICAgIHN0ZDo6Y2VyciA8PCAiZmlyc3Qga2V5d29yZCBuYW1lIGRpZCBub3Qgcm91bmQtdHJpcFxuIjsKICAgIHJldHVybiA0OwogIH0KCiAgSnNvbjo6SnNvbk9iamVjdCBnZW5lcmF0ZWQ7CiAgZ2VuZXJhdGVkLmFkZF9pdGVtKCJwcm9iZSIsICJvayIpOwogIEpzb246Okpzb25PYmplY3QgdmFsdWVzID0gZ2VuZXJhdGVkLmFkZF9hcnJheSgidmFsdWVzIik7CiAgdmFsdWVzLmFkZCg3KTsKICB2YWx1ZXMuYWRkKDkpOwoKICBKc29uOjpKc29uT2JqZWN0IHJvdW5kdHJpcChnZW5lcmF0ZWQuZHVtcCgpKTsKICBpZiAocm91bmR0cmlwLmdldF9zdHJpbmcoInByb2JlIikgIT0gIm9rIiB8fAogICAgICByb3VuZHRyaXAuZ2V0X2l0ZW0oInZhbHVlcyIpLmdldF9hcnJheV9pdGVtKDFVKS5hc19pbnQoKSAhPSA5KSB7CiAgICBzdGQ6OmNlcnIgPDwgImdlbmVyYXRlZCBKU09OIGRpZCBub3Qgcm91bmQtdHJpcFxuIjsKICAgIHJldHVybiA1OwogIH0KCiAgc3RkOjpjb3V0IDw8ICJvcG0tY29tbW9uLWpzb24tb2tcbiI7CiAgcmV0dXJuIDA7Cn0K'

smoke_dir.mkdir(parents=True, exist_ok=True)
(smoke_dir / 'CMakeLists.txt').write_text(
    base64.b64decode(cmake_b64).decode('utf-8').replace('@@SRC@@', str(src)),
    encoding='utf-8',
)
(smoke_dir / 'main.cpp').write_text(
    base64.b64decode(main_b64).decode('utf-8').replace(
        'Json::JsonObject parsed(std::filesystem::path(argv[1]));',
        'Json::JsonObject parsed{std::filesystem::path(argv[1])};',
    ),
    encoding='utf-8',
)
PY
    cmake -S '$smoke_dir' -B '$smoke_dir/build' -G Ninja
    cmake --build '$smoke_dir/build'
  "

  binary="$(find "$smoke_dir" -maxdepth 5 -type f -name 'opm-common-json-smoke' | head -n1)"
  set_failure_context opm-common compile-time "checking JsonObject smoke build output"
  if ! test -x "$binary"; then
    cat /tmp/opm-common-build.log >&2
    die "opm-common JsonObject smoke binary was not built"
  fi
  clear_failure_context
  with_failure_context opm-common link-time "verifying JsonObject smoke linkage to packaged libcjson" \
    assert_links_to_packaged_safe "$binary"
  with_failure_context opm-common runtime-semantic "running JsonObject round-trip smoke" \
    run_logged /tmp/opm-common-json.log "$binary" "$src/tests/json/example1.json"
  with_failure_context opm-common runtime-semantic "checking JsonObject smoke sentinel" \
    grep -Fx 'opm-common-json-ok' /tmp/opm-common-json.log >/dev/null
}

test_iperf3() {
  local src=""
  local binary=""
  local lib_path=""

  should_run iperf3 || return 0

  with_failure_context iperf3 package-install "installing build dependencies" install_build_deps iperf3
  set_failure_context iperf3 package-install "fetching source package"
  src="$(fetch_source iperf3)"
  clear_failure_context

  log "iperf3: rebuilding libiperf against packaged libcjson and exercising the JSON helper routines"
  with_failure_context iperf3 compile-time "rebuilding libiperf against packaged libcjson" run_bash_logged /tmp/iperf3-build.log "
    cd '$src'
    python3 - <<'PY'
from pathlib import Path

makefile = Path('src/Makefile.am')
text = makefile.read_text()
if '                        cjson.c \\\\' not in text or '                        cjson.h \\\\' not in text:
    raise SystemExit('iperf3 Makefile.am no longer lists the vendored cJSON sources')
text = text.replace('                        cjson.c \\\\\n', '')
text = text.replace('                        cjson.h \\\\\n', '')
if 'libiperf_la_LIBADD' not in text:
    text = text.replace('\\n\\n# Specify the sources and various flags for the iperf binary\\n',
                        '\\nlibiperf_la_LIBADD      = -lcjson\\n\\n# Specify the sources and various flags for the iperf binary\\n',
                        1)
makefile.write_text(text)
Path('src/cjson.h').write_text('#pragma once\\n#include <cjson/cJSON.h>\\n')
PY
    autoreconf -fi
    ./configure
    make -C src -j'$(nproc)' iperf3 libiperf.la
  "

  binary="$src/src/.libs/iperf3"
  lib_path="$(find "$src/src/.libs" -maxdepth 1 -type f -name 'libiperf.so*' | head -n1)"
  set_failure_context iperf3 compile-time "checking iperf3 build outputs"
  test -x "$binary" || die "iperf3 binary was not built"
  [[ -n "$lib_path" ]] || die "iperf3 shared library was not built"
  clear_failure_context
  with_failure_context iperf3 link-time "capturing iperf3 link resolution" run_bash_logged /tmp/iperf3-link-resolution.log "
    LD_LIBRARY_PATH='$src/src/.libs' ldd '$binary'
  "
  set_failure_context iperf3 link-time "verifying iperf3 link resolution"
  grep -E 'libiperf\.so\.0 => .*/src/\.libs/libiperf\.so\.0' /tmp/iperf3-link-resolution.log >/dev/null || {
    cat /tmp/iperf3-link-resolution.log >&2
    return 1
  }
  grep -F 'libcjson.so.1 =>' /tmp/iperf3-link-resolution.log >/dev/null || {
    cat /tmp/iperf3-link-resolution.log >&2
    return 1
  }
  clear_failure_context
  with_failure_context iperf3 link-time "verifying libiperf linkage to packaged libcjson" \
    assert_links_to_packaged_safe "$lib_path"

  with_failure_context iperf3 compile-time "building iperf3 JSON smoke" run_bash_logged /tmp/iperf3-json-smoke-build.log "
    set -euo pipefail
    python3 - <<'PY'
import base64
from pathlib import Path

source_b64 = 'I2luY2x1ZGUgPGludHR5cGVzLmg+CiNpbmNsdWRlIDxzdGRpby5oPgojaW5jbHVkZSA8c3RyaW5nLmg+CgojaW5jbHVkZSAiaXBlcmZfdXRpbC5oIgoKc3RhdGljIGludCBmYWlsKGNvbnN0IGNoYXIgKm1lc3NhZ2UpIHsKICAgIGZwcmludGYoc3RkZXJyLCAiJXNcbiIsIG1lc3NhZ2UpOwogICAgcmV0dXJuIDE7Cn0KCmludCBtYWluKHZvaWQpIHsKICAgIGNKU09OICpyb290ID0gTlVMTDsKICAgIGNKU09OICpwYXJzZWQgPSBOVUxMOwogICAgY0pTT04gKnJvbGUgPSBOVUxMOwogICAgY0pTT04gKnN0cmVhbXMgPSBOVUxMOwogICAgY0pTT04gKnJldmVyc2UgPSBOVUxMOwogICAgY0pTT04gKnJhdGUgPSBOVUxMOwogICAgY2hhciAqcmVuZGVyZWQgPSBOVUxMOwogICAgaW50IHJjID0gMTsKCiAgICByb290ID0gaXBlcmZfanNvbl9wcmludGYoCiAgICAgICAgInJvbGU6ICVzIHN0cmVhbXM6ICVkIHJldmVyc2U6ICViIHJhdGU6ICVmIiwKICAgICAgICAiY2xpZW50IiwKICAgICAgICAoaW50NjRfdCk0LAogICAgICAgIDEsCiAgICAgICAgMTIuNQogICAgKTsKICAgIGlmIChyb290ID09IE5VTEwpIHsKICAgICAgICByZXR1cm4gZmFpbCgiaXBlcmZfanNvbl9wcmludGYgcmV0dXJuZWQgTlVMTCIpOwogICAgfQoKICAgIHJlbmRlcmVkID0gY0pTT05fUHJpbnRVbmZvcm1hdHRlZChyb290KTsKICAgIGlmIChyZW5kZXJlZCA9PSBOVUxMKSB7CiAgICAgICAgY0pTT05fRGVsZXRlKHJvb3QpOwogICAgICAgIHJldHVybiBmYWlsKCJjSlNPTl9QcmludFVuZm9ybWF0dGVkIHJldHVybmVkIE5VTEwiKTsKICAgIH0KCiAgICBwYXJzZWQgPSBjSlNPTl9QYXJzZShyZW5kZXJlZCk7CiAgICBpZiAocGFyc2VkID09IE5VTEwpIHsKICAgICAgICBjSlNPTl9mcmVlKHJlbmRlcmVkKTsKICAgICAgICBjSlNPTl9EZWxldGUocm9vdCk7CiAgICAgICAgcmV0dXJuIGZhaWwoImNKU09OX1BhcnNlIHJlamVjdGVkIHRoZSByZW5kZXJlZCBKU09OIik7CiAgICB9CgogICAgcm9sZSA9IGNKU09OX0dldE9iamVjdEl0ZW1DYXNlU2Vuc2l0aXZlKHBhcnNlZCwgInJvbGUiKTsKICAgIHN0cmVhbXMgPSBjSlNPTl9HZXRPYmplY3RJdGVtQ2FzZVNlbnNpdGl2ZShwYXJzZWQsICJzdHJlYW1zIik7CiAgICByZXZlcnNlID0gY0pTT05fR2V0T2JqZWN0SXRlbUNhc2VTZW5zaXRpdmUocGFyc2VkLCAicmV2ZXJzZSIpOwogICAgcmF0ZSA9IGNKU09OX0dldE9iamVjdEl0ZW1DYXNlU2Vuc2l0aXZlKHBhcnNlZCwgInJhdGUiKTsKICAgIGlmICghY0pTT05fSXNTdHJpbmcocm9sZSkgfHwgc3RyY21wKHJvbGUtPnZhbHVlc3RyaW5nLCAiY2xpZW50IikgIT0gMCkgewogICAgICAgIGdvdG8gY2xlYW51cDsKICAgIH0KICAgIGlmICghY0pTT05fSXNOdW1iZXIoc3RyZWFtcykgfHwgc3RyZWFtcy0+dmFsdWVkb3VibGUgIT0gNCkgewogICAgICAgIGdvdG8gY2xlYW51cDsKICAgIH0KICAgIGlmICghY0pTT05fSXNUcnVlKHJldmVyc2UpKSB7CiAgICAgICAgZ290byBjbGVhbnVwOwogICAgfQogICAgaWYgKCFjSlNPTl9Jc051bWJlcihyYXRlKSB8fCByYXRlLT52YWx1ZWRvdWJsZSAhPSAxMi41KSB7CiAgICAgICAgZ290byBjbGVhbnVwOwogICAgfQoKICAgIHB1dHMocmVuZGVyZWQpOwogICAgcmMgPSAwOwoKY2xlYW51cDoKICAgIGNKU09OX0RlbGV0ZShwYXJzZWQpOwogICAgY0pTT05fZnJlZShyZW5kZXJlZCk7CiAgICBjSlNPTl9EZWxldGUocm9vdCk7CiAgICByZXR1cm4gcmM7Cn0K'
Path('/tmp/iperf3-json-smoke.c').write_text(
    base64.b64decode(source_b64).decode('utf-8'),
    encoding='utf-8',
)
PY
    cc \
      -I'$src/src' \
      /tmp/iperf3-json-smoke.c \
      '$src/src/.libs/libiperf.so' \
      -lcjson \
      -o /tmp/iperf3-json-smoke
  "
  with_failure_context iperf3 link-time "verifying iperf3 JSON smoke linkage" \
    assert_links_to_packaged_safe /tmp/iperf3-json-smoke
  with_failure_context iperf3 runtime-semantic "running iperf3 JSON smoke" run_bash_logged /tmp/iperf3-runtime.log "
    export LD_LIBRARY_PATH='$src/src/.libs'
    /tmp/iperf3-json-smoke >/tmp/iperf3-client.json
  "

  set_failure_context iperf3 runtime-semantic "validating iperf3 JSON payload"
  jq -e '.role == "client" and .streams == 4 and .reverse == true and .rate == 12.5' \
    /tmp/iperf3-client.json >/dev/null || {
      cat /tmp/iperf3-client.json >&2
      return 1
    }
  clear_failure_context
}

test_epic5() {
  local src=""
  local binary=""

  should_run epic5 || return 0

  with_failure_context epic5 package-install "installing build dependencies" install_build_deps epic5
  set_failure_context epic5 package-install "fetching source package"
  src="$(fetch_source epic5)"
  clear_failure_context

  log "epic5: rebuilding scripted JSON functions against packaged libcjson and exercising JSON_EXPLODE/JSON_IMPLODE"
  with_failure_context epic5 compile-time "rebuilding scripted JSON functions against packaged libcjson" run_bash_logged /tmp/epic5-build.log "
    cd '$src'
    python3 - <<'PY'
from pathlib import Path

makefile = Path('source/Makefile.in')
text = makefile.read_text()
if 'cJSON.o ' not in text:
    raise SystemExit('epic5 Makefile.in no longer lists cJSON.o')
text = text.replace('cJSON.o ', '')
text = text.replace('\$(LIBS)', '\$(LIBS) -lcjson', 1)
makefile.write_text(text)
Path('source/cJSON.h').write_text('#pragma once\\n#include <cjson/cJSON.h>\\n')
regress = Path('regress/json').read_text()
Path('/tmp/epic5-json-smoke').write_text(
    regress + '\\necho epic5-json-ok:' + chr(36) + 'misses\\nexit;\\n'
)
PY
    ./configure
    make -C source -j'$(nproc)' epic5
  "

  binary="$src/source/epic5"
  set_failure_context epic5 compile-time "checking epic5 build output"
  test -x "$binary" || die "epic5 binary was not built"
  clear_failure_context
  with_failure_context epic5 link-time "verifying epic5 linkage to packaged libcjson" \
    assert_links_to_packaged_safe "$binary"

  with_failure_context epic5 runtime-semantic "running JSON_EXPLODE/JSON_IMPLODE regression driver" run_bash_logged /tmp/epic5-runtime-driver.log "
    set +e
    timeout 30 '$binary' -d -B -s -n smoke -l /tmp/epic5-json-smoke > /tmp/epic5-runtime.log 2>&1
    status=\$?
    set -e
    cat /tmp/epic5-runtime.log
    if [[ \"\$status\" -ne 0 && \"\$status\" -ne 1 ]]; then
      exit \"\$status\"
    fi
  "

  set_failure_context epic5 runtime-semantic "checking JSON_EXPLODE/JSON_IMPLODE results"
  grep -F 'epic5-json-ok:0' /tmp/epic5-runtime.log >/dev/null || {
    cat /tmp/epic5-runtime.log >&2
    return 1
  }
  ! grep -F '[FAILED!]' /tmp/epic5-runtime.log >/dev/null || {
    cat /tmp/epic5-runtime.log >&2
    return 1
  }
  clear_failure_context
}

prepare_writable_root
assert_dependents_inventory
assert_only_filter
build_and_install_safe_cjson_packages

test_freerdp3
test_librist
test_monado
test_mosquitto
test_ocp
test_oidc_agent
test_pgagroal
test_qad
test_snibbetracker
test_opm_common
test_iperf3
test_epic5

log "All selected dependent checks passed"
CONTAINER_SCRIPT
