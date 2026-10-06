# AGENTS.md — jekyll-compress-flow

Jekyll plugin: generates `.br`/`.zst`/`.gz` siblings for text assets via a
`:site, :post_write` dispatcher (default priority 10, configurable from 0–10),
after page post-processors and Fingerprint Flow. Precompressed-capable static
servers (Caddy
`file_server { precompressed ... }`) serve them with no per-request CPU.

## Layout

- `lib/jekyll-compress-flow.rb` — gem entry (requires the real file)
- `lib/jekyll/compress_flow.rb` — config, format table, hook, `run()`
- `lib/jekyll/compress_flow/version.rb` — single version literal
- `spec/` — RSpec (tmp dirs, real CLI tools — specs need brotli/zstd/gzip installed)

## Commands

- `bundle install`, `bundle exec rake` (quality gate), `rake quick`
- `rake 'version:bump[patch]'`, `rake version:check_changelog`
- Release: `rake version:bump[...]` → changelog `## X.Y.Z — date` →
  `rake 'release_tag[X.Y.Z]'` (gate + tag + push) → release workflow
  publishes via trusted publishing. Never add a task named `release` —
  bundler's is required by rubygems/release-gem.

## Conventions

- `# frozen_string_literal: true`, double-quoted strings, RuboCop clean
- Shell out with array-form `system()` — never string-interpolated commands
- Compressor CLI tools are a *build host* dependency, not a gem dependency —
  detect once per format via `tool --version`, `fail_on_error` decides
  abort vs warn; minimums brotli >= 1.1.0 / zstd >= 1.5.5 (Ubuntu 24.04
  LTS floor), unparseable banner = installed

## CI / services

- `.github/workflows/ci.yml` — Ruby 3.3/3.4 matrix; installs `brotli`/`zstd`
  via apt (specs shell out to real CLIs), bundle-audit, `rake ci`, Codecov
  upload on 3.4; separate `semgrep ci` job
- Secrets used: `SEMGREP_APP_TOKEN`, `CODECOV_TOKEN` (repo → Settings →
  Secrets → Actions); Codecov OIDC works without the token
- Codecov (`codecov.yml`, 85% target), SonarQube Cloud CI analysis
  (`sonar-project.properties`, scan step in `ci.yml` imports SimpleCov
  `coverage/coverage.json`), CodeFactor + DeepWiki index the public repo
  automatically; `.devin/wiki.json` steers DeepWiki
- `.semgrep.yml` holds the local ReDoS rule — pre-commit uses it, CI uses
  the org policy via `semgrep ci`
