# frozen_string_literal: true

require "jekyll"
require "open3"

require_relative "compress_flow/version"
require_relative "compress_flow/interface"

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
      "br" => { "tool" => "brotli", "args" => %w[-f -k],
                "min_version" => "1.1.0", "version_pattern" => /brotli\s+(\d+(?:\.\d+)+)/ },
      "zst" => { "tool" => "zstd", "args" => %w[-f -q -19],
                 "min_version" => "1.5.5", "version_pattern" => /v(\d+\.\d+\.\d+)/ },
      "gz" => { "tool" => "gzip", "args" => %w[-f -9 -k] }
    }.freeze

    DEFAULT_POST_WRITE_PRIORITY = 10
    POST_WRITE_PRIORITIES = (0..DEFAULT_POST_WRITE_PRIORITY)
    DEFAULTS = {
      "enabled" => nil, # nil => Jekyll.env == "production"
      "priority" => DEFAULT_POST_WRITE_PRIORITY,
      "extensions" => %w[html css js json xml svg txt map],
      "formats" => %w[br zst gz],
      "min_size" => 0,
      "fail_on_error" => true
    }.freeze

    module_function

    def post_write_priority(config)
      priority = config.transform_keys(&:to_s).fetch("priority", DEFAULT_POST_WRITE_PRIORITY)
      return priority if priority.is_a?(Integer) && POST_WRITE_PRIORITIES.cover?(priority)

      raise Jekyll::Errors::FatalException,
            "CompressFlow: compress_flow.priority must be an integer from 0 through 10"
    end

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
        cfg["formats"].include?(name) && tool_ok?(name, format, cfg)
      end
    end

    # Installed and new enough? Reports a missing or too-old tool once via
    # fail_or_warn — never per file.
    def tool_ok?(name, format, cfg)
      detected = tool_version(format["tool"], format["version_pattern"])
      if detected.nil?
        fail_or_warn(cfg, "#{format['tool']} not installed — cannot generate .#{name} output")
        return false
      end

      minimum = format["min_version"]
      return true unless minimum && detected.is_a?(Gem::Version) && detected < Gem::Version.new(minimum)

      fail_or_warn(cfg, "#{format['tool']} #{detected} found — need >= #{minimum} for .#{name} output")
      false
    end

    def target_files(dest, cfg)
      exts = cfg["extensions"].map { |e| ".#{e.to_s.sub(/\A\./, '')}" }
      min = cfg["min_size"].to_i
      Dir.glob(File.join(dest, "**", "*"))
         .select { |f| File.file?(f) && exts.include?(File.extname(f)) && File.size(f) >= min }
         .sort
    end

    def compress(file, format, cfg)
      # Array-form system(): no shell — tool/args are literals from the frozen
      # FORMATS table; file is a data argument globbed under the build dest.
      # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec
      ok = system(format["tool"], *format["args"], file, out: File::NULL, err: File::NULL)
      fail_or_warn(cfg, "#{format['tool']} failed on #{file}") unless ok
    end

    # Detected Gem::Version of +tool+, :unversioned when installed but the
    # banner could not be parsed (or no pattern is defined — e.g. Apple gzip
    # vs GNU gzip use incomparable version strings), nil when not installed.
    def tool_version(tool, pattern)
      # Array-form capture2e: no shell — tool is a literal from frozen FORMATS.
      # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec
      out, status = Open3.capture2e(tool, "--version")
      return nil unless status.success?
      return :unversioned unless pattern && (match = out.match(pattern))

      Gem::Version.new(match[1])
    rescue Errno::ENOENT
      nil
    rescue ArgumentError
      :unversioned
    end

    def fail_or_warn(cfg, message)
      raise Jekyll::Errors::FatalException, "CompressFlow: #{message}" if cfg["fail_on_error"]

      Jekyll.logger.warn "CompressFlow:", message
    end
  end
end

Jekyll::CompressFlow::POST_WRITE_PRIORITIES.each do |hook_priority|
  registered_priority = hook_priority
  Jekyll::Hooks.register :site, :post_write, priority: registered_priority do |site|
    config = site.config["compress_flow"] || {}
    next unless Jekyll::CompressFlow.post_write_priority(config) == registered_priority

    Jekyll::CompressFlow.run(site.dest, config)
  end
end
