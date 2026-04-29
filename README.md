# port-cjson

SafeLibs port of `cjson` for Ubuntu 24.04. Built via `dpkg-buildpackage` rooted in `safe/debian/`.

This repository follows the [`safelibs/port-template`](https://github.com/safelibs/port-template) contract. See [`AGENTS.md`](AGENTS.md) for the canonical layout, hook-script contracts, and CI sequence.

## Layout

- `original/` — pinned upstream `cjson` source for differential testing.
- `safe/` — Rust safe implementation plus `safe/debian/` packaging metadata.
- `test-original.sh`, `check_*` — port-internal test harnesses.
- `scripts/` — template hook scripts (`install-build-deps.sh`, `build-debs.sh`, etc.).
- `packaging/package.env` — `SAFELIBS_LIBRARY` identifier for the validator hook; the `DEB_*` fields are scaffolding (the real metadata lives in `safe/debian/`).

## Local Build

```sh
bash scripts/install-build-deps.sh
bash scripts/check-layout.sh
rm -rf build dist
bash scripts/build-debs.sh
```

`.deb` artifacts land in `dist/`.
