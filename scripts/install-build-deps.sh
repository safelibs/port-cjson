#!/usr/bin/env bash
# Install apt packages needed to dpkg-buildpackage the safe cjson port.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  devscripts \
  dpkg-dev \
  equivs \
  fakeroot \
  file \
  git \
  jq \
  python3 \
  rsync \
  xz-utils
