require "test_helper"

class ThrottleTest < ActiveSupport::TestCase
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @original_cache }

  test "first request to a host does not pause" do
    paused = []
    stub_class_method(Throttle, :pause, ->(s) { paused << s }) do
      Throttle.wait("example.com", now: 1000.0)
    end
    assert_empty paused
  end

  test "a second request within the interval pauses for the remainder" do
    paused = []
    stub_class_method(Throttle, :pause, ->(s) { paused << s }) do
      Throttle.wait("example.com", now: 1000.0)
      Throttle.wait("example.com", now: 1000.3) # 0.3s later
    end
    assert_equal 1, paused.size
    assert_in_delta 0.7, paused.first, 0.001
  end

  test "a request after the interval does not pause" do
    paused = []
    stub_class_method(Throttle, :pause, ->(s) { paused << s }) do
      Throttle.wait("example.com", now: 1000.0)
      Throttle.wait("example.com", now: 1002.0) # 2s later
    end
    assert_empty paused
  end

  test "different hosts are tracked independently" do
    paused = []
    stub_class_method(Throttle, :pause, ->(s) { paused << s }) do
      Throttle.wait("a.com", now: 1000.0)
      Throttle.wait("b.com", now: 1000.1) # different host, no pause
    end
    assert_empty paused
  end
end
