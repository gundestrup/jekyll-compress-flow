# jekyll-compress-flow

Jekyll plugin that generates **Brotli (`.br`), Zstandard (`.zst`) and
gzip (`.gz`) siblings** for text assets at the end of a build. A
precompressed-capable static server then serves the best encoding the
client accepts — with zero per-request compression CPU.

Pairs with Caddy's `file_server { precompressed gzip br zstd }` (see
[`caddy_config_file_local_hosting`](https://github.com/gundestrup)).
Static sites are always "pre"-compressed anyway — the compression
simply happens at build time instead of request time.

[Compare different formats](https://speedvitals.com/blog/zstd-vs-brotli-vs-gzip/)

## Install

Add to the site's `Gemfile`:

```ruby
group :jekyll_plugins do
  gem "jekyll-compress-flow", "~> 0.1"
  # for local development against a checkout:
  # gem "jekyll-compress-flow", path: "../jekyll-compress-flow"
end
```

Install the compressor binaries on the build host:

```bash
brew install brotli zstd gzip        # macOS
apt-get install brotli zstd gzip     # Debian/Ubuntu CI
```

That's it — `JEKYLL_ENV=production bundle exec jekyll build` writes
`file.br`, `file.zst` and `file.gz` next to every text asset.

## Configuration (`_config.yml`)

```yaml
compress_flow:
  enabled: true            # default: Jekyll.env == "production"
  formats: [br, zst, gz]   # subset of the three; unknown names abort
  extensions: [html, css, js, json, xml, svg, txt, map]
  min_size: 0              # bytes — skip tiny files
  fail_on_error: true      # false: warn + skip instead of failing build
```

## Behavior

- Runs on `:site, :post_write`, after every file is written — works
  with any generator (pages, posts, feeds, sitemap, search JSON).
- Compressed siblings are never re-compressed (extensions not in the
  list); images/fonts/PDFs are skipped (already compressed formats).
- A missing CLI tool aborts the build once per format
  (`fail_on_error: false` downgrades to a warning) — never silently
  ships uncompressed output.
- `-f` flags make output idempotent — reruns overwrite stale siblings.

## Development

```bash
bundle install
bundle exec rake          # rubocop + markdownlint + bundler-audit + rspec + gem build
bundle exec rake quick    # rubocop + rspec only
```
