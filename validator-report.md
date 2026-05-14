# cjson validator baseline report

Phase: `impl_01_validator_baseline`

## Baseline identity

- Validator repository: https://github.com/safelibs/validator
- Validator commit: `d1c08d01cd50b34a7aeb62c5630e28df0eb6cd97`
- Validator checkout status: clean
- Validated port commit: pending scaffold commit
- Report commit: pending final report commit
- Canonical packages: `libcjson1`, `libcjson-dev`

## Checks executed

- `make -C validator unit` passed.
- `make -C validator check-testcases` passed.
- `bash scripts/install-build-deps.sh` passed.
- `bash scripts/check-layout.sh` passed.
- `python3 -m unittest tests.test_build_port_lock` passed.

## Baseline

Package build and validator port-mode execution are pending this scaffold
commit. The validator port mode for this repository will consume `.deb`
overrides and a generated port lock; it will not be given a `safe/` source path.

## Failures

Baseline failures pending validator execution.

## Notes

- No validator source changes.
- Do not modify validator sources for this phase.
- Raw `.work/validation/`, `dist/`, and validator artifact contents are
  workspace artifacts only; durable conclusions will be recorded here.
