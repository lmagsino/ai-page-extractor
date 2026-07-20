# ScrapeJob: one extraction request and its lifecycle.
#
# State machine (status enum, string-backed):
#
#   pending ──► fetching ──► extracting ──► done
#      │           │             │
#      └───────────┴─────────────┴──► failed  (error_message set; user can resubmit)
#
# Each transition is driven by ScrapeJobProcessor as it walks the
# fetch -> clean -> extract -> validate pipeline. `featured` marks curated
# gallery items surfaced on the public index; ordinary user runs stay unlisted
# (viewable only via their own show URL).
class ScrapeJob < ApplicationRecord
  STATUSES = %w[pending fetching extracting done failed].freeze

  enum :status, STATUSES.index_with(&:itself), default: "pending", validate: true

  validates :url, presence: true,
                  format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]),
                            message: "must be a valid http(s) URL" }
  validates :prompt, presence: true

  scope :gallery, -> { where(featured: true).order(created_at: :desc) }

  # Live updates: whenever the record changes (status transition, result stored),
  # push a replacement of the show-page panel to anyone subscribed to this job's
  # stream. Replaces the old JS polling loop.
  after_update_commit :broadcast_panel

  # Stable DOM id for the show-page panel (target of the Turbo Stream replace).
  def panel_dom_id
    "scrape_job_#{id}_panel"
  end

  # Parsed extraction result, or nil if not done / unparseable.
  def result
    return nil if result_json.blank?

    JSON.parse(result_json)
  rescue JSON::ParserError
    nil
  end

  def result=(hash)
    self.result_json = hash.nil? ? nil : hash.to_json
  end

  private

  def broadcast_panel
    broadcast_replace_to self,
                         target: panel_dom_id,
                         partial: "scrapes/panel",
                         locals: { scrape_job: self }
  end
end
