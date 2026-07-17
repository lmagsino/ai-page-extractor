require "test_helper"

class ValidatorTest < ActiveSupport::TestCase
  test "accepts items array of hashes with a notes string" do
    data = { "items" => [{ "name" => "Widget", "price" => "$9" }], "notes" => "found 1" }
    result = Validator.call(data)
    assert_equal 1, result[:items].length
  end

  # B1 regression: the extractor is instructed it MAY return notes: "".
  # filled(:string) rejected this and failed well-behaved jobs.
  test "accepts an empty notes string (B1 regression)" do
    data = { "items" => [{ "name" => "Widget" }], "notes" => "" }
    assert_nothing_raised { Validator.call(data) }
  end

  test "accepts a missing notes key (optional)" do
    assert_nothing_raised { Validator.call({ "items" => [{ "a" => 1 }] }) }
  end

  test "accepts a null notes value" do
    assert_nothing_raised { Validator.call({ "items" => [{ "a" => 1 }], "notes" => nil }) }
  end

  test "accepts an empty items array" do
    assert_nothing_raised { Validator.call({ "items" => [], "notes" => "nothing here" }) }
  end

  test "rejects when items is missing" do
    assert_raises(Validator::ValidationError) { Validator.call({ "notes" => "x" }) }
  end

  test "rejects when items is not an array" do
    assert_raises(Validator::ValidationError) { Validator.call({ "items" => "nope" }) }
  end

  test "rejects when items contains non-hash entries" do
    assert_raises(Validator::ValidationError) { Validator.call({ "items" => ["a", "b"] }) }
  end
end
