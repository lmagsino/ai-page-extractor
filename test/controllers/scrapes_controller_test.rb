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
end
