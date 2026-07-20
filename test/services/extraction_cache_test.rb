require "test_helper"

class ExtractionCacheTest < ActiveSupport::TestCase
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @original_cache }

  test "read returns nil on a miss" do
    assert_nil ExtractionCache.read("https://a.com", "extract names")
  end

  test "write then read round-trips the result" do
    result = { "items" => [ { "name" => "A" } ], "notes" => "" }
    ExtractionCache.write("https://a.com", "extract names", result)
    assert_equal result, ExtractionCache.read("https://a.com", "extract names")
  end

  test "key is stable for the same url and prompt" do
    assert_equal ExtractionCache.key("https://a.com", "p"), ExtractionCache.key("https://a.com", "p")
  end

  test "key differs when url or prompt differs" do
    base = ExtractionCache.key("https://a.com", "p")
    assert_not_equal base, ExtractionCache.key("https://b.com", "p")
    assert_not_equal base, ExtractionCache.key("https://a.com", "different")
  end

  test "different (url, prompt) pairs do not collide" do
    ExtractionCache.write("https://a.com", "p1", { "items" => [ { "x" => 1 } ] })
    ExtractionCache.write("https://a.com", "p2", { "items" => [ { "x" => 2 } ] })
    assert_equal 1, ExtractionCache.read("https://a.com", "p1")["items"].first["x"]
    assert_equal 2, ExtractionCache.read("https://a.com", "p2")["items"].first["x"]
  end
end
