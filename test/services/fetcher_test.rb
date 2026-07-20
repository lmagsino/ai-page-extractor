require "test_helper"

class FetcherTest < ActiveSupport::TestCase
  # ---- SSRF guard (offline: literal IPs need no DNS) ----

  test "blocks loopback IPv4" do
    err = assert_raises(Fetcher::BlockedError) { Fetcher.call("http://127.0.0.1/admin") }
    assert_match(/private or internal/, err.message)
  end

  test "blocks loopback IPv6" do
    assert_raises(Fetcher::BlockedError) { Fetcher.call("http://[::1]/") }
  end

  test "blocks private ranges" do
    assert_raises(Fetcher::BlockedError) { Fetcher.call("http://10.0.0.1/") }
    assert_raises(Fetcher::BlockedError) { Fetcher.call("http://192.168.1.1/") }
    assert_raises(Fetcher::BlockedError) { Fetcher.call("http://172.16.0.1/") }
  end

  test "blocks the cloud metadata endpoint" do
    assert_raises(Fetcher::BlockedError) { Fetcher.call("http://169.254.169.254/latest/meta-data/") }
  end

  test "blocks non-http(s) schemes" do
    assert_raises(Fetcher::BlockedError) { Fetcher.call("ftp://example.com/") }
    assert_raises(Fetcher::BlockedError) { Fetcher.call("file:///etc/passwd") }
  end

  test "blocks garbage input" do
    assert_raises(Fetcher::BlockedError) { Fetcher.call("not a url") }
  end

  # ---- sufficiently_rendered? logic (pure) ----

  test "sufficiently_rendered? is false for empty/nil" do
    f = Fetcher.new("http://example.com")
    assert_not f.sufficiently_rendered?(nil)
    assert_not f.sufficiently_rendered?("")
  end

  test "sufficiently_rendered? true for text-heavy html" do
    f = Fetcher.new("http://example.com")
    assert f.sufficiently_rendered?("<html><body>#{"real content " * 50}</body></html>")
  end

  test "sufficiently_rendered? false for a script-heavy JS shell" do
    f = Fetcher.new("http://example.com")
    shell = "<html><body><div id='root'></div>#{"<script>x=1;</script>" * 200}</body></html>"
    assert_not f.sufficiently_rendered?(shell)
  end

  # ---- fetch flow (network methods overridden per-instance) ----
  # Singleton-method overrides keep these hermetic (no network, no Chrome).

  def fetcher_with_guard_stubbed
    f = Fetcher.new("http://example.com")
    def f.parse_and_guard!(_url) = URI.parse("http://example.com")
    def f.enforce_politeness!(_uri) = nil # robots + throttle covered separately
    f
  end

  test "raises when robots.txt disallows the path" do
    f = Fetcher.new("http://example.com/private")
    def f.parse_and_guard!(_url) = URI.parse("http://example.com/private")
    stub_class_method(RobotsPolicy, :allowed?, ->(_uri, **) { false }) do
      assert_raises(Fetcher::DisallowedByRobotsError) { f.call }
    end
  end

  test "returns static html when sufficiently rendered" do
    f = fetcher_with_guard_stubbed
    def f.fetch_static(_uri) = "<html><body>#{"content " * 50}</body></html>"
    assert_includes f.call, "content"
  end

  test "falls back to browser when static html is a thin shell" do
    f = fetcher_with_guard_stubbed
    def f.fetch_static(_uri) = "<html><body><div id='root'></div></body></html>"
    def f.fetch_with_browser(_uri) = "<html><body>rendered by chrome</body></html>"
    assert_includes f.call, "rendered by chrome"
  end

  test "falls back to browser when static fetch raises Faraday error" do
    f = fetcher_with_guard_stubbed
    def f.fetch_static(_uri) = raise(Faraday::ConnectionFailed, "refused")
    def f.fetch_with_browser(_uri) = "<html><body>browser saved it</body></html>"
    assert_includes f.call, "browser saved it"
  end

  test "raises FetchError when both static and browser fail" do
    f = fetcher_with_guard_stubbed
    def f.fetch_static(_uri) = raise(Faraday::ConnectionFailed, "refused")
    def f.fetch_with_browser(_uri) = raise(StandardError, "chrome crashed")
    assert_raises(Fetcher::FetchError) { f.call }
  end
end
