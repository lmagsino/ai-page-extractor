class AddTruncatedToScrapeJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :scrape_jobs, :truncated, :boolean, null: false, default: false
  end
end
