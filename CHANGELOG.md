# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed

- Register the compression dispatcher at low priority (10) by default, after
  normal-priority processing and Fingerprint Flow (default 12); allow per-site
  `compress_flow.priority` values from 0 through 10.

## 0.2.0 — 2026-10-03

### Added

- Tool version checks: `brotli >= 1.1.0` / `zstd >= 1.5.5` enforced via
  `tool --version` probe (Ubuntu 24.04 LTS floor — the oldest versions
  exercised by CI); `gzip` unchecked (Apple vs GNU version strings are
  incomparable); unparseable version banners are treated as installed
- Minimum-versions + per-platform install docs (brew/apt/dnf/apk/
  scoop/winget), Caddy/nginx/Apache serving guide
- Specs: real `Jekyll::Site` build exercising the hook end-to-end,
  compressor-failure and version-check paths — 100% line + branch
- CI: Ruby 3.3/3.4 matrix, Codecov, Semgrep, SonarCloud, CodeFactor,
  DeepWiki, Dependabot; release workflow publishing via RubyGems
  trusted publishing (OIDC)

### Changed

- Missing-tool message reads "cannot generate" — accurate in both
  warn and abort modes

## 0.1.0 — 2026-10-03

### Added

- `:site, :post_write` hook generating `.br`, `.zst` and `.gz` siblings
  for text assets via the `brotli`, `zstd` and `gzip` CLI tools
- `compress_flow:` config: `enabled` (default: production builds only),
  `formats`, `extensions`, `min_size`, `fail_on_error`
- Missing-tool detection reported once per format; fails the build by
  default so uncompressed output is never silently shipped
