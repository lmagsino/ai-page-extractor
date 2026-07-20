require "test_helper"

class RateLimitTest < ActionDispatch::IntegrationTest
  setup do
    @original_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
  end

  teardown do
    Rack::Attack.cache.store = @original_store
    Rack::Attack.enabled = false
  end

  def submit
    post scrapes_path, params: { scrape_job: { url: "https://example.com/x", prompt: "extract" } }
  end

  test "allows submits up to the per-IP limit, then returns 429" do
    10.times { submit }
    assert_response :redirect # 10th still allowed

    submit
    assert_response :too_many_requests
    assert_match(/cost-limited demo/, @response.body)
  end

  test "does not throttle GET requests" do
    20.times { get new_scrape_path }
    assert_response :success
  end
end
