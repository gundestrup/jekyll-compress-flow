# frozen_string_literal: true

module Jekyll
  module CompressFlow
    # Machine-readable description of the plugin's public interface:
    # config keys and enum values (this plugin registers no Liquid tags).
    # `rake interface` writes this as interface.yml (shipped in the gem) so
    # tooling like editor extensions can consume it without parsing Ruby.
    module Interface
      def self.to_h
        {
          "gem" => "jekyll-compress-flow",
          "version" => VERSION,
          "tags" => {},
          "filters" => [],
          "config" => { "compress_flow" => DEFAULTS.keys.sort },
          "enums" => { "formats" => FORMATS.keys.sort }
        }
      end
    end
  end
end
