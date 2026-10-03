# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## 0.1.0 — 2026-10-03

### Added

- `:site, :post_write` hook generating `.br`, `.zst` and `.gz` siblings
  for text assets via the `brotli`, `zstd` and `gzip` CLI tools
- `compress_flow:` config: `enabled` (default: production builds only),
  `formats`, `extensions`, `min_size`, `fail_on_error`
- Missing-tool detection reported once per format; fails the build by
  default so uncompressed output is never silently shipped
