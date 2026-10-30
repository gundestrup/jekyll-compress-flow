# frozen_string_literal: true

require "spec_helper"
require "open3"
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

  it "dispatches at every allowed priority via the public hook seam" do
    (0..10).each do |priority|
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "index.html"), "x" * 1024)
        site = Struct.new(:config, :dest).new(
          { "compress_flow" => { "enabled" => true, "formats" => %w[gz], "priority" => priority } }, dir
        )
        Jekyll::Hooks.trigger(:site, :post_write, site)
        expect(File.exist?(File.join(dir, "index.html.gz"))).to be(true), "priority #{priority} did not dispatch"
      end
    end
    expect(Jekyll::CompressFlow::DEFAULT_POST_WRITE_PRIORITY).to eq(10)
    expect(described_class.post_write_priority({})).to eq(10)
  end

  it "accepts only compression priorities below fingerprinting" do
    expect(described_class.post_write_priority({})).to eq(10)
    expect(described_class.post_write_priority("priority" => 4)).to eq(4)
    expect(described_class.post_write_priority(priority: 4)).to eq(4)
    expect { described_class.post_write_priority("priority" => 11) }
      .to raise_error(Jekyll::Errors::FatalException)
    expect { described_class.post_write_priority("priority" => "4") }
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
    decoded = siblings("index.html").zip(%w[brotli zstd gzip]).map do |path, tool|
      Open3.capture3(tool, "-d", "-c", path).first
    end
    expect(decoded).to all(eq(original))
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

  it "honors a custom extensions list" do
    write_file("index.html")
    write_file("data.foo")
    described_class.run(dest, config.merge("extensions" => %w[foo], "formats" => %w[gz]))
    expect(File.exist?(File.join(dest, "data.foo.gz"))).to be(true)
    expect(File.exist?(File.join(dest, "index.html.gz"))).to be(false)
  end

  it "compresses every default text extension, not just html" do
    %w[css js map].each { |ext| write_file("asset.#{ext}") }
    described_class.run(dest, config.merge("formats" => %w[gz]))
    %w[css js map].each do |ext|
      expect(File.exist?(File.join(dest, "asset.#{ext}.gz"))).to be(true), "missing .gz for .#{ext}"
    end
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
    # Wraps jekyll_build with a JEKYLL_ENV override — the plugin only emits
    # siblings in production builds.
    def build_env_site(env, config: {}, files: {}, &block)
      old_env = ENV.fetch("JEKYLL_ENV", nil)
      ENV["JEKYLL_ENV"] = env
      jekyll_build(config: config, files: files, &block)
    ensure
      old_env.nil? ? ENV.delete("JEKYLL_ENV") : ENV["JEKYLL_ENV"] = old_env
    end

    def output_path(output_files, name)
      File.join(output_files.dir, name)
    end

    let(:index_file) { { "index.html" => "<html>#{'x' * 500}</html>" } }

    it "the post_write hook emits siblings in production" do
      build_env_site("production", files: index_file) do |_site, output_files|
        %w[br zst gz].each do |ext|
          path = output_path(output_files, "index.html.#{ext}")
          expect(File.exist?(path)).to be(true), "missing #{path}"
        end
      end
    end

    it "the hook stays idle outside production" do
      build_env_site("development", files: index_file) do |_site, output_files|
        expect(Dir.glob(File.join(output_files.dir, "**", "*.{br,zst,gz}"))).to be_empty
      end
    end

    it "uses a site-configured compression priority" do
      compressed_before_hook = nil
      active = true
      # Jekyll has no public unregister — leave the probe registered and
      # disarm it after the build (see engineering-memory lesson).
      probe = proc { |site| compressed_before_hook = File.exist?(File.join(site.dest, "index.html.gz")) if active }
      Jekyll::Hooks.register(:site, :post_write, priority: 9, &probe)

      begin
        build_env_site(
          "production",
          config: { "compress_flow" => { "formats" => %w[gz], "priority" => 8 } },
          files: index_file
        ) do |_site, output_files|
          expect(File.exist?(output_path(output_files, "index.html.gz"))).to be(true)
        end
      ensure
        active = false
      end

      expect(compressed_before_hook).to be(false)
    end

    it "emits only the configured formats in a real build" do
      build_env_site(
        "production",
        config: { "compress_flow" => { "formats" => %w[gz] } },
        files: index_file
      ) do |_site, output_files|
        expect(File.exist?(output_path(output_files, "index.html.gz"))).to be(true)
        expect(File.exist?(output_path(output_files, "index.html.br"))).to be(false)
        expect(File.exist?(output_path(output_files, "index.html.zst"))).to be(false)
      end
    end

    it "skips a missing compressor in warn mode but still emits other formats" do
      allow(described_class).to receive(:tool_version).and_wrap_original do |original, tool, pattern|
        tool == "brotli" ? nil : original.call(tool, pattern)
      end
      allow(Jekyll.logger).to receive(:warn)

      build_env_site(
        "production",
        config: { "compress_flow" => { "fail_on_error" => false } },
        files: index_file
      ) do |_site, output_files|
        expect(File.exist?(output_path(output_files, "index.html.br"))).to be(false)
        expect(File.exist?(output_path(output_files, "index.html.zst"))).to be(true)
        expect(File.exist?(output_path(output_files, "index.html.gz"))).to be(true)
      end

      expect(Jekyll.logger).to have_received(:warn).with("CompressFlow:", /not installed/)
    end

    it "aborts the build when a configured compressor is missing" do
      allow(described_class).to receive(:tool_version).and_return(nil)

      expect do
        build_env_site("production", files: index_file) { |_site, _output_files| nil }
      end.to raise_error(JekyllTestHarness::SiteBuildError, /not installed/)
    end

    # The harness builds each site in a fresh temporary directory, so
    # examples that mutate the source or share one source/destination across
    # builds keep their own scaffolding.
    context "with builds sharing one source tree" do
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
    end
  end
end
