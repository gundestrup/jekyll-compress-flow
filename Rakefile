# frozen_string_literal: true

require "bundler/gem_tasks"

VERSION_FILE = File.expand_path("lib/jekyll/compress_flow/version.rb", __dir__)
CHANGELOG_FILE = File.expand_path("CHANGELOG.md", __dir__)
GEMSPEC_FILE = File.expand_path("jekyll-compress-flow.gemspec", __dir__)

task default: :quality

desc "Run all quality checks (style, docs, security, tests)"
task quality: %i[rubocop markdownlint bundler_audit spec build_gem]

desc "Run quick checks (style + tests only)"
task quick: %i[rubocop spec]

desc "Check code style with RuboCop"
task :rubocop do
  sh "bundle exec rubocop"
end

desc "Auto-fix RuboCop issues"
task :rubocop_fix do
  sh "bundle exec rubocop -a"
end

desc "Lint Markdown documentation"
task :markdownlint do
  sh "npx --yes markdownlint-cli2@0.23.2"
end

desc "Run security audit"
task :bundler_audit do
  sh "bundle exec bundler-audit check --update"
end

desc "Run Ruby tests"
task :spec do
  sh "bundle exec rspec"
end

desc "Build the gem"
task :build_gem do
  sh "gem build #{GEMSPEC_FILE}"
end

namespace :version do
  desc "Print the current gem version"
  task :show do
    puts File.read(VERSION_FILE)[/VERSION = "([^"]+)"/, 1]
  end

  desc "Bump the gem version: bundle exec rake 'version:bump[patch]'"
  task :bump, [:part] do |_task, args|
    part = args[:part].to_s
    abort "Usage: bundle exec rake 'version:bump[major|minor|patch]'" unless %w[major minor patch].include?(part)

    current = Gem::Version.new(File.read(VERSION_FILE)[/VERSION = "([^"]+)"/, 1])
    segments = current.segments
    index = { "major" => 0, "minor" => 1, "patch" => 2 }.fetch(part)
    segments[index] += 1
    ((index + 1)...segments.length).each { |position| segments[position] = 0 }
    next_version = segments.join(".")

    File.write(VERSION_FILE, File.read(VERSION_FILE).sub(/VERSION = "[^"]+"/, %(VERSION = "#{next_version}")))
    puts "Bumped #{current} -> #{next_version}"
    puts "Add a '## #{next_version} — YYYY-MM-DD' entry to CHANGELOG.md before committing."
  end

  desc "Verify CHANGELOG.md has an entry for the current version"
  task :check_changelog do
    version = File.read(VERSION_FILE)[/VERSION = "([^"]+)"/, 1]
    unless File.read(CHANGELOG_FILE).match?(/^## #{Regexp.escape(version)}\b/)
      abort "CHANGELOG.md has no '## #{version}' entry. Add one before releasing."
    end
    puts "CHANGELOG.md has an entry for version #{version}"
  end
end
