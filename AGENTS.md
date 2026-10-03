# AGENTS.md — jekyll-compress-flow

Jekyll plugin: generates `.br`/`.zst`/`.gz` siblings for text assets at
`:site, :post_write` so precompressed-capable static servers (Caddy
`file_server { precompressed ... }`) serve them with no per-request CPU.

## Layout

- `lib/jekyll-compress-flow.rb` — gem entry (requires the real file)
- `lib/jekyll/compress_flow.rb` — config, format table, hook, `run()`
- `lib/jekyll/compress_flow/version.rb` — single version literal
- `spec/` — RSpec (tmp dirs, real CLI tools — specs need brotli/zstd/gzip installed)

## Commands

- `bundle install`, `bundle exec rake` (quality gate), `rake quick`
- `rake 'version:bump[patch]'`, `rake version:check_changelog`
- Release: bump → changelog `## X.Y.Z — date` → `rake` → `gem build` → `gem push`

## Conventions

- `# frozen_string_literal: true`, double-quoted strings, RuboCop clean
- Shell out with array-form `system()` — never string-interpolated commands
- Compressor CLI tools are a *build host* dependency, not a gem dependency —
  detect once per format, `fail_on_error` decides abort vs warn
