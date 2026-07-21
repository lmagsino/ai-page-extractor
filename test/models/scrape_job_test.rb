require "test_helper"

class ScrapeJobTest < ActiveSupport::TestCase
  def valid_attrs(overrides = {})
    { url: "https://example.com/products", prompt: "Extract every product name" }.merge(overrides)
  end

  test "valid with url and prompt" do
    assert ScrapeJob.new(valid_attrs).valid?
  end

  test "requires url" do
    job = ScrapeJob.new(valid_attrs(url: nil))
    assert_not job.valid?
    assert_includes job.errors[:url], "can't be blank"
  end

  test "requires a well-formed http(s) url" do
    assert_not ScrapeJob.new(valid_attrs(url: "not-a-url")).valid?
    assert_not ScrapeJob.new(valid_attrs(url: "ftp://example.com")).valid?
    assert ScrapeJob.new(valid_attrs(url: "http://example.com")).valid?
    assert ScrapeJob.new(valid_attrs(url: "https://example.com")).valid?
  end

  test "requires prompt" do
    job = ScrapeJob.new(valid_attrs(prompt: nil))
    assert_not job.valid?
    assert_includes job.errors[:prompt], "can't be blank"
  end

  test "defaults to pending and not featured" do
    job = ScrapeJob.create!(valid_attrs)
    assert job.pending?
    assert_not job.featured?
  end

  test "status enum exposes predicates and bang setters" do
    job = ScrapeJob.create!(valid_attrs)
    job.fetching!
    assert job.fetching?
    job.extracting!
    assert job.extracting?
    job.done!
    assert job.done?
  end

  test "an unknown status fails validation (does not raise)" do
    job = ScrapeJob.new(valid_attrs)
    job.status = "bogus"
    assert_not job.valid?
    assert_includes job.errors[:status], "is not included in the list"
  end

  test "gallery scope returns only featured, newest first" do
    old_featured = ScrapeJob.create!(valid_attrs(featured: true, created_at: 2.days.ago))
    new_featured = ScrapeJob.create!(valid_attrs(featured: true, created_at: 1.hour.ago))
    ScrapeJob.create!(valid_attrs(featured: false))

    assert_equal [ new_featured, old_featured ], ScrapeJob.gallery.to_a
  end

  test "result round-trips through result_json" do
    job = ScrapeJob.new(valid_attrs)
    job.result = { "items" => [ { "name" => "Widget" } ], "notes" => "" }
    assert_equal [ { "name" => "Widget" } ], job.result["items"]
    assert_equal "", job.result["notes"]
  end

  test "result is nil when result_json is blank" do
    assert_nil ScrapeJob.new(valid_attrs).result
  end

  test "result is nil when result_json is unparseable" do
    job = ScrapeJob.new(valid_attrs)
    job.result_json = "{not valid json"
    assert_nil job.result
  end

  test "result= nil clears result_json" do
    job = ScrapeJob.new(valid_attrs(result_json: '{"items":[]}'))
    job.result = nil
    assert_nil job.result_json
  end

  test "result_items and result_columns are empty without a result" do
    job = ScrapeJob.new(valid_attrs)
    assert_empty job.result_items
    assert_empty job.result_columns
  end

  test "result_columns is the union of all item keys (B3)" do
    job = ScrapeJob.new(valid_attrs)
    job.result = { "items" => [
      { "name" => "A", "price" => "$1" },
      { "name" => "B", "stock" => "3" } # different key set
    ], "notes" => "" }

    assert_equal %w[name price stock], job.result_columns
    assert_equal 2, job.result_items.length
  end

  test "updating broadcasts a panel replace to the job's stream" do
    job = ScrapeJob.create!(valid_attrs)
    captured = {}
    job.define_singleton_method(:broadcast_replace_to) do |*args, **kwargs|
      captured[:stream] = args
      captured[:kwargs] = kwargs
    end

    job.update!(status: "fetching")

    assert_equal [ job ], captured[:stream]
    assert_equal job.panel_dom_id, captured[:kwargs][:target]
    assert_equal "scrapes/panel", captured[:kwargs][:partial]
  end
end
