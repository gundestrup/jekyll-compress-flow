# frozen_string_literal: true

require "spec_helper"
require "zlib"

RSpec.describe Jekyll::CompressFlow do
  let(:config) { { "enabled" => true } }
  let(:dest) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dest) }

  def write_file(name, content = "x" * 1024)
    path = File.join(dest, name)
    FileUtils.mkdir_p File.dirname(path)
    File.write(path, content)
    path
  end

  def siblings(name)
    %w[br zst gz].map { |ext| File.join(dest, "#{name}.#{ext}") }
  end

  def generated
    Dir.glob(File.join(dest, "**", "*.{br,zst,gz}"))
  end

  it "registers a dispatcher after output processors" do
    callbacks = Jekyll::Hooks.instance_variable_get(:@registry).fetch(:site).fetch(:post_write).select do |hook|
      hook.source_location&.first&.end_with?("/lib/jekyll/compress_flow.rb")
    end
    priorities = Jekyll::Hooks.instance_variable_get(:@hook_priority)
    registered = callbacks.map { |hook| -priorities.fetch(hook).first }

    expect(registered).to match_array((0..10).to_a)
    expect(Jekyll::CompressFlow::DEFAULT_POST_WRITE_PRIORITY).to eq(10)
    expect(described_class.post_write_priority({})).to eq(10)
  end

  it "accepts only compression priorities below fingerprinting" do
    expect(described_class.post_write_priority({})).to eq(10)
    expect(described_class.post_write_priority("priority" => 4)).to eq(4)
    expect { described_class.post_write_priority("priority" => 11) }
      .to raise_error(Jekyll::Errors::FatalException)
  end

  it "generates .br/.zst/.gz siblings for text assets" do
    html = write_file("index.html")
    described_class.run(dest, config)
    siblings("index.html").each do |path|
      expect(File.exist?(path)).to be(true), "missing #{path}"
      expect(File.size(path)).to be < File.size(html)
    end
  end

  it "produces siblings that decode back to the original bytes" do
    original = "<html>#{'x' * 500}</html>"
    write_file("index.html", original)
    described_class.run(dest, config)
    expect(`brotli -d -c #{File.join(dest, "index.html.br")}`).to eq(original)
    expect(`zstd -d -c #{File.join(dest, "index.html.zst")} 2>/dev/null`).to eq(original)
    expect(`gzip -d -c #{File.join(dest, "index.html.gz")}`).to eq(original)
  end

  it "skips non-text files and already-compressed siblings" do
    write_file("photo.png")
    write_file("index.html.br")
    described_class.run(dest, config)
    expect(generated).to eq([File.join(dest, "index.html.br")])
  end

  it "does nothing when enabled is false" do
    write_file("index.html")
    described_class.run(dest, "enabled" => false)
    expect(generated).to be_empty
  end

  it "only compresses files at or above min_size" do
    write_file("small.html", "tiny")
    write_file("big.html", "x" * 2048)
    described_class.run(dest, config.merge("min_size" => 100))
    expect(File.exist?(File.join(dest, "small.html.gz"))).to be(false)
    expect(File.exist?(File.join(dest, "big.html.gz"))).to be(true)
  end

  it "accepts symbol-keyed config" do
    write_file("index.html")
    described_class.run(dest, { enabled: true, formats: %w[gz] })
    expect(File.exist?(File.join(dest, "index.html.gz"))).to be(true)
    expect(File.exist?(File.join(dest, "index.html.br"))).to be(false)
  end

  it "limits output to the configured formats" do
    write_file("index.html")
    described_class.run(dest, config.merge("formats" => %w[zst]))
    expect(File.exist?(File.join(dest, "index.html.zst"))).to be(true)
    expect(File.exist?(File.join(dest, "index.html.br"))).to be(false)
  end

  it "aborts on unknown formats when fail_on_error" do
    expect { described_class.run(dest, config.merge("formats" => %w[gz bogus])) }
      .to raise_error(Jekyll::Errors::FatalException, /bogus/)
  end

  it "warns instead of aborting when fail_on_error is false" do
    allow(Jekyll.logger).to receive(:warn)
    described_class.run(dest, config.merge("formats" => %w[gz bogus], "fail_on_error" => false))
    expect(Jekyll.logger).to have_received(:warn).with("CompressFlow:", /bogus/)
  end

  it "aborts when a required tool is missing" do
    allow(described_class).to receive(:tool_version).and_return(nil)
    write_file("index.html")
    expect { described_class.run(dest, config) }
      .to raise_error(Jekyll::Errors::FatalException, /not installed/)
  end

  it "treats a nonexistent binary as unavailable" do
    expect(described_class.tool_version("definitely-missing-cf-tool", /x/)).to be_nil
  end

  it "treats a failed --version probe as not installed" do
    status = instance_double(Process::Status, success?: false)
    allow(Open3).to receive(:capture2e).and_return(["", status])
    expect(described_class.tool_version("brotli", /brotli\s+(\d+(?:\.\d+)+)/)).to be_nil
  end

  it "treats an invalid version string as unversioned" do
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture2e).and_return(["brotli abc", status])
    expect(described_class.tool_version("brotli", /brotli\s+(\S+)/)).to eq(:unversioned)
  end

  it "skips a missing tool in warn mode but keeps supported formats" do
    write_file("index.html")
    allow(described_class).to receive(:tool_version).and_wrap_original do |original, tool, pattern|
      tool == "brotli" ? nil : original.call(tool, pattern)
    end
    allow(Jekyll.logger).to receive(:warn)
    described_class.run(dest, config.merge("fail_on_error" => false))
    expect(File.exist?(File.join(dest, "index.html.br"))).to be(false)
    expect(File.exist?(File.join(dest, "index.html.gz"))).to be(true)
  end

  it "aborts when a tool is older than the minimum" do
    allow(described_class).to receive(:tool_version).and_return(Gem::Version.new("0.1.0"))
    write_file("index.html")
    expect { described_class.run(dest, config) }
      .to raise_error(Jekyll::Errors::FatalException, /need >= /)
  end

  it "skips an outdated tool but keeps supported formats" do
    write_file("index.html")
    allow(described_class).to receive(:tool_version).and_wrap_original do |original, tool, pattern|
      tool == "zstd" ? Gem::Version.new("1.0.0") : original.call(tool, pattern)
    end
    allow(Jekyll.logger).to receive(:warn)
    described_class.run(dest, config.merge("fail_on_error" => false))
    expect(File.exist?(File.join(dest, "index.html.zst"))).to be(false)
    expect(File.exist?(File.join(dest, "index.html.gz"))).to be(true)
    expect(Jekyll.logger).to have_received(:warn).with("CompressFlow:", /need >= /).at_least(:once)
  end

  it "treats an unparseable version banner as installed" do
    write_file("index.html")
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture2e).and_return(["strange banner", status])
    described_class.run(dest, config)
    expect(generated).not_to be_empty
  end

  it "warns when a compressor fails on a file" do
    write_file("index.html")
    allow(described_class).to receive(:system).and_return(false)
    allow(Jekyll.logger).to receive(:warn)
    described_class.run(dest, config.merge("fail_on_error" => false))
    expect(Jekyll.logger).to have_received(:warn).with("CompressFlow:", /failed on/).at_least(:once)
  end

  context "when running inside a real jekyll build" do
    let(:src) { Dir.mktmpdir }

    after { FileUtils.remove_entry(src) }

    def build_site(env, config = {})
      old_env = ENV.fetch("JEKYLL_ENV", nil)
      ENV["JEKYLL_ENV"] = env
      site_config = { "source" => src, "destination" => dest, "quiet" => true }.merge(config)
      Jekyll::Site.new(Jekyll.configuration(site_config)).process
    ensure
      old_env.nil? ? ENV.delete("JEKYLL_ENV") : ENV["JEKYLL_ENV"] = old_env
    end

    it "the post_write hook emits siblings in production" do
      File.write(File.join(src, "index.html"), "<html>#{'x' * 500}</html>")
      build_site("production")
      siblings("index.html").each do |path|
        expect(File.exist?(path)).to be(true), "missing #{path}"
      end
    end

    it "the hook stays idle outside production" do
      File.write(File.join(src, "index.html"), "<html>#{'x' * 500}</html>")
      build_site("development")
      expect(generated).to be_empty
    end

    it "uses a site-configured compression priority" do
      File.write(File.join(src, "index.html"), "<html>#{'x' * 500}</html>")
      compressed_before_hook = nil
      probe = proc { |_site| compressed_before_hook = File.exist?(File.join(dest, "index.html.gz")) }
      hooks = Jekyll::Hooks.instance_variable_get(:@registry).fetch(:site).fetch(:post_write)
      priorities = Jekyll::Hooks.instance_variable_get(:@hook_priority)
      Jekyll::Hooks.register(:site, :post_write, priority: 9, &probe)

      begin
        build_site("production", "compress_flow" => { "formats" => %w[gz], "priority" => 8 })
      ensure
        hooks.delete(probe)
        priorities.delete(probe)
      end

      expect(compressed_before_hook).to be(false)
      expect(File.exist?(File.join(dest, "index.html.gz"))).to be(true)
    end

    it "emits only the configured formats in a real build" do
      File.write(File.join(src, "index.html"), "<html>#{'x' * 500}</html>")
      build_site("production", "compress_flow" => { "formats" => %w[gz] })
      expect(File.exist?(File.join(dest, "index.html.gz"))).to be(true)
      expect(File.exist?(File.join(dest, "index.html.br"))).to be(false)
      expect(File.exist?(File.join(dest, "index.html.zst"))).to be(false)
    end

    it "regenerates siblings with the new content on rebuild" do
      File.write(File.join(src, "index.html"), "<html>v1-#{'x' * 500}</html>")
      build_site("production", "compress_flow" => { "formats" => %w[gz] })
      first = Zlib::GzipReader.open(File.join(dest, "index.html.gz"), &:read)

      File.write(File.join(src, "index.html"), "<html>v2-#{'y' * 500}</html>")
      FileUtils.touch(File.join(src, "index.html"), mtime: Time.now + 10)
      build_site("production", "compress_flow" => { "formats" => %w[gz] })
      second = Zlib::GzipReader.open(File.join(dest, "index.html.gz"), &:read)

      expect(first).to include("v1-")
      expect(second).to include("v2-")
    end

    it "uses each site's own formats when two sites build in one process" do
      File.write(File.join(src, "index.html"), "<html>#{'x' * 500}</html>")
      dest_b = Dir.mktmpdir
      results = nil
      begin
        build_site("production", "compress_flow" => { "formats" => %w[gz] })
        old_env = ENV.fetch("JEKYLL_ENV", nil)
        ENV["JEKYLL_ENV"] = "production"
        Jekyll::Site.new(Jekyll.configuration(
                           "source" => src, "destination" => dest_b, "quiet" => true,
                           "compress_flow" => { "formats" => %w[zst] }
                         )).process
        results = %w[gz zst].map { |ext| File.exist?(File.join(dest_b, "index.html.#{ext}")) }
      ensure
        old_env.nil? ? ENV.delete("JEKYLL_ENV") : ENV["JEKYLL_ENV"] = old_env
        FileUtils.remove_entry(dest_b)
      end

      expect(File.exist?(File.join(dest, "index.html.gz"))).to be(true)
      expect(File.exist?(File.join(dest, "index.html.zst"))).to be(false)
      expect(results).to eq([false, true])
    end

    it "skips a missing compressor in warn mode but still emits other formats" do
      File.write(File.join(src, "index.html"), "<html>#{'x' * 500}</html>")
      allow(described_class).to receive(:tool_version).and_wrap_original do |original, tool, pattern|
        tool == "brotli" ? nil : original.call(tool, pattern)
      end
      allow(Jekyll.logger).to receive(:warn)

      build_site("production", "compress_flow" => { "fail_on_error" => false })

      expect(File.exist?(File.join(dest, "index.html.br"))).to be(false)
      expect(File.exist?(File.join(dest, "index.html.zst"))).to be(true)
      expect(File.exist?(File.join(dest, "index.html.gz"))).to be(true)
      expect(Jekyll.logger).to have_received(:warn).with("CompressFlow:", /not installed/)
    end

    it "aborts the build when a configured compressor is missing" do
      File.write(File.join(src, "index.html"), "<html>#{'x' * 500}</html>")
      allow(described_class).to receive(:tool_version).and_return(nil)

      expect { build_site("production") }
        .to raise_error(Jekyll::Errors::FatalException, /not installed/)
    end
  end
end
