# frozen_string_literal: true

require "simplecov"
require "simplecov-cobertura" if ENV["CI"]

SimpleCov.start do
  enable_coverage :branch
  add_filter "/spec/"
  minimum_coverage line: 85, branch: 75 if ENV["CI"] || ENV["COVERAGE"]
  formatter SimpleCov::Formatter::CoberturaFormatter if ENV["CI"]
end

require "jekyll-compress-flow"
require "tmpdir"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.order = :random
  Kernel.srand config.seed
end
