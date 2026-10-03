# frozen_string_literal: true

require "spec_helper"

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

    def build_site(env)
      old_env = ENV.fetch("JEKYLL_ENV", nil)
      ENV["JEKYLL_ENV"] = env
      Jekyll::Site.new(
        Jekyll.configuration(
          "source" => src,
          "destination" => dest,
          "quiet" => true
        )
      ).process
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
  end
end
