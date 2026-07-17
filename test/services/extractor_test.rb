require "test_helper"

class ExtractorTest < ActiveSupport::TestCase
  # Minimal stand-in for a Faraday response.
  FakeResp = Struct.new(:status, :body) do
    def success? = (200..299).cover?(status)
  end

  def tool_use_body(items:, notes: "")
    {
      "content" => [
        { "type" => "tool_use", "name" => "extract_data",
          "input" => { "items" => items, "notes" => notes } }
      ]
    }.to_json
  end

  def build(markdown: "# Page", prompt: "extract names")
    Extractor.new(markdown: markdown, prompt: prompt)
  end

  setup { ENV["ANTHROPIC_API_KEY"] = "test-key" }
  teardown { ENV.delete("ANTHROPIC_API_KEY") }

  test "returns the tool_use input hash on success" do
    ext = build
    resp = FakeResp.new(200, tool_use_body(items: [ { "name" => "Widget" } ], notes: ""))
    ext.define_singleton_method(:perform_request) { |_body| resp }

    result = ext.call
    assert_equal [ { "name" => "Widget" } ], result["items"]
    assert_equal "", result["notes"]
  end

  test "raises without an API key" do
    ENV.delete("ANTHROPIC_API_KEY")
    err = assert_raises(Extractor::ExtractionError) { build.call }
    assert_match(/ANTHROPIC_API_KEY/, err.message)
  end

  test "raises on a non-2xx response" do
    ext = build
    ext.define_singleton_method(:perform_request) { |_b| FakeResp.new(400, "bad request") }
    assert_raises(Extractor::ExtractionError) { ext.call }
  end

  test "raises when the model returns no tool_use block" do
    ext = build
    body = { "content" => [ { "type" => "text", "text" => "here is your data" } ] }.to_json
    ext.define_singleton_method(:perform_request) { |_b| FakeResp.new(200, body) }
    err = assert_raises(Extractor::ExtractionError) { ext.call }
    assert_match(/extract_data/, err.message)
  end

  test "raises on unparseable response body" do
    ext = build
    ext.define_singleton_method(:perform_request) { |_b| FakeResp.new(200, "{not json") }
    assert_raises(Extractor::ExtractionError) { ext.call }
  end

  test "retries on 503 then succeeds" do
    ext = build
    ext.define_singleton_method(:retry_delay) { |_a| 0 } # no real sleeping
    calls = 0
    good = tool_use_body(items: [ { "x" => 1 } ])
    ext.define_singleton_method(:perform_request) do |_b|
      calls += 1
      calls < 3 ? FakeResp.new(503, "unavailable") : FakeResp.new(200, good)
    end

    result = ext.call
    assert_equal 3, calls
    assert_equal [ { "x" => 1 } ], result["items"]
  end

  test "gives up after exhausting retries on persistent 5xx" do
    ext = build
    ext.define_singleton_method(:retry_delay) { |_a| 0 }
    ext.define_singleton_method(:perform_request) { |_b| FakeResp.new(503, "still down") }
    assert_raises(Extractor::ExtractionError) { ext.call }
  end

  test "request body uses tool-use with the current model and a generous token budget" do
    body = build.send(:request_body)
    assert_equal "claude-sonnet-5", body[:model]
    assert_operator body[:max_tokens], :>=, 8192
    assert_equal "extract_data", body[:tool_choice][:name]
    assert_equal "extract_data", body[:tools].first[:name]
    assert_includes body[:tools].first[:input_schema][:required], "items"
  end
end
