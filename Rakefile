# frozen_string_literal: true

# bundler/gem_tasks provides the bare `release` task that
# rubygems/release-gem invokes in the tag workflow (OIDC-minted
# credentials — that IS trusted publishing). The local tag+push
# task is named `release_tag` so the two can never collide.
require "bundler/gem_tasks"

VERSION_FILE = File.expand_path("lib/jekyll/compress_flow/version.rb", __dir__)
CHANGELOG_FILE = File.expand_path("CHANGELOG.md", __dir__)
GEMSPEC_FILE = File.expand_path("jekyll-compress-flow.gemspec", __dir__)

task default: :quality

desc "Run all quality checks (style, docs, security, tests)"
task quality: %i[rubocop markdownlint bundler_audit spec build_gem]

desc "Run quick checks (style + tests only)"
task quick: %i[rubocop spec]

desc "Run the test suite and syntax checks (CI)"
task :ci do
  sh "bundle exec rspec"
  sh "bundle exec rubocop"
  sh "npx --yes markdownlint-cli2@0.23.2"
  Dir["lib/**/*.rb"].each { |file| sh "bundle exec ruby -c #{file}" }
  sh "gem build #{GEMSPEC_FILE}"
end

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

desc "Tag and push release v<version> (tags stay coupled to releases)"
task :release_tag, [:version] do |_, args|
  v = args[:version] or abort "usage: bundle exec rake 'release_tag[1.2.3]'"
  abort "version.rb is not #{v} — run 'version:bump' first" \
    unless File.read(VERSION_FILE)[/VERSION = "([^"]+)"/, 1] == v
  Rake::Task["version:check_changelog"].invoke
  abort "working tree not clean — commit or stash first" unless `git status --porcelain`.empty?
  abort "not on main" unless `git branch --show-current`.strip == "main"
  Rake::Task[:quality].invoke
  sh "git tag -a v#{v} -m 'Release #{v}'"
  sh "git push origin main v#{v}"
  puts "Tagged and pushed v#{v} — the release workflow builds and publishes to RubyGems via trusted publishing."
end
