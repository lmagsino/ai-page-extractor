require "test_helper"

class ScrapeJobProcessorTest < ActiveSupport::TestCase
  # Swap a class method for the duration of the block, then restore it.
  def stub_class_method(klass, method, impl)
    original = klass.method(method)
    klass.define_singleton_method(method, impl)
    yield
  ensure
    klass.define_singleton_method(method, original)
  end

  def new_job
    ScrapeJob.create!(url: "https://example.com/products", prompt: "extract product names")
  end

  # Stubs Fetcher + Extractor (the external calls); Cleaner + Validator run for real.
  def with_pipeline(html:, extraction:)
    stub_class_method(Fetcher, :call, ->(_url) { html }) do
      stub_class_method(Extractor, :call, ->(markdown:, prompt:) { extraction }) do
        yield
      end
    end
  end

  test "happy path: transitions to done and stores the validated result" do
    job = new_job
    with_pipeline(
      html: "<html><body><h1>Widgets</h1><p>Widget A</p></body></html>",
      extraction: { "items" => [{ "name" => "Widget A" }], "notes" => "" }
    ) do
      ScrapeJobProcessor.perform_now(job.id)
    end

    job.reload
    assert job.done?, "expected done, was #{job.status}"
    assert_equal [{ "name" => "Widget A" }], job.result["items"]
    assert_nil job.error_message
  end

  test "fetch failure marks the job failed with the message, does not raise" do
    job = new_job
    stub_class_method(Fetcher, :call, ->(_url) { raise Fetcher::FetchError, "boom" }) do
      assert_nothing_raised { ScrapeJobProcessor.perform_now(job.id) }
    end

    job.reload
    assert job.failed?
    assert_equal "boom", job.error_message
  end

  test "a blocked (SSRF) url is a failed job with a clear message" do
    job = new_job
    stub_class_method(Fetcher, :call, ->(_url) { raise Fetcher::BlockedError, "Refusing to fetch a private or internal address" }) do
      ScrapeJobProcessor.perform_now(job.id)
    end

    job.reload
    assert job.failed?
    assert_match(/private or internal/, job.error_message)
  end

  test "extraction failure marks the job failed" do
    job = new_job
    stub_class_method(Fetcher, :call, ->(_url) { "<html><body>ok</body></html>" }) do
      stub_class_method(Extractor, :call, ->(**) { raise Extractor::ExtractionError, "api down" }) do
        ScrapeJobProcessor.perform_now(job.id)
      end
    end

    job.reload
    assert job.failed?
    assert_equal "api down", job.error_message
  end

  test "invalid extraction shape fails validation and marks the job failed" do
    job = new_job
    with_pipeline(
      html: "<html><body>ok</body></html>",
      extraction: { "items" => "not-an-array" } # Validator (real) rejects this
    ) do
      ScrapeJobProcessor.perform_now(job.id)
    end

    job.reload
    assert job.failed?
    assert_match(/validation/i, job.error_message)
  end

  test "unexpected error marks failed and re-raises" do
    job = new_job
    stub_class_method(Fetcher, :call, ->(_url) { raise "kaboom" }) do
      assert_raises(RuntimeError) { ScrapeJobProcessor.perform_now(job.id) }
    end

    job.reload
    assert job.failed?
    assert_match(/Unexpected error/, job.error_message)
  end
end
