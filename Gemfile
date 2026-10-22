# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  gem "bundler-audit", "~> 0.9"
  gem "csv" # jekyll needs it explicitly on Ruby >= 3.4 (removed from stdlib)
  gem "rake", "~> 13.2"
  gem "rspec", "~> 3.13"
  gem "tmpdir"
end

group :development do
  gem "rubocop", "~> 1.91"
  gem "rubocop-rspec", "~> 3.10"
end

group :test do
  gem "simplecov", "~> 1.1"
  gem "simplecov-cobertura", "~> 4.0"
end
