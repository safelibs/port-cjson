#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_TAG="${CJSON_ORIGINAL_TEST_IMAGE:-cjson-original-test:ubuntu24.04}"
ONLY=""

usage() {
  cat <<'EOF'
usage: test-original.sh [--only <source-package>]

Runs a Docker-based compatibility matrix for the Ubuntu 24.04 cJSON dependents
recorded in dependents.json, using a /usr/local install of the original cJSON.

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
      build-essential \
      ca-certificates \
      cmake \
      dpkg-dev \
      file \
      jq \
      meson \
      netcat-openbsd \
      ninja-build \
      pkg-config \
      python3 \
      python3-pkg-resources \
      ripgrep \
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
set -euo pipefail

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

ROOT=/work
ONLY="${CJSON_TEST_ONLY:-}"
APT_UPDATED=0
declare -A BUILD_DEPS_READY=()
declare -A SOURCE_DIRS=()

log() {
  printf '\n==> %s\n' "$1"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

assert_dependents_inventory() {
  python3 - <<'PY'
import json
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
]

data = json.loads(Path("/work/dependents.json").read_text(encoding="utf-8"))
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

  python3 - "$ONLY" <<'PY'
import json
import sys
from pathlib import Path

name = sys.argv[1]
data = json.loads(Path("/work/dependents.json").read_text(encoding="utf-8"))
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

prepare_original_cjson() {
  log "Building original cJSON into /usr/local"
  run_logged /tmp/cjson-configure.log \
    cmake -S "$ROOT/original" -B /tmp/cjson-build -G Ninja -DCMAKE_BUILD_TYPE=Release -DENABLE_CJSON_TEST=OFF
  run_logged /tmp/cjson-build.log cmake --build /tmp/cjson-build -j"$(nproc)"
  run_logged /tmp/cjson-install.log cmake --install /tmp/cjson-build
  ldconfig

  export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
  export LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export CMAKE_PREFIX_PATH="/usr/local${CMAKE_PREFIX_PATH:+;$CMAKE_PREFIX_PATH}"

  find /usr/local -name 'libcjson.so*' | grep -F 'libcjson.so' >/dev/null || die "original cJSON install did not produce libcjson shared libraries"
}

assert_links_to_original() {
  local target="$1"

  [[ -e "$target" ]] || die "missing binary or library to inspect: $target"
  ldd "$target" 2>/dev/null | grep -F '/usr/local/' | grep -F 'libcjson.so' >/dev/null || {
    echo "expected $target to resolve libcjson from /usr/local" >&2
    ldd "$target" >&2 || true
    return 1
  }
}

find_linked_artifact() {
  local root="$1"
  local candidate=""

  while IFS= read -r -d '' candidate; do
    if ldd "$candidate" 2>/dev/null | grep -F '/usr/local/' | grep -F 'libcjson.so' >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(find "$root" -type f \( -perm -111 -o -name '*.so' -o -name '*.so.*' \) -print0 2>/dev/null)

  return 1
}

assert_any_tree_links_to_original() {
  local root="$1"
  local label="$2"
  local artifact=""

  artifact="$(find_linked_artifact "$root")" || {
    echo "expected at least one $label artifact in $root to resolve libcjson from /usr/local" >&2
    return 1
  }

  printf 'linked %s artifact: %s\n' "$label" "$artifact"
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

test_freerdp3() {
  local src=""
  local build_dir="/tmp/build-freerdp3"
  local lib_path=""
  local sfreerdp_bin=""

  should_run freerdp3 || return 0

  install_build_deps freerdp3
  src="$(fetch_source freerdp3)"

  log "freerdp3: building AAD core and SDL client"
  rm -rf "$build_dir"
  run_logged /tmp/freerdp3-configure.log \
    cmake -S "$src" -B "$build_dir" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH=/usr/local \
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
  run_logged /tmp/freerdp3-build.log cmake --build "$build_dir" --target freerdp sfreerdp

  sfreerdp_bin="$(find "$build_dir" -path '*/sfreerdp' -type f | head -n1)"
  [[ -n "$sfreerdp_bin" ]] || die "freerdp3 SDL client was not built"
  lib_path="$(find "$build_dir/libfreerdp" -maxdepth 1 -name 'libfreerdp3.so*' | head -n1)"
  [[ -n "$lib_path" ]] || die "freerdp3 core library was not built"
  assert_links_to_original "$sfreerdp_bin"
  assert_links_to_original "$lib_path"
}

test_librist() {
  should_run librist || return 0

  log "librist: exercising sender statistics JSON output through rist-tools"
  install_packages rist-tools
  assert_links_to_original "$(command -v ristreceiver)"

  (
    set -euo pipefail
    ristreceiver -i rist://127.0.0.1:9200 -o udp://127.0.0.1:9201 -S 100 -v 6 >/tmp/librist-receiver.log 2>&1 &
    local_rx_pid="$!"
    ristsender -i udp://127.0.0.1:9202 -o rist://127.0.0.1:9200 -S 100 -v 6 >/tmp/librist-sender.log 2>&1 &
    local_tx_pid="$!"
    trap 'kill "$local_rx_pid" "$local_tx_pid" 2>/dev/null || true; wait "$local_rx_pid" 2>/dev/null || true; wait "$local_tx_pid" 2>/dev/null || true' EXIT

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
  )

  grep -F '"sender-stats"' /tmp/librist-sender.log >/dev/null || {
    cat /tmp/librist-sender.log >&2
    die "librist sender statistics JSON was not emitted"
  }

  extract_first_json_from_log /tmp/librist-sender.log | jq -e '."sender-stats".peer.stats.sent >= 1' >/dev/null
}

test_monado() {
  local src=""
  local build_dir="/tmp/build-monado"
  local test_bin=""

  should_run monado || return 0

  install_build_deps monado
  src="$(fetch_source monado)"

  log "monado: building and running tests_json with system cJSON"
  rm -rf "$build_dir"
  run_logged /tmp/monado-configure.log \
    cmake -S "$src" -B "$build_dir" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH=/usr/local \
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
      -DXRT_BUILD_DRIVER_QWERTY=OFF \
      -DXRT_BUILD_DRIVER_REALSENSE=OFF \
      -DXRT_BUILD_DRIVER_REMOTE=OFF \
      -DXRT_BUILD_DRIVER_RIFT_S=OFF \
      -DXRT_BUILD_DRIVER_SIMULAVR=OFF \
      -DXRT_BUILD_DRIVER_SIMULATED=OFF \
      -DXRT_BUILD_DRIVER_SURVIVE=OFF \
      -DXRT_BUILD_DRIVER_TWRAP=OFF \
      -DXRT_BUILD_DRIVER_ULV2=OFF \
      -DXRT_BUILD_DRIVER_VF=OFF \
      -DXRT_BUILD_DRIVER_VIVE=OFF \
      -DXRT_BUILD_DRIVER_WMR=OFF
  run_logged /tmp/monado-build.log cmake --build "$build_dir" --target tests_json

  test_bin="$build_dir/tests/tests_json"
  test -x "$test_bin" || die "monado tests_json binary was not built"
  run_logged /tmp/monado-tests.log "$test_bin" --success
  assert_links_to_original "$test_bin"
}

test_mosquitto() {
  local dynsec_plugin="/usr/lib/x86_64-linux-gnu/mosquitto_dynamic_security.so"

  should_run mosquitto || return 0

  log "mosquitto: exercising dynamic-security JSON persistence and mosquitto_sub JSON formatting"
  install_packages mosquitto mosquitto-clients
  assert_links_to_original "$(command -v mosquitto_sub)"
  test -f "$dynsec_plugin" || die "mosquitto dynamic-security plugin was not installed"
  assert_links_to_original "$dynsec_plugin"

  (
    set -euo pipefail
    broker_pid=0
    cleanup() {
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
  )

  jq -e '.topic == "smoke/json" and .payload == "hello" and .payloadlen == 5' /tmp/mosquitto-sub.json >/dev/null
  grep -Fx 'persisted' /tmp/mosquitto-sub-restart.out >/dev/null
}

test_ocp() {
  local src=""
  local binary=""
  local lib_path=""

  should_run ocp || return 0

  install_build_deps ocp
  src="$(fetch_source ocp)"

  log "ocp: building ncurses variant from source"
  run_bash_logged /tmp/ocp-configure.log "
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
  run_bash_logged /tmp/ocp-build.log "cd '$src' && make -j'$(nproc)'"

  lib_path="$src/libocp.so"
  test -f "$lib_path" || die "ocp build did not produce libocp.so"
  assert_links_to_original "$lib_path"

  log "ocp: exercising cached MusicBrainz JSON parsing through musicbrainz.c"
  run_bash_logged /tmp/ocp-musicbrainz-build.log "
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
  assert_links_to_original /tmp/ocp-musicbrainz-smoke
  run_logged /tmp/ocp-musicbrainz.log /tmp/ocp-musicbrainz-smoke
  grep -Fx 'Test Album' /tmp/ocp-musicbrainz.log >/dev/null
  grep -Fx 'First Track' /tmp/ocp-musicbrainz.log >/dev/null
  grep -Fx 'Track Artist feat. Guest' /tmp/ocp-musicbrainz.log >/dev/null

  if [[ -x "$src/ocp-curses" ]]; then
    binary="$src/ocp-curses"
  elif [[ -x "$src/ocp" ]]; then
    binary="$src/ocp"
  else
    die "ocp build did not produce an executable"
  fi
  timeout 10 "$binary" --help >/tmp/ocp-help.log 2>&1 || true
  test -s /tmp/ocp-help.log || die "ocp help output was empty"
}

test_oidc_agent() {
  local src=""
  local test_bin=""

  should_run oidc-agent || return 0

  install_build_deps oidc-agent
  src="$(fetch_source oidc-agent)"

  log "oidc-agent: running upstream unit tests against shared libcjson"
  run_bash_logged /tmp/oidc-agent-test.log \
    "cd '$src' && make USE_CJSON_SO=1 create_obj_dir_structure test"

  test_bin="$(find "$src" -path '*/test/bin/test' -type f | head -n1)"
  [[ -n "$test_bin" ]] || die "oidc-agent test binary was not produced"
  assert_links_to_original "$test_bin"
}

test_pgagroal() {
  should_run pgagroal || return 0

  log "pgagroal: exercising JSON management commands"
  install_packages pgagroal
  prepare_tester_user
  assert_links_to_original "$(command -v pgagroal-cli)"

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

  (
    set -euo pipefail
    runuser -u tester -- bash -lc \
      "pgagroal -c /home/tester/pgagroal/pgagroal.conf -a /home/tester/pgagroal/pgagroal_hba.conf >/home/tester/pgagroal/server.log 2>&1 & echo \$! >/home/tester/pgagroal/server.pid"
    trap 'kill "$(cat /home/tester/pgagroal/server.pid)" 2>/dev/null || true' EXIT

    for _ in $(seq 1 100); do
      [[ -S /home/tester/pgagroal/run/.s.pgagroal.2345 ]] && break
      sleep 0.1
    done

    runuser -u tester -- pgagroal-cli -c /home/tester/pgagroal/pgagroal.conf ping -F json >/tmp/pgagroal-ping.json
    runuser -u tester -- pgagroal-cli -c /home/tester/pgagroal/pgagroal.conf status -F json >/tmp/pgagroal-status.json
    runuser -u tester -- pgagroal-cli -c /home/tester/pgagroal/pgagroal.conf conf ls -F json >/tmp/pgagroal-conf-ls.json
  )

  jq -e '.command.name == "ping" and .command.output.message == "running"' /tmp/pgagroal-ping.json >/dev/null
  jq -e '.command.name == "status" and .command.output.connections.max == 10' /tmp/pgagroal-status.json >/dev/null
  jq -e '.command.name == "conf ls" and (.command.output.files.list | length) >= 2' /tmp/pgagroal-conf-ls.json >/dev/null
}

test_qad() {
  local src=""
  local build_dir="/tmp/build-qad"

  should_run qad || return 0

  install_build_deps qad
  src="$(fetch_source qad)"

  log "qad: building the HTTP/JSON daemon and exercising REST JSON request parsing"
  rm -rf "$build_dir"
  run_logged /tmp/qad-setup.log meson setup "$build_dir" "$src" -Dbackend-ilm=false
  run_logged /tmp/qad-build.log meson compile -C "$build_dir"

  test -x "$build_dir/qad" || die "qad binary was not built"
  assert_links_to_original "$build_dir/qad"
  run_logged /tmp/qad-help.log "$build_dir/qad" --help
  grep -F -- '--port' /tmp/qad-help.log >/dev/null

  run_bash_logged /tmp/qad-json-smoke-build.log "
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
  assert_links_to_original /tmp/qad-json-smoke
  run_logged /tmp/qad-json-smoke.log /tmp/qad-json-smoke
  grep -Fx 'qad-json-ok' /tmp/qad-json-smoke.log >/dev/null
}

test_snibbetracker() {
  local src=""
  local binary=""

  should_run snibbetracker || return 0

  install_build_deps snibbetracker
  src="$(fetch_source snibbetracker)"

  log "snibbetracker: building binary and JSON save/load smoke test"
  run_bash_logged /tmp/snibbetracker-build.log "
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
  test -x "$binary" || die "snibbetracker binary was not built"
  assert_links_to_original "$binary"
  assert_links_to_original /tmp/snibbetracker-smoke
  run_logged /tmp/snibbetracker-smoke.json /tmp/snibbetracker-smoke
  jq -e '.file_version == 4 and (.patterns | type == "array") and (.nodes | type == "array")' \
    /tmp/snibbetracker-smoke.json >/dev/null
}

assert_dependents_inventory
assert_only_filter
prepare_original_cjson

test_freerdp3
test_librist
test_monado
test_mosquitto
test_ocp
test_oidc_agent
test_pgagroal
test_qad
test_snibbetracker

log "All selected dependent checks passed"
CONTAINER_SCRIPT
