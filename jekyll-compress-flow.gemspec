# frozen_string_literal: true

require_relative "lib/jekyll/compress_flow/version"

Gem::Specification.new do |spec|
  spec.name = "jekyll-compress-flow"
  spec.version = Jekyll::CompressFlow::VERSION
  spec.authors = ["Svend Gundestrup"]
  spec.email = ["svend@gundestrup.dk"]
  spec.summary = "Generate .br/.zst/.gz siblings for Jekyll build output"
  spec.description = "A Jekyll plugin that writes Brotli, Zstandard and gzip siblings next to text " \
                     "assets at the end of a build, so a precompressed-capable static server " \
                     "(e.g. Caddy's file_server precompressed) can serve them without per-request " \
                     "compression CPU."
  spec.homepage = "https://github.com/gundestrup/jekyll-compress-flow"
  spec.license = "AGPL-3.0-or-later"
  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/gundestrup/jekyll-compress-flow/tree/main",
    "changelog_uri" => "https://github.com/gundestrup/jekyll-compress-flow/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/gundestrup/jekyll-compress-flow/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.required_ruby_version = ">= 3.3.0"
  spec.files = Dir["lib/**/*", "README.md", "LICENSE", "CHANGELOG.md", "interface.yml"]
  spec.require_paths = ["lib"]

  spec.add_dependency "jekyll", ">= 4.4", "< 5.0"
end
