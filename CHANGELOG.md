# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed

- CI: Semgrep moved from an inline `pip3 install` pin to the pinned
  `semgrep/semgrep` container image (tag + sha256 digest). Image bumped
  to 1.182.1 (certificate trust fix for the eMudhra CA compromise).
  CI Node bumped from 24 to 26 (Active LTS "Lithium" since 2026-10-28).
- CI: `sonarqube-scan-action` bumped to v8.4.0; `markdownlint-cli2`
  bumped to 0.24.0; in-range gem updates (rubocop 1.92.2, parser
  3.3.13.0, addressable 2.9.1, csv 3.3.7, sass-embedded 1.107.0).
- CI: Ruby 4.0 added to the test matrix (latest stable major;
  `required_ruby_version >= 3.3.0` already permits it).

## 0.2.1 — 2026-10-06

### Added

- `Jekyll::CompressFlow::Interface.to_h` — the config surface
  (`compress_flow` keys plus `formats:`/`priority:` enums) derived from
  `DEFAULTS`, serialized to a committed `interface.yml` by
  `rake interface`; `interface_spec.rb` pins manifest freshness.

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
