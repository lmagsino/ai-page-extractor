require "csv"

class ScrapesController < ApplicationController
  # Public index shows ONLY curated gallery items (2A) — never other users'
  # submissions. A user's own run is reachable via its show URL, not listed here.
  def index
    @scrape_jobs = ScrapeJob.gallery.limit(50)
  end

  def new
    @scrape_job = ScrapeJob.new
  end

  def create
    @scrape_job = ScrapeJob.new(scrape_job_params)

    if @scrape_job.save
      ScrapeJobProcessor.perform_later(@scrape_job.id)
      redirect_to scrape_path(@scrape_job)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @scrape_job = ScrapeJob.find(params[:id])
  end

  # JSON polling endpoint the show page uses to follow background progress.
  # (Turbo Streams will supersede polling in M2; this stays as the fallback.)
  def status
    job = ScrapeJob.find(params[:id])
    render json: {
      status: job.status,
      result: job.result,
      error_message: job.error_message
    }
  end

  # Download a finished extraction as CSV. Columns are the union of item keys
  # (ScrapeJob#result_columns), matching the on-screen table.
  def export
    job = ScrapeJob.find(params[:id])
    unless job.done? && job.result_items.any?
      head :not_found and return
    end

    columns = job.result_columns
    csv = CSV.generate do |out|
      out << columns
      job.result_items.each { |item| out << columns.map { |c| item[c] } }
    end

    send_data csv, filename: "extraction-#{job.id}.csv", type: "text/csv", disposition: "attachment"
  end

  private

  def scrape_job_params
    params.require(:scrape_job).permit(:url, :prompt)
  end
end
