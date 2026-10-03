# frozen_string_literal: true

require "jekyll"

require_relative "compress_flow/version"

module Jekyll
  # Generates .br/.zst/.gz siblings for text assets in the build output so a
  # precompressed-capable static server (e.g. Caddy's
  # `file_server { precompressed gzip br zstd }`) can serve them without
  # per-request compression CPU.
  #
  # Runs on :site, :post_write — enabled only for production builds by
  # default. Configure via `compress_flow:` in _config.yml; the CLI tools
  # (brotli, zstd, gzip) must be installed on the build host.
  module CompressFlow
    FORMATS = {
      "br" => { "tool" => "brotli", "args" => %w[-f -k] },
      "zst" => { "tool" => "zstd", "args" => %w[-f -q -19] },
      "gz" => { "tool" => "gzip", "args" => %w[-f -9 -k] }
    }.freeze

    DEFAULTS = {
      "enabled" => nil, # nil => Jekyll.env == "production"
      "extensions" => %w[html css js json xml svg txt map],
      "formats" => %w[br zst gz],
      "min_size" => 0,
      "fail_on_error" => true
    }.freeze

    module_function

    # Entry point — compress all matching files under +dest+.
    # +config+ is the site's `compress_flow:` mapping (string or symbol keys).
    def run(dest, config = {})
      cfg = DEFAULTS.merge(config.transform_keys(&:to_s))
      return unless enabled?(cfg)

      formats = select_available(cfg)
      target_files(dest, cfg).each do |file|
        formats.each_value { |format| compress(file, format, cfg) }
      end

      Jekyll.logger.info "CompressFlow:", "#{target_files(dest, cfg).size} file(s) x #{formats.keys.join('+')}"
    end

    def enabled?(cfg)
      cfg["enabled"].nil? ? Jekyll.env == "production" : cfg["enabled"]
    end

    # Configured formats, minus unknown names (reported once) and formats
    # whose CLI tool is not installed (reported once, not per file).
    def select_available(cfg)
      unknown = cfg["formats"] - FORMATS.keys
      fail_or_warn(cfg, "unknown formats ignored: #{unknown.join(', ')}") unless unknown.empty?

      FORMATS.select do |name, format|
        next false unless cfg["formats"].include?(name)

        available = tool_available?(format["tool"])
        fail_or_warn(cfg, "#{format['tool']} not installed — skipping .#{name} output") unless available
        available
      end
    end

    def target_files(dest, cfg)
      exts = cfg["extensions"].map { |e| ".#{e.to_s.sub(/\A\./, '')}" }
      min = cfg["min_size"].to_i
      Dir.glob(File.join(dest, "**", "*"))
         .select { |f| File.file?(f) && exts.include?(File.extname(f)) && File.size(f) >= min }
         .sort
    end

    def compress(file, format, cfg)
      ok = system(format["tool"], *format["args"], file, out: File::NULL, err: File::NULL)
      fail_or_warn(cfg, "#{format['tool']} failed on #{file}") unless ok
    end

    def tool_available?(tool)
      system(tool, "--version", out: File::NULL, err: File::NULL)
    rescue Errno::ENOENT
      false
    end

    def fail_or_warn(cfg, message)
      raise Jekyll::Errors::FatalException, "CompressFlow: #{message}" if cfg["fail_on_error"]

      Jekyll.logger.warn "CompressFlow:", message
    end
  end
end

Jekyll::Hooks.register :site, :post_write do |site|
  Jekyll::CompressFlow.run(site.dest, site.config["compress_flow"] || {})
end
