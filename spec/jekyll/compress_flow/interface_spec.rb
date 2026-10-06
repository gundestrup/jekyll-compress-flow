# frozen_string_literal: true

require "spec_helper"
require "yaml"

RSpec.describe Jekyll::CompressFlow::Interface do
  let(:root) { File.expand_path("../../..", __dir__) }
  let(:interface) { described_class.to_h }

  it "matches the committed interface.yml" do
    manifest = YAML.load_file(File.join(root, "interface.yml"))
    expect(manifest).to eq(interface)
  end

  it "declares no tags — this gem registers none with Liquid" do
    owned = Liquid::Template.tags.select do |_name, klass|
      klass.to_s.start_with?("Jekyll::CompressFlow")
    end.map(&:first)
    expect(owned).to be_empty
    expect(interface["tags"]).to be_empty
  end

  it "declares exactly the config keys DEFAULTS defines" do
    expect(interface.dig("config", "compress_flow"))
      .to eq(Jekyll::CompressFlow::DEFAULTS.keys.sort)
  end

  it "documents every config key and enum value" do
    docs = Dir[File.join(root, "*.md")].map { |f| File.read(f) }.join("\n")

    missing = []
    interface["config"].each do |section, keys|
      keys.each do |key|
        missing << "#{section} config `#{key}`" unless docs.match?(/\b#{key}\b/)
      end
    end
    interface["enums"].each do |setting, values|
      values.each do |value|
        missing << "#{setting} value `#{value}`" unless docs.match?(/\b#{Regexp.escape(value)}\b/)
      end
    end

    expect(missing).to be_empty,
                       "interface items missing from docs:\n  #{missing.join("\n  ")}"
  end
end
