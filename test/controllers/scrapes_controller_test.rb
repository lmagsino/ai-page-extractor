require "test_helper"

class ScrapesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "new renders the form" do
    get new_scrape_path
    assert_response :success
    assert_select "form"
  end

  test "root routes to the new form" do
    get root_path
    assert_response :success
  end

  test "index shows only featured gallery jobs, not user submissions" do
    featured = ScrapeJob.create!(url: "https://featured.example.com/a", prompt: "curated", featured: true, status: "done")
    user_run = ScrapeJob.create!(url: "https://private.example.com/secret", prompt: "someone's run", featured: false, status: "done")

    get scrapes_path
    assert_response :success
    assert_includes @response.body, featured.url
    assert_not_includes @response.body, user_run.url
  end

  test "create with valid params saves, enqueues the job, and redirects" do
    assert_enqueued_with(job: ScrapeJobProcessor) do
      assert_difference "ScrapeJob.count", 1 do
        post scrapes_path, params: { scrape_job: { url: "https://example.com/x", prompt: "extract names" } }
      end
    end
    assert_redirected_to scrape_path(ScrapeJob.last)
    assert ScrapeJob.last.pending?
  end

  test "create with invalid params re-renders with 422 and does not enqueue" do
    assert_no_enqueued_jobs do
      assert_no_difference "ScrapeJob.count" do
        post scrapes_path, params: { scrape_job: { url: "not-a-url", prompt: "" } }
      end
    end
    assert_response :unprocessable_entity
  end

  test "show renders an existing job" do
    job = ScrapeJob.create!(url: "https://example.com/x", prompt: "extract")
    get scrape_path(job)
    assert_response :success
    assert_includes @response.body, job.url
  end

  test "show returns 404 for a missing job" do
    get scrape_path(id: 999_999)
    assert_response :not_found
  end

  test "status returns the job's state as json" do
    job = ScrapeJob.create!(url: "https://example.com/x", prompt: "extract", status: "done")
    job.update!(result: { "items" => [ { "name" => "A" } ], "notes" => "" })

    get status_scrape_path(job)
    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal "done", body["status"]
    assert_equal [ { "name" => "A" } ], body["result"]["items"]
  end

  test "export returns the result as a CSV with union-of-keys headers" do
    job = ScrapeJob.create!(url: "https://example.com/x", prompt: "extract", status: "done")
    job.update!(result: { "items" => [
      { "name" => "A", "price" => "$1" },
      { "name" => "B", "stock" => "3" }
    ], "notes" => "" })

    get export_scrape_path(job, format: :csv)
    assert_response :success
    assert_match %r{text/csv}, @response.media_type
    lines = @response.body.strip.split("\n")
    assert_equal "name,price,stock", lines[0]
    assert_equal "A,$1,", lines[1]      # missing stock -> empty cell, aligned
    assert_equal "B,,3", lines[2]        # missing price -> empty cell, aligned
  end

  test "export is 404 when the job is not done" do
    job = ScrapeJob.create!(url: "https://example.com/x", prompt: "extract") # pending
    get export_scrape_path(job, format: :csv)
    assert_response :not_found
  end
end
