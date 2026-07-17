class CreateScrapeJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :scrape_jobs do |t|
      t.string  :url,           null: false
      t.text    :prompt,        null: false
      t.string  :status,        null: false, default: "pending" # pending -> fetching -> extracting -> done/failed
      t.text    :result_json
      t.text    :error_message
      t.boolean :featured,      null: false, default: false      # curated gallery items shown on the public index

      t.timestamps
    end

    add_index :scrape_jobs, :status
    add_index :scrape_jobs, :featured
  end
end
