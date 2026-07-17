# Orchestrates the fetch -> clean -> extract -> validate pipeline for a single
# ScrapeJob, keeping its status current so the UI can follow along.
#
#   pending ─► fetching ─► extracting ─► done
#      (Fetcher)   (Cleaner)  (Extractor+Validator)
#
# Known pipeline errors (fetch/extract/validate) are terminal-but-expected:
# the job is marked `failed` with a user-facing message and NOT re-raised.
# Anything unexpected is also recorded as failed, then re-raised so it surfaces
# in logs and Solid Queue's failed-jobs view.
class ScrapeJobProcessor < ApplicationJob
  queue_as :default

  PIPELINE_ERRORS = [
    Fetcher::FetchError,
    Extractor::ExtractionError,
    Validator::ValidationError
  ].freeze

  def perform(scrape_job_id)
    job = ScrapeJob.find(scrape_job_id)

    job.fetching!
    html = Fetcher.call(job.url)
    cleaned = Cleaner.call(html)

    job.extracting!
    raw = Extractor.call(markdown: cleaned.text, prompt: job.prompt)
    validated = Validator.call(raw)

    job.update!(status: "done", result: validated)
  rescue *PIPELINE_ERRORS => e
    job&.update!(status: "failed", error_message: e.message)
  rescue StandardError => e
    job&.update!(status: "failed", error_message: "Unexpected error: #{e.message}")
    raise
  end
end
